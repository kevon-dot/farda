import { createHash, randomUUID } from "node:crypto";
import type {
	PrismaClient,
	RefillAgentRequest,
} from "../../generated/prisma/client";
import { ConsumerError } from "../reminders/policy";
import { lock, serial } from "../reminders/service";
import {
	RefillProviderError,
	type ProviderOrder,
	type RefillsProvider,
	type VerifiedProviderLink,
} from "./providers/types";

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
const terminalStates = ["delivered", "picked_up", "completed", "canceled"];
const consentText =
	"Send this refill request with the medication, pharmacy and address shown. The pharmacy will confirm availability and any payment.";

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
	) {}
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
		const status =
			request.status === "submitting" &&
			this.now().getTime() - request.createdAt.getTime() > 120_000
				? "unknown"
				: request.status;
		return {
			id: request.id,
			status,
			providerConfirmed: request.providerConfirmed,
			statusLabel: labels[status] ?? "Checking request status",
			submittedAt: request.createdAt,
			updatedAt: request.updatedAt,
			lastCheckedAt: request.lastCheckedAt,
			canRefresh:
				this.provider.configured &&
				request.environment === this.provider.environment &&
				request.status !== "failed" &&
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
	) {
		return {
			prescriptionId,
			provider: {
				name: "Photon",
				configured: this.provider.configured,
				environment: this.provider.configured
					? this.provider.environment
					: null,
			},
			canSubmit: review !== null && blockedReason === null,
			blockedReason,
			review,
			latestRequest: this.requestView(request),
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
		if (await this.active(userId, prescriptionId))
			return this.response(
				prescriptionId,
				latest,
				"A request is already in progress. Check its status before starting another.",
			);
		if (!this.provider.configured)
			return this.response(
				prescriptionId,
				latest,
				"Pharmacy requests are not connected yet. You can still prepare a request to share yourself.",
			);
		const link = await this.link(userId, prescriptionId);
		if (!link)
			return this.response(
				prescriptionId,
				latest,
				"This prescription is not linked to a verified pharmacy record. You can still prepare a request to share yourself.",
			);
		let verified: VerifiedProviderLink;
		try {
			verified = await this.verify(link);
		} catch {
			return this.response(
				prescriptionId,
				latest,
				"We could not verify this prescription for a refill. Check with your pharmacy or try reviewing it again later.",
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
		return this.response(prescriptionId, latest, null, {
			token: review.id,
			expiresAt: review.expiresAt,
			medicationName: verified.medicationName,
			instructions: verified.instructions,
			pharmacyName: verified.pharmacyName,
			deliveryAddress: verified.address,
			fillsRemaining: verified.fillsRemaining,
			consentText,
		});
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
			return this.response(
				prescriptionId,
				previous,
				"This request has already been recorded. Check its status.",
			);
		}
		if (!this.provider.configured)
			throw new ConsumerError(409, "Pharmacy requests are not connected yet.");
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
				},
			});
			return { request, send: true };
		});
		if (!reserved.send)
			return this.response(
				prescriptionId,
				reserved.request,
				"This request is already recorded.",
			);
		let request = reserved.request;
		try {
			const order = await this.provider.submitOrder({
				externalId: request.id,
				patientId: request.patientId,
				prescriptionId: request.providerPrescriptionId,
				pharmacyId: request.pharmacyId,
				address: verified.address,
			});
			this.assertOrder(request, order);
			request = await this.db.refillAgentRequest.update({
				where: { id: request.id },
				data: {
					providerOrderId: order.id,
					status: providerOrderStatus(order),
					providerConfirmed: true,
					lastCheckedAt: this.now(),
					failureCode: null,
				},
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
				},
			});
		}
		return this.response(
			prescriptionId,
			request,
			request.status === "failed"
				? "Your request was not sent. Review it again before trying another request."
				: "Your request is recorded. Check its status for verified updates.",
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
		const request = await this.latest(userId, prescriptionId);
		if (!request) return this.review(userId, prescriptionId);
		if (
			!this.provider.configured ||
			request.environment !== this.provider.environment
		)
			return this.response(
				prescriptionId,
				request,
				"The pharmacy connection is unavailable. Your recorded request is unchanged.",
			);
		if (request.status === "failed")
			return this.response(
				prescriptionId,
				request,
				"Your request was not sent. Review it again before trying another request.",
			);
		const now = this.now();
		if (
			request.status === "submitting" &&
			now.getTime() - request.createdAt.getTime() < 120_000
		)
			return this.response(
				prescriptionId,
				request,
				"Your request is still being sent. Check back in a moment.",
			);
		const claimed = await this.db.refillAgentRequest.updateMany({
			where: {
				id: request.id,
				userId,
				OR: [
					{ refreshClaimedAt: null },
					{ refreshClaimedAt: { lt: new Date(now.getTime() - 90_000) } },
				],
			},
			data: { refreshClaimedAt: now },
		});
		if (!claimed.count)
			return this.response(
				prescriptionId,
				request,
				"Status was checked recently. Give the pharmacy a moment to update.",
			);
		try {
			const order = request.providerOrderId
				? await this.provider.getOrder(request.providerOrderId)
				: await this.provider.findOrder({
						patientId: request.patientId,
						externalId: request.id,
					});
			if (!order)
				return this.response(
					prescriptionId,
					request,
					"The provider has not confirmed this request yet. Do not send it again; check back or contact your pharmacy.",
				);
			this.assertOrder(request, order);
			const incoming = providerOrderStatus(order);
			// A delayed refresh cannot roll back a newer read or a known terminal fulfillment.
			const ranks: Record<string, number> = {
				sent: 0,
				received: 1,
				ready: 2,
				shipped: 2,
			};
			const status =
				terminalStates.includes(request.status) ||
				((ranks[request.status] ?? -1) > (ranks[incoming] ?? -1) &&
					incoming !== "unknown" &&
					!terminalStates.includes(incoming))
					? request.status
					: incoming;
			await this.db.refillAgentRequest.updateMany({
				where: { id: request.id, userId, refreshClaimedAt: now },
				data: {
					providerOrderId: order.id,
					status,
					providerConfirmed: true,
					lastCheckedAt: now,
					failureCode: null,
				},
			});
			const updated = await this.db.refillAgentRequest.findFirst({
				where: { id: request.id, userId },
			});
			return this.response(
				prescriptionId,
				updated,
				"Status comes from the provider. Your supply count changes only when you confirm a receipt.",
			);
		} catch {
			return this.response(
				prescriptionId,
				request,
				"We could not check the provider just now. Your recorded request is unchanged; do not send it again.",
			);
		}
	}
}
