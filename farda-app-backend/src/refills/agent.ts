import { createHash, randomUUID } from "node:crypto";
import type {
	PrismaClient,
	RefillAgentRequest,
} from "../../generated/prisma/client";
import { ConsumerError } from "../reminders/policy";
import { lock, serial } from "../reminders/service";
import {
	type ProviderOrder,
	RefillProviderError,
	type RefillsProvider,
	type VerifiedProviderLink,
} from "./providers/types";
import {
	canRefreshStatus,
	isRequestStatus,
	nextAction,
	nextProviderStatus,
	type RefillReasonCode,
	type RefillRequestStatus,
	statusReason,
} from "./workflow";

const hash = (value: unknown) =>
	createHash("sha256").update(JSON.stringify(value)).digest("hex");
const activeStates = [
	"submitting",
	"unknown",
	"sent",
	"received",
	"ready",
	"shipped",
];
const labels: Record<string, string> = {
	submitting: "Sending your request",
	unknown: "Checking whether your request went through",
	sent: "Request sent to provider",
	received: "Pharmacy received your request",
	ready: "Ready for pickup",
	shipped: "Your refill has shipped",
	delivered: "Delivery reported by provider",
	picked_up: "Pickup reported by provider",
	completed: "Provider reports order complete",
	canceled: "Provider reports order canceled",
	failed: "Request was not sent",
};
const consentText =
	"Send this refill request with the medication, pharmacy and address shown. The pharmacy will confirm availability and any payment.";

const actionLabels = {
	confirm_and_submit: "Review and confirm request",
	wait: "Wait before checking again",
	refresh_status: "Check provider status",
	contact_pharmacy: "Contact your pharmacy",
	collect_refill: "Follow the pharmacy's pickup instructions",
	track_delivery: "Check delivery status",
	confirm_supply: "Confirm what you received",
	review_again: "Review a new request",
} as const;

const verificationReasons: Record<string, RefillReasonCode> = {
	provider_unavailable: "provider_not_configured",
	provider_authentication: "eligibility_check_unavailable",
	provider_timeout: "eligibility_check_unavailable",
	provider_request_failed: "eligibility_check_unavailable",
	provider_link_invalid: "link_verification_failed",
	provider_prescription_unavailable: "prescription_not_eligible",
	provider_address_missing: "delivery_address_required",
	provider_response_invalid: "eligibility_check_failed",
};

export type RefillAgentEvent = {
	operation: "review" | "submit" | "refresh";
	outcome:
		| "ready"
		| "blocked"
		| "reserved"
		| "replayed"
		| "confirmed"
		| "uncertain"
		| "failed"
		| "unchanged";
	environment: "sandbox" | "production";
	status?: RefillRequestStatus;
	reasonCode?: RefillReasonCode;
	durationMs?: number;
};

export type RefillAgentObserver = (event: RefillAgentEvent) => void;

export function providerOrderStatus(order: ProviderOrder): string {
	if (order.orderState === "CANCELED" || order.orderState === "CANCELLED")
		return "canceled";
	if (!["ROUTING", "PENDING", "PLACED", "COMPLETED"].includes(order.orderState))
		return "unknown";
	const pickup: Record<string, string> = {
		RECEIVED: "received",
		READY: "ready",
		PICKED_UP: "picked_up",
	};
	const mail: Record<string, string> = {
		FILLING: "received",
		SHIPPED: "shipped",
		DELIVERED: "delivered",
	};
	const states =
		order.fulfillmentType === "PICK_UP"
			? pickup
			: order.fulfillmentType === "MAIL_ORDER"
				? mail
				: {};
	if (order.fulfillmentState && states[order.fulfillmentState])
		return states[order.fulfillmentState];
	if (order.fulfillmentState && order.fulfillmentState !== "SENT")
		return "unknown";
	if (order.orderState === "COMPLETED") return "completed";
	return "sent";
}

export class RefillAgentService {
	constructor(
		private db: PrismaClient,
		private provider: RefillsProvider,
		private now = () => new Date(),
		private observe: RefillAgentObserver = () => undefined,
	) {}
	private event(
		event: Omit<RefillAgentEvent, "environment" | "status" | "durationMs"> & {
			status?: string;
			durationMs?: number;
		},
	) {
		try {
			const status: RefillRequestStatus | undefined = event.status
				? isRequestStatus(event.status)
					? event.status
					: "unknown"
				: undefined;
			const durationMs =
				event.durationMs === undefined
					? undefined
					: Math.max(0, Math.min(30_000, Math.round(event.durationMs)));
			this.observe({
				operation: event.operation,
				outcome: event.outcome,
				environment: this.provider.environment,
				...(event.reasonCode ? { reasonCode: event.reasonCode } : {}),
				...(status ? { status } : {}),
				...(durationMs === undefined ? {} : { durationMs }),
			});
		} catch {
			// Telemetry can never change a refill decision or expose request data.
		}
	}
	private verificationReason(error: unknown): RefillReasonCode {
		return error instanceof RefillProviderError
			? (verificationReasons[error.code] ?? "eligibility_check_failed")
			: "eligibility_check_failed";
	}
	private async owned(userId: string, prescriptionId: string) {
		const prescription = await this.db.prescription.findFirst({
			where: { id: prescriptionId, userId, archivedAt: null },
		});
		if (!prescription) throw new ConsumerError(404, "Prescription not found.");
		return prescription;
	}
	private async latest(userId: string, prescriptionId: string) {
		return this.db.refillAgentRequest.findFirst({
			where: { userId, prescriptionId },
			orderBy: { createdAt: "desc" },
		});
	}
	private requestView(request: RefillAgentRequest | null) {
		if (!request) return null;
		const rawStatus =
			request.status === "submitting" &&
			this.now().getTime() - request.createdAt.getTime() > 120_000
				? "unknown"
				: request.status;
		const status = isRequestStatus(rawStatus) ? rawStatus : "unknown";
		const action = nextAction(status);
		return {
			id: request.id,
			status,
			statusCode: status,
			providerConfirmed: request.providerConfirmed,
			statusLabel: labels[status] ?? "Checking request status",
			reasonCode: statusReason(status),
			nextStep: { action, label: actionLabels[action] },
			outcomeCertain: status !== "submitting" && status !== "unknown",
			submittedAt: request.createdAt,
			updatedAt: request.updatedAt,
			lastCheckedAt: request.lastCheckedAt,
			canRefresh:
				this.provider.configured &&
				this.provider.capabilities.lookupOrders &&
				request.environment === this.provider.environment &&
				canRefreshStatus(status) &&
				(request.providerOrderId !== null ||
					this.provider.capabilities.reconcileUnknownOutcomes) &&
				!(
					request.status === "submitting" &&
					this.now().getTime() - request.createdAt.getTime() < 120_000
				),
		};
	}
	private response(
		prescriptionId: string,
		request: RefillAgentRequest | null,
		blockedReason: string | null,
		review: unknown = null,
		reasonCode?: RefillReasonCode,
	) {
		const latestRequest = this.requestView(request);
		const resolvedReason =
			reasonCode ??
			(review !== null
				? "review_ready"
				: (latestRequest?.reasonCode ?? "eligibility_check_failed"));
		const action =
			review !== null && blockedReason === null
				? "confirm_and_submit"
				: latestRequest
					? latestRequest.nextStep.action
					: "contact_pharmacy";
		return {
			prescriptionId,
			provider: {
				name: "Photon",
				configured: this.provider.configured,
				environment: this.provider.configured
					? this.provider.environment
					: null,
				capabilities: this.provider.capabilities,
			},
			canSubmit:
				review !== null &&
				blockedReason === null &&
				this.provider.configured &&
				this.provider.capabilities.submitOrders,
			reasonCode: resolvedReason,
			blockedReason,
			nextStep: { action, label: actionLabels[action] },
			manualFallback: {
				available: true,
				action: "contact_pharmacy" as const,
				label: actionLabels.contact_pharmacy,
				message:
					"Contact the pharmacy yourself to confirm eligibility, timing, cost and delivery. Farda will not mark the request as sent or change your supply count.",
			},
			review,
			latestRequest,
		};
	}
	private async link(userId: string, prescriptionId: string) {
		return this.db.refillProviderLink.findFirst({
			where: {
				userId,
				prescriptionId,
				enabled: true,
				environment: this.provider.environment,
			},
		});
	}
	private async verify(link: {
		userId: string;
		patientId: string;
		providerPrescriptionId: string;
		pharmacyId: string;
	}) {
		return this.provider.verifyLink({
			userId: link.userId,
			patientId: link.patientId,
			prescriptionId: link.providerPrescriptionId,
			pharmacyId: link.pharmacyId,
		});
	}
	private async active(userId: string, prescriptionId: string) {
		return this.db.refillAgentRequest.findFirst({
			where: { userId, prescriptionId, status: { in: activeStates } },
		});
	}
	async review(userId: string, prescriptionId: string) {
		const prescription = await this.owned(userId, prescriptionId);
		// Bound cleanup work and retain every review attached to a submitted request.
		const expired = await this.db.refillAgentReview.findMany({
			where: { userId, expiresAt: { lt: this.now() } },
			select: { id: true },
			take: 100,
		});
		if (expired.length)
			await this.db.refillAgentReview.deleteMany({
				where: {
					id: { in: expired.map((item) => item.id) },
					userId,
					request: null,
					expiresAt: { lt: this.now() },
				},
			});
		const latest = await this.latest(userId, prescriptionId);
		const active = await this.active(userId, prescriptionId);
		if (active) {
			this.event({
				operation: "review",
				outcome: "blocked",
				reasonCode: "request_in_progress",
				status: active.status,
			});
			return this.response(
				prescriptionId,
				active,
				"A request is already in progress. Check its status before starting another.",
				null,
				"request_in_progress",
			);
		}
		if (!this.provider.configured) {
			this.event({
				operation: "review",
				outcome: "blocked",
				reasonCode: "provider_not_configured",
			});
			return this.response(
				prescriptionId,
				latest,
				"Pharmacy requests are not connected yet. You can still prepare a request to share yourself.",
				null,
				"provider_not_configured",
			);
		}
		if (
			!this.provider.capabilities.verifyEligibility ||
			!this.provider.capabilities.submitOrders
		) {
			this.event({
				operation: "review",
				outcome: "blocked",
				reasonCode: "provider_submission_unsupported",
			});
			return this.response(
				prescriptionId,
				latest,
				"This pharmacy connection cannot submit refill orders. Contact your pharmacy directly.",
				null,
				"provider_submission_unsupported",
			);
		}
		const link = await this.link(userId, prescriptionId);
		if (!link) {
			this.event({
				operation: "review",
				outcome: "blocked",
				reasonCode: "prescription_not_linked",
			});
			return this.response(
				prescriptionId,
				latest,
				"This prescription is not linked to a verified pharmacy record. You can still prepare a request to share yourself.",
				null,
				"prescription_not_linked",
			);
		}
		let verified: VerifiedProviderLink;
		const verificationStarted = Date.now();
		try {
			verified = await this.verify(link);
		} catch (error) {
			const reasonCode = this.verificationReason(error);
			this.event({
				operation: "review",
				outcome: "blocked",
				reasonCode,
				durationMs: Date.now() - verificationStarted,
			});
			return this.response(
				prescriptionId,
				latest,
				reasonCode === "prescription_not_eligible"
					? "The provider does not currently show this prescription as eligible for a refill. Contact your pharmacy for the available options."
					: reasonCode === "delivery_address_required"
						? "The provider needs a valid delivery address before it can accept this request. Contact your pharmacy to update it."
						: "We could not verify this prescription for a refill. Check with your pharmacy or try reviewing it again later.",
				null,
				reasonCode,
			);
		}
		const expiresAt = new Date(this.now().getTime() + 10 * 60_000);
		const cached = await this.db.refillAgentReview.findFirst({
			where: {
				userId,
				prescriptionId,
				snapshotHash: hash(verified),
				expiresAt: { gt: this.now() },
			},
			orderBy: { createdAt: "desc" },
		});
		const reusable =
			cached &&
			cached.localRevision.getTime() === prescription.updatedAt.getTime() &&
			cached.linkRevision.getTime() === link.updatedAt.getTime() &&
			!(await this.db.refillAgentRequest.findUnique({
				where: { reviewId: cached.id },
			}));
		const review = reusable
			? cached
			: await this.db.refillAgentReview.create({
					data: {
						id: randomUUID(),
						userId,
						prescriptionId,
						snapshot: JSON.parse(JSON.stringify(verified)),
						snapshotHash: hash(verified),
						localRevision: prescription.updatedAt,
						linkRevision: link.updatedAt,
						expiresAt,
					},
				});
		this.event({
			operation: "review",
			outcome: "ready",
			reasonCode: "review_ready",
			durationMs: Date.now() - verificationStarted,
		});
		return this.response(
			prescriptionId,
			latest,
			null,
			{
				token: review.id,
				expiresAt: review.expiresAt,
				medicationName: verified.medicationName,
				instructions: verified.instructions,
				pharmacyName: verified.pharmacyName,
				deliveryAddress: verified.address,
				fillsRemaining: verified.fillsRemaining,
				consentText,
			},
			"review_ready",
		);
	}
	async submit(
		userId: string,
		prescriptionId: string,
		input: { reviewToken: string; confirmed: boolean; idempotencyKey: string },
	) {
		await this.owned(userId, prescriptionId);
		if (!input.confirmed)
			throw new ConsumerError(
				400,
				"Review and confirm the refill request before sending.",
			);
		const previous = await this.db.refillAgentRequest.findUnique({
			where: {
				userId_requestKey: { userId, requestKey: input.idempotencyKey },
			},
		});
		if (previous) {
			if (
				previous.prescriptionId !== prescriptionId ||
				previous.reviewId !== input.reviewToken
			)
				throw new ConsumerError(
					409,
					"This request key belongs to a different refill request.",
				);
			this.event({
				operation: "submit",
				outcome: "replayed",
				reasonCode: "request_already_recorded",
				status: previous.status,
			});
			return this.response(
				prescriptionId,
				previous,
				"This request has already been recorded. Check its status.",
				null,
				"request_already_recorded",
			);
		}
		if (!this.provider.configured)
			throw new ConsumerError(409, "Pharmacy requests are not connected yet.");
		if (
			!this.provider.capabilities.verifyEligibility ||
			!this.provider.capabilities.submitOrders
		)
			throw new ConsumerError(
				409,
				"This pharmacy connection cannot submit refill orders.",
			);
		const [review, link] = await Promise.all([
			this.db.refillAgentReview.findFirst({
				where: { id: input.reviewToken, userId, prescriptionId },
			}),
			this.link(userId, prescriptionId),
		]);
		if (!review || !link || review.expiresAt <= this.now())
			throw new ConsumerError(409, "Review this refill again before sending.");
		let verified: VerifiedProviderLink;
		try {
			verified = await this.verify(link);
		} catch {
			throw new ConsumerError(
				409,
				"We could not verify this refill. Review it again or contact your pharmacy.",
			);
		}
		if (hash(verified) !== review.snapshotHash)
			throw new ConsumerError(
				409,
				"Prescription or pharmacy details changed. Review this refill again.",
			);
		const reserved = await serial(this.db, async (tx) => {
			await lock(tx, `refill-agent:${userId}`);
			const replay = await tx.refillAgentRequest.findUnique({
				where: {
					userId_requestKey: { userId, requestKey: input.idempotencyKey },
				},
			});
			if (replay) {
				if (
					replay.prescriptionId !== prescriptionId ||
					replay.reviewId !== input.reviewToken
				)
					throw new ConsumerError(
						409,
						"This request key belongs to a different refill request.",
					);
				return { request: replay, send: false };
			}
			const [current, currentLink, used, active] = await Promise.all([
				tx.prescription.findFirst({
					where: { id: prescriptionId, userId, archivedAt: null },
				}),
				tx.refillProviderLink.findFirst({
					where: {
						id: link.id,
						userId,
						prescriptionId,
						enabled: true,
						environment: this.provider.environment,
					},
				}),
				tx.refillAgentRequest.findUnique({ where: { reviewId: review.id } }),
				tx.refillAgentRequest.findFirst({
					where: {
						userId,
						environment: this.provider.environment,
						patientId: verified.patientId,
						providerPrescriptionId: verified.prescriptionId,
						status: { in: activeStates },
					},
				}),
			]);
			if (
				!current ||
				!currentLink ||
				current.updatedAt.getTime() !== review.localRevision.getTime() ||
				currentLink.updatedAt.getTime() !== review.linkRevision.getTime() ||
				review.expiresAt <= this.now()
			)
				throw new ConsumerError(
					409,
					"Details changed. Review this refill again before sending.",
				);
			if (used || active)
				throw new ConsumerError(
					409,
					"A request is already recorded. Check its status before starting another.",
				);
			const request = await tx.refillAgentRequest.create({
				data: {
					id: randomUUID(),
					userId,
					prescriptionId,
					reviewId: review.id,
					requestKey: input.idempotencyKey,
					environment: this.provider.environment,
					patientId: verified.patientId,
					providerPrescriptionId: verified.prescriptionId,
					pharmacyId: verified.pharmacyId,
					status: "submitting",
					providerConfirmed: false,
					createdAt: this.now(),
					nextReconcileAt: new Date(this.now().getTime() + 120_000),
				},
			});
			return { request, send: true };
		});
		if (!reserved.send) {
			this.event({
				operation: "submit",
				outcome: "replayed",
				reasonCode: "request_already_recorded",
				status: reserved.request.status,
			});
			return this.response(
				prescriptionId,
				reserved.request,
				"This request is already recorded.",
				null,
				"request_already_recorded",
			);
		}
		let request = reserved.request;
		this.event({
			operation: "submit",
			outcome: "reserved",
			status: request.status,
		});
		const submitStarted = Date.now();
		try {
			const order = await this.provider.submitOrder({
				externalId: request.id,
				patientId: request.patientId,
				prescriptionId: request.providerPrescriptionId,
				pharmacyId: request.pharmacyId,
				address: verified.address,
			});
			this.assertOrder(request, order);
			const status = providerOrderStatus(order);
			request = await this.db.refillAgentRequest.update({
				where: { id: request.id },
				data: {
					providerOrderId: order.id,
					status,
					providerConfirmed: true,
					lastCheckedAt: this.now(),
					failureCode: null,
					refreshClaimedAt: null,
					reconcileAttempts: 0,
					nextReconcileAt: activeStates.includes(status)
						? new Date(this.now().getTime() + 60_000)
						: null,
				},
			});
			this.event({
				operation: "submit",
				outcome: "confirmed",
				status: request.status,
				durationMs: Date.now() - submitStarted,
			});
		} catch (error) {
			// Unknown transport outcomes (including a crash after reservation) never authorize another send.
			const definite =
				error instanceof RefillProviderError &&
				error.outcome === "not_submitted";
			request = await this.db.refillAgentRequest.update({
				where: { id: request.id },
				data: {
					status: definite ? "failed" : "unknown",
					failureCode:
						error instanceof RefillProviderError
							? error.code
							: "provider_outcome_unknown",
					refreshClaimedAt: null,
					reconcileAttempts: definite ? 0 : 1,
					nextReconcileAt: definite
						? null
						: new Date(this.now().getTime() + 60_000),
				},
			});
			this.event({
				operation: "submit",
				outcome: definite ? "failed" : "uncertain",
				status: request.status,
				reasonCode: definite
					? "request_not_submitted"
					: "submission_outcome_uncertain",
				durationMs: Date.now() - submitStarted,
			});
		}
		return this.response(
			prescriptionId,
			request,
			request.status === "failed"
				? "Your request was not sent. Review it again before trying another request."
				: "Your request is recorded. Check its status for verified updates.",
			null,
			request.status === "failed"
				? "request_not_submitted"
				: request.status === "unknown"
					? "submission_outcome_uncertain"
					: "provider_status_available",
		);
	}
	private assertOrder(request: RefillAgentRequest, order: ProviderOrder) {
		if (
			order.externalId !== request.id ||
			order.patientId !== request.patientId ||
			order.pharmacyId !== request.pharmacyId ||
			order.prescriptionIds.length !== 1 ||
			order.prescriptionIds[0] !== request.providerPrescriptionId
		)
			throw new RefillProviderError("provider_response_invalid", "unknown");
	}
	async refresh(userId: string, prescriptionId: string) {
		await this.owned(userId, prescriptionId);
		let request = await this.latest(userId, prescriptionId);
		if (!request) return this.review(userId, prescriptionId);
		if (
			!this.provider.configured ||
			request.environment !== this.provider.environment
		) {
			this.event({
				operation: "refresh",
				outcome: "blocked",
				reasonCode: "provider_not_configured",
				status: request.status,
			});
			return this.response(
				prescriptionId,
				request,
				"The pharmacy connection is unavailable. Your recorded request is unchanged.",
				null,
				"provider_not_configured",
			);
		}
		if (
			!this.provider.capabilities.lookupOrders ||
			(!request.providerOrderId &&
				!this.provider.capabilities.reconcileUnknownOutcomes)
		) {
			this.event({
				operation: "refresh",
				outcome: "blocked",
				reasonCode: "provider_status_unsupported",
				status: request.status,
			});
			return this.response(
				prescriptionId,
				request,
				"This pharmacy connection cannot check this request automatically. Contact your pharmacy and do not send it again.",
				null,
				"provider_status_unsupported",
			);
		}
		const initialStatus = isRequestStatus(request.status)
			? request.status
			: "unknown";
		if (!canRefreshStatus(initialStatus)) {
			const reasonCode = statusReason(initialStatus);
			this.event({
				operation: "refresh",
				outcome: "unchanged",
				reasonCode,
				status: initialStatus,
			});
			return this.response(
				prescriptionId,
				request,
				initialStatus === "failed"
					? "Your request was not sent. Review it again before trying another request."
					: "This provider request is complete. Confirm your actual supply separately when you receive it.",
				null,
				reasonCode,
			);
		}
		const now = this.now();
		if (
			request.status === "submitting" &&
			now.getTime() - request.createdAt.getTime() < 120_000
		) {
			this.event({
				operation: "refresh",
				outcome: "unchanged",
				reasonCode: "submission_in_progress",
				status: request.status,
			});
			return this.response(
				prescriptionId,
				request,
				"Your request is still being sent. Check back in a moment.",
				null,
				"submission_in_progress",
			);
		}
		const claimed = await this.db.refillAgentRequest.updateMany({
			where: {
				id: request.id,
				userId,
				status: { in: activeStates },
				OR: [
					{ refreshClaimedAt: null },
					{ refreshClaimedAt: { lt: new Date(now.getTime() - 90_000) } },
				],
			},
			data: { refreshClaimedAt: now },
		});
		if (!claimed.count) {
			const current = await this.db.refillAgentRequest.findFirst({
				where: { id: request.id, userId },
			});
			const currentStatus = current
				? isRequestStatus(current.status)
					? current.status
					: "unknown"
				: initialStatus;
			const terminal = !canRefreshStatus(currentStatus);
			const reasonCode = terminal
				? statusReason(currentStatus)
				: "status_check_recent";
			this.event({
				operation: "refresh",
				outcome: "unchanged",
				reasonCode,
				status: currentStatus,
			});
			return this.response(
				prescriptionId,
				current ?? request,
				terminal
					? "This provider request is complete. Confirm your actual supply separately when you receive it."
					: "Status was checked recently. Give the pharmacy a moment to update.",
				null,
				reasonCode,
			);
		}
		const claimedRequest = await this.db.refillAgentRequest.findFirst({
			where: {
				id: request.id,
				userId,
				refreshClaimedAt: now,
				status: { in: activeStates },
			},
		});
		if (!claimedRequest) {
			await this.db.refillAgentRequest.updateMany({
				where: { id: request.id, userId, refreshClaimedAt: now },
				data: { refreshClaimedAt: null },
			});
			return this.response(
				prescriptionId,
				await this.latest(userId, prescriptionId),
				"Status changed while it was being checked. Your recorded request is unchanged.",
				null,
				"status_check_recent",
			);
		}
		request = claimedRequest;
		const storedStatus = isRequestStatus(request.status)
			? request.status
			: "unknown";
		const refreshStarted = Date.now();
		try {
			const order = request.providerOrderId
				? await this.provider.getOrder(request.providerOrderId)
				: await this.provider.findOrder({
						patientId: request.patientId,
						externalId: request.id,
					});
			if (!order) {
				const completedAt = this.now();
				const retryStatus =
					request.status === "submitting" ? "unknown" : storedStatus;
				const attempts = request.reconcileAttempts + 1;
				const updated = await this.db.refillAgentRequest.updateMany({
					where: { id: request.id, userId, refreshClaimedAt: now },
					data: {
						status: retryStatus,
						lastCheckedAt: completedAt,
						failureCode: "provider_status_pending",
						refreshClaimedAt: null,
						reconcileAttempts: attempts,
						nextReconcileAt: new Date(
							completedAt.getTime() +
								Math.min(
									6 * 60 * 60_000,
									60_000 * 2 ** Math.min(16, attempts - 1),
								),
						),
					},
				});
				const current = updated.count
					? await this.db.refillAgentRequest.findFirst({
							where: { id: request.id, userId },
						})
					: request;
				this.event({
					operation: "refresh",
					outcome: "unchanged",
					reasonCode: "provider_status_pending",
					status: retryStatus,
					durationMs: Date.now() - refreshStarted,
				});
				return this.response(
					prescriptionId,
					current,
					"The provider has not confirmed this request yet. Do not send it again; check back or contact your pharmacy.",
					null,
					"provider_status_pending",
				);
			}
			this.assertOrder(request, order);
			const completedAt = this.now();
			const mapped = providerOrderStatus(order);
			const incoming = isRequestStatus(mapped) ? mapped : "unknown";
			const status = nextProviderStatus(request.status, incoming);
			const terminal = !activeStates.includes(status);
			const advanced = status !== storedStatus;
			const attempts = advanced ? 0 : request.reconcileAttempts + 1;
			await this.db.refillAgentRequest.updateMany({
				where: { id: request.id, userId, refreshClaimedAt: now },
				data: {
					providerOrderId: order.id,
					status,
					providerConfirmed: true,
					lastCheckedAt: completedAt,
					failureCode: null,
					refreshClaimedAt: null,
					reconcileAttempts: attempts,
					nextReconcileAt: terminal
						? null
						: new Date(
								completedAt.getTime() +
									Math.min(
										6 * 60 * 60_000,
										60_000 * 2 ** Math.min(16, Math.max(0, attempts - 1)),
									),
							),
					...(advanced ? { operatorAlertedAt: null } : {}),
				},
			});
			const updated = await this.db.refillAgentRequest.findFirst({
				where: { id: request.id, userId },
			});
			this.event({
				operation: "refresh",
				outcome: "confirmed",
				reasonCode: statusReason(status),
				status,
				durationMs: Date.now() - refreshStarted,
			});
			return this.response(
				prescriptionId,
				updated,
				"Status comes from the provider. Your supply count changes only when you confirm a receipt.",
				null,
				statusReason(status),
			);
		} catch {
			const completedAt = this.now();
			const retryStatus =
				request.status === "submitting" ? "unknown" : storedStatus;
			const attempts = request.reconcileAttempts + 1;
			await this.db.refillAgentRequest.updateMany({
				where: { id: request.id, userId, refreshClaimedAt: now },
				data: {
					status: retryStatus,
					lastCheckedAt: completedAt,
					failureCode: "status_check_unavailable",
					refreshClaimedAt: null,
					reconcileAttempts: attempts,
					nextReconcileAt: new Date(
						completedAt.getTime() +
							Math.min(
								6 * 60 * 60_000,
								60_000 * 2 ** Math.min(16, attempts - 1),
							),
					),
				},
			});
			const current = await this.db.refillAgentRequest.findFirst({
				where: { id: request.id, userId },
			});
			this.event({
				operation: "refresh",
				outcome: "unchanged",
				reasonCode: "status_check_unavailable",
				status: retryStatus,
				durationMs: Date.now() - refreshStarted,
			});
			return this.response(
				prescriptionId,
				current,
				"We could not check the provider just now. Your recorded request is unchanged; do not send it again.",
				null,
				"status_check_unavailable",
			);
		}
	}
}
