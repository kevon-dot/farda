import { describe, expect, it, vi } from "vitest";
import type {
	ProviderOrder,
	RefillsProvider,
} from "../src/refills/providers/types";
import {
	type RefillReconciliationEvent,
	RefillReconciliationService,
	refillReconciliationBackoffMs,
	startRefillReconciliationWorker,
} from "../src/refills/reconciliation";
import { memoryDb } from "./consumer-memory-db";

const start = new Date("2026-10-17T00:00:00.000Z");

function fixture(
	input: {
		status?: string;
		attempts?: number;
		providerOrderId?: string | null;
		configured?: boolean;
	} = {},
) {
	let now = start;
	const events: RefillReconciliationEvent[] = [];
	const request = {
		id: "request-secret",
		userId: "patient-secret",
		prescriptionId: "prescription-secret",
		reviewId: "review-secret",
		requestKey: "key-secret",
		environment: "sandbox",
		patientId: "photon-patient-secret",
		providerPrescriptionId: "photon-rx-secret",
		pharmacyId: "pharmacy-secret",
		providerOrderId: input.providerOrderId ?? null,
		status: input.status ?? "unknown",
		providerConfirmed: false,
		failureCode: null,
		lastCheckedAt: null,
		refreshClaimedAt: null,
		reconcileAttempts: input.attempts ?? 0,
		nextReconcileAt: start,
		operatorAlertedAt: null,
		createdAt: new Date(start.getTime() - 10 * 60_000),
		updatedAt: start,
	};
	const db = memoryDb({ refillAgentRequest: [request] });
	const order = (
		state = "PENDING",
		fulfillmentState: string | null = null,
	): ProviderOrder => ({
		id: "order-secret",
		externalId: request.id,
		patientId: request.patientId,
		prescriptionIds: [request.providerPrescriptionId],
		pharmacyId: request.pharmacyId,
		orderState: state,
		fulfillmentType: fulfillmentState ? "PICK_UP" : null,
		fulfillmentState,
	});
	const provider = {
		configured: input.configured ?? true,
		environment: "sandbox" as const,
		capabilities: {
			verifyEligibility: true,
			submitOrders: true,
			lookupOrders: true,
			reconcileUnknownOutcomes: true,
		},
		verifyLink: vi.fn(),
		submitOrder: vi.fn(),
		getOrder: vi.fn(async () => null as ProviderOrder | null),
		findOrder: vi.fn(async () => null as ProviderOrder | null),
	} satisfies RefillsProvider;
	const service = new RefillReconciliationService(
		db.db,
		provider,
		() => now,
		(event) => events.push(event),
	);
	return {
		...db,
		provider,
		service,
		events,
		order,
		advance: (ms: number) => {
			now = new Date(now.getTime() + ms);
		},
	};
}

describe("persisted Photon order reconciliation", () => {
	it("uses bounded exponential backoff", () => {
		expect([1, 2, 3, 4].map(refillReconciliationBackoffMs)).toEqual([
			60_000, 120_000, 240_000, 480_000,
		]);
		expect(refillReconciliationBackoffMs(100)).toBe(6 * 60 * 60_000);
	});

	it("fails closed without configuration and emits no identifying telemetry", async () => {
		const f = fixture({ configured: false });
		expect(await f.service.tick()).toEqual({
			considered: 0,
			claimed: 0,
			terminal: 0,
			retried: 0,
			alerts: 0,
		});
		expect(f.provider.getOrder).not.toHaveBeenCalled();
		expect(f.provider.findOrder).not.toHaveBeenCalled();
		expect(JSON.stringify(f.events)).not.toMatch(/secret/);
		expect(f.events).toContainEqual(
			expect.objectContaining({
				outcome: "blocked",
				reasonCode: "provider_not_configured",
			}),
		);
	});

	it("leases each due attempt once and persists retry timing across ticks", async () => {
		const f = fixture();
		const [first, competing] = await Promise.all([
			f.service.tick(),
			f.service.tick(),
		]);
		expect(first.claimed + competing.claimed).toBe(1);
		expect(f.provider.findOrder).toHaveBeenCalledTimes(1);
		const row = f.rows("refillAgentRequest")[0];
		expect(row).toMatchObject({
			status: "unknown",
			reconcileAttempts: 1,
			refreshClaimedAt: null,
		});
		expect(row.nextReconcileAt).toEqual(new Date(start.getTime() + 60_000));
		expect((await f.service.tick()).considered).toBe(0);
	});

	it("treats a null schedule from a rolling deploy as immediately due", async () => {
		const f = fixture();
		f.rows("refillAgentRequest")[0].nextReconcileAt = null;
		expect(await f.service.tick()).toMatchObject({ considered: 1, claimed: 1 });
		expect(f.provider.findOrder).toHaveBeenCalledOnce();
		expect(f.rows("refillAgentRequest")[0].nextReconcileAt).toEqual(
			new Date(start.getTime() + 60_000),
		);
	});

	it("uses fresh per-row leases and schedules from lookup completion", async () => {
		const f = fixture();
		const first = f.rows("refillAgentRequest")[0];
		first.nextReconcileAt = new Date(start.getTime() - 1_000);
		const second = structuredClone(first);
		Object.assign(second, {
			id: "request-second",
			reviewId: "review-second",
			requestKey: "key-second",
			nextReconcileAt: start,
		});
		f.rows("refillAgentRequest").push(second);
		let calls = 0;
		f.provider.findOrder.mockImplementation(async () => {
			if (calls++ === 0) f.advance(120_000);
			return null;
		});

		expect(await f.service.tick()).toMatchObject({ considered: 2, claimed: 2 });
		expect(f.rows("refillAgentRequest")[1]).toMatchObject({
			lastCheckedAt: new Date(start.getTime() + 120_000),
			refreshClaimedAt: null,
			nextReconcileAt: new Date(start.getTime() + 180_000),
		});
	});

	it("advances verified provider state without submitting or changing inventory", async () => {
		const f = fixture({ status: "sent", providerOrderId: "order-secret" });
		f.provider.getOrder.mockResolvedValueOnce(f.order("PENDING", "READY"));
		expect(await f.service.tick()).toMatchObject({ claimed: 1, terminal: 0 });
		expect(f.rows("refillAgentRequest")[0]).toMatchObject({
			status: "ready",
			providerConfirmed: true,
			reconcileAttempts: 0,
			operatorAlertedAt: null,
		});
		expect(f.provider.submitOrder).not.toHaveBeenCalled();
		expect(f.rows("inventoryEntry")).toHaveLength(0);
	});

	it("does not regress known progress for unfamiliar provider states", async () => {
		const f = fixture({ status: "ready", providerOrderId: "order-secret" });
		f.provider.getOrder.mockResolvedValueOnce(f.order("NEW_REMOTE_STATE"));
		await f.service.tick();
		expect(f.rows("refillAgentRequest")[0].status).toBe("ready");
	});

	it("stops polling terminal state and emits a one-time PHI-free attention signal", async () => {
		const f = fixture({ attempts: 4 });
		const result = await f.service.tick();
		expect(result).toMatchObject({ retried: 1, alerts: 1 });
		let row = f.rows("refillAgentRequest")[0];
		expect(row.operatorAlertedAt).toEqual(start);
		expect(JSON.stringify(f.events)).not.toMatch(/secret/);
		expect(f.events).toContainEqual(
			expect.objectContaining({
				outcome: "attention",
				reasonCode: "reconciliation_attention_required",
				attemptBucket: "5+",
			}),
		);

		f.advance(refillReconciliationBackoffMs(5));
		await f.service.tick();
		expect(
			f.events.filter((event) => event.outcome === "attention"),
		).toHaveLength(1);

		row = f.rows("refillAgentRequest")[0];
		row.nextReconcileAt = new Date(start.getTime() + 1);
		f.provider.findOrder.mockResolvedValueOnce(f.order("COMPLETED"));
		await f.service.tick();
		expect(row).toMatchObject({ status: "completed", nextReconcileAt: null });
	});

	it("drains an in-flight tick during shutdown", async () => {
		let finish = () => {};
		const tick = vi.fn(
			() =>
				new Promise<void>((resolve) => {
					finish = resolve;
				}),
		);
		const stop = startRefillReconciliationWorker(
			{ configured: true, tick },
			true,
			60_000,
		);
		expect(tick).toHaveBeenCalledOnce();
		let stopped = false;
		const draining = stop().then(() => {
			stopped = true;
		});
		await Promise.resolve();
		expect(stopped).toBe(false);
		finish();
		await draining;
		expect(stopped).toBe(true);
	});
});
