import type {
	PrismaClient,
	RefillAgentRequest,
} from "../../generated/prisma/client";
import { providerOrderStatus } from "./agent";
import type { ProviderOrder, RefillsProvider } from "./providers/types";
import {
	isRequestStatus,
	nextProviderStatus,
	type RefillRequestStatus,
} from "./workflow";

export const RECONCILABLE_REFILL_STATUSES = [
	"submitting",
	"unknown",
	"sent",
	"received",
	"ready",
	"shipped",
] as const;

const LEASE_MS = 90_000;
const SUBMISSION_GRACE_MS = 120_000;
const BASE_BACKOFF_MS = 60_000;
const MAX_BACKOFF_MS = 6 * 60 * 60_000;
const ALERT_AFTER_ATTEMPTS = 5;

export function refillReconciliationBackoffMs(attempt: number): number {
	const exponent = Math.max(0, Math.min(16, Math.trunc(attempt) - 1));
	return Math.min(MAX_BACKOFF_MS, BASE_BACKOFF_MS * 2 ** exponent);
}

type AttemptBucket = "1-2" | "3-4" | "5+";
export type RefillReconciliationEvent = {
	operation: "reconcile";
	outcome:
		| "blocked"
		| "claimed"
		| "advanced"
		| "unchanged"
		| "retry_scheduled"
		| "attention"
		| "terminal";
	environment: "sandbox" | "production";
	status?: RefillRequestStatus;
	reasonCode:
		| "provider_not_configured"
		| "provider_status_pending"
		| "status_check_unavailable"
		| "provider_status_available"
		| "reconciliation_attention_required";
	attemptBucket?: AttemptBucket;
	durationMs?: number;
};

export type RefillReconciliationObserver = (
	event: RefillReconciliationEvent,
) => void;

type TickResult = {
	considered: number;
	claimed: number;
	terminal: number;
	retried: number;
	alerts: number;
};

function attemptBucket(attempt: number): AttemptBucket {
	return attempt >= 5 ? "5+" : attempt >= 3 ? "3-4" : "1-2";
}

function assertOrder(request: RefillAgentRequest, order: ProviderOrder) {
	if (
		order.externalId !== request.id ||
		order.patientId !== request.patientId ||
		order.pharmacyId !== request.pharmacyId ||
		order.prescriptionIds.length !== 1 ||
		order.prescriptionIds[0] !== request.providerPrescriptionId
	)
		throw new Error("provider_order_mismatch");
}

/**
 * Read-only Photon reconciliation. It never verifies eligibility or calls the
 * order mutation. Every retry and lease is persisted so restarts are harmless.
 */
export class RefillReconciliationService {
	constructor(
		private readonly db: PrismaClient,
		private readonly provider: RefillsProvider,
		private readonly now = () => new Date(),
		private readonly observe: RefillReconciliationObserver = () => undefined,
	) {}

	get configured() {
		return this.provider.configured && this.provider.capabilities.lookupOrders;
	}

	private event(event: Omit<RefillReconciliationEvent, "environment">) {
		try {
			this.observe({ ...event, environment: this.provider.environment });
		} catch {
			// Operational telemetry cannot affect persisted order state.
		}
	}

	async tick(limit = 50): Promise<TickResult> {
		const result: TickResult = {
			considered: 0,
			claimed: 0,
			terminal: 0,
			retried: 0,
			alerts: 0,
		};
		if (!this.configured) {
			this.event({
				operation: "reconcile",
				outcome: "blocked",
				reasonCode: "provider_not_configured",
			});
			return result;
		}
		const now = this.now();
		const due = await this.db.refillAgentRequest.findMany({
			where: {
				environment: this.provider.environment,
				status: { in: [...RECONCILABLE_REFILL_STATUSES] },
				nextReconcileAt: { lte: now },
				OR: [
					{ refreshClaimedAt: null },
					{
						refreshClaimedAt: {
							lt: new Date(now.getTime() - LEASE_MS),
						},
					},
				],
			},
			orderBy: { nextReconcileAt: "asc" },
			take: Math.max(1, Math.min(100, Math.trunc(limit))),
		});
		result.considered = due.length;
		for (const request of due) {
			const outcome = await this.reconcile(request, now);
			if (!outcome) continue;
			result.claimed++;
			if (outcome.terminal) result.terminal++;
			if (outcome.retried) result.retried++;
			if (outcome.alerted) result.alerts++;
		}
		return result;
	}

	private async reconcile(request: RefillAgentRequest, now: Date) {
		const claimed = await this.db.refillAgentRequest.updateMany({
			where: {
				id: request.id,
				environment: this.provider.environment,
				status: { in: [...RECONCILABLE_REFILL_STATUSES] },
				nextReconcileAt: { lte: now },
				OR: [
					{ refreshClaimedAt: null },
					{
						refreshClaimedAt: {
							lt: new Date(now.getTime() - LEASE_MS),
						},
					},
				],
			},
			data: { refreshClaimedAt: now },
		});
		if (!claimed.count) return null;
		const status = isRequestStatus(request.status) ? request.status : "unknown";
		this.event({
			operation: "reconcile",
			outcome: "claimed",
			reasonCode: "provider_status_available",
			status,
			attemptBucket: attemptBucket(request.reconcileAttempts + 1),
		});

		if (
			request.status === "submitting" &&
			now.getTime() - request.createdAt.getTime() < SUBMISSION_GRACE_MS
		) {
			await this.db.refillAgentRequest.updateMany({
				where: { id: request.id, refreshClaimedAt: now },
				data: {
					refreshClaimedAt: null,
					nextReconcileAt: new Date(
						request.createdAt.getTime() + SUBMISSION_GRACE_MS,
					),
				},
			});
			return { terminal: false, retried: false, alerted: false };
		}

		const started = Date.now();
		try {
			const order = request.providerOrderId
				? await this.provider.getOrder(request.providerOrderId)
				: await this.provider.findOrder({
						patientId: request.patientId,
						externalId: request.id,
					});
			if (!order)
				return this.scheduleRetry(
					request,
					now,
					request.status === "submitting" ? "unknown" : status,
					"provider_status_pending",
					Date.now() - started,
				);

			assertOrder(request, order);
			const mapped = providerOrderStatus(order);
			const incoming = isRequestStatus(mapped) ? mapped : "unknown";
			const next = nextProviderStatus(status, incoming);
			const terminal = !RECONCILABLE_REFILL_STATUSES.includes(
				next as (typeof RECONCILABLE_REFILL_STATUSES)[number],
			);
			const advanced = next !== status;
			const attempts = advanced ? 0 : request.reconcileAttempts + 1;
			const nextAt = terminal
				? null
				: new Date(
						now.getTime() + refillReconciliationBackoffMs(attempts || 1),
					);
			const updated = await this.db.refillAgentRequest.updateMany({
				where: { id: request.id, refreshClaimedAt: now },
				data: {
					providerOrderId: order.id,
					status: next,
					providerConfirmed: true,
					lastCheckedAt: now,
					failureCode: null,
					refreshClaimedAt: null,
					reconcileAttempts: attempts,
					nextReconcileAt: nextAt,
					...(advanced ? { operatorAlertedAt: null } : {}),
				},
			});
			if (!updated.count)
				return { terminal: false, retried: false, alerted: false };
			this.event({
				operation: "reconcile",
				outcome: terminal ? "terminal" : advanced ? "advanced" : "unchanged",
				reasonCode: "provider_status_available",
				status: next,
				attemptBucket: terminal ? undefined : attemptBucket(attempts || 1),
				durationMs: Math.max(0, Math.min(30_000, Date.now() - started)),
			});
			if (!terminal && !advanced && attempts >= ALERT_AFTER_ATTEMPTS)
				return this.markAttention(request, now, next, attempts, true);
			return { terminal, retried: !terminal && !advanced, alerted: false };
		} catch {
			return this.scheduleRetry(
				request,
				now,
				request.status === "submitting" ? "unknown" : status,
				"status_check_unavailable",
				Date.now() - started,
			);
		}
	}

	private async scheduleRetry(
		request: RefillAgentRequest,
		now: Date,
		status: RefillRequestStatus,
		reasonCode: "provider_status_pending" | "status_check_unavailable",
		durationMs: number,
	) {
		const attempts = request.reconcileAttempts + 1;
		const updated = await this.db.refillAgentRequest.updateMany({
			where: { id: request.id, refreshClaimedAt: now },
			data: {
				status,
				lastCheckedAt: now,
				failureCode: reasonCode,
				refreshClaimedAt: null,
				reconcileAttempts: attempts,
				nextReconcileAt: new Date(
					now.getTime() + refillReconciliationBackoffMs(attempts),
				),
			},
		});
		if (!updated.count)
			return { terminal: false, retried: false, alerted: false };
		this.event({
			operation: "reconcile",
			outcome: "retry_scheduled",
			reasonCode,
			status,
			attemptBucket: attemptBucket(attempts),
			durationMs: Math.max(0, Math.min(30_000, durationMs)),
		});
		if (attempts >= ALERT_AFTER_ATTEMPTS)
			return this.markAttention(request, now, status, attempts, true);
		return { terminal: false, retried: true, alerted: false };
	}

	private async markAttention(
		request: RefillAgentRequest,
		now: Date,
		status: RefillRequestStatus,
		attempts: number,
		retried: boolean,
	) {
		const marked = await this.db.refillAgentRequest.updateMany({
			where: { id: request.id, operatorAlertedAt: null },
			data: { operatorAlertedAt: now },
		});
		if (marked.count)
			this.event({
				operation: "reconcile",
				outcome: "attention",
				reasonCode: "reconciliation_attention_required",
				status,
				attemptBucket: attemptBucket(attempts),
			});
		return { terminal: false, retried, alerted: marked.count > 0 };
	}
}

export function startRefillReconciliationWorker(
	service: Pick<RefillReconciliationService, "configured" | "tick">,
	enabled = process.env.FARDA_REFILL_RECONCILIATION_WORKER_ENABLED === "true",
	intervalMs = 30_000,
) {
	if (!enabled) return async () => {};
	let currentTick: Promise<unknown> | null = null;
	let stopped = false;
	const run = () => {
		if (stopped || currentTick) return;
		currentTick = service
			.tick()
			.catch(() => console.error("refill_reconciliation_worker_failed"))
			.finally(() => {
				currentTick = null;
			});
	};
	// Emit one fail-closed signal for a requested but unavailable connector.
	run();
	const timer = service.configured ? setInterval(run, intervalMs) : null;
	timer?.unref();
	return async () => {
		stopped = true;
		if (timer) clearInterval(timer);
		await currentTick;
	};
}
