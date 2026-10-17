import { describe, expect, it, vi } from "vitest";
import {
	providerOrderStatus,
	type RefillAgentEvent,
	RefillAgentService,
} from "../src/refills/agent";
import {
	type ProviderOrder,
	RefillProviderError,
	type RefillsProvider,
} from "../src/refills/providers/types";
import { RefillService } from "../src/refills/service";
import { memoryDb } from "./consumer-memory-db";

const date = new Date("2026-10-16T00:00:00Z");
function fixture(observe: (event: RefillAgentEvent) => void = () => undefined) {
	const f = memoryDb({
		prescription: [
			{ id: "rx", userId: "u", archivedAt: null, updatedAt: date },
		],
		refillProviderLink: [
			{
				id: "link",
				userId: "u",
				prescriptionId: "rx",
				environment: "sandbox",
				patientId: "patient",
				providerPrescriptionId: "remote-rx",
				pharmacyId: "pharmacy",
				enabled: true,
				updatedAt: date,
			},
		],
	});
	const verified = {
		patientId: "patient",
		prescriptionId: "remote-rx",
		pharmacyId: "pharmacy",
		pharmacyName: "Test pharmacy",
		medicationName: "Test medication",
		instructions: "As printed",
		fillsRemaining: 1,
		expirationDate: "2027-01-01",
		effectiveDate: "2026-01-01",
		prescriptionState: "ACTIVE",
		address: {
			street1: "Test address",
			postalCode: "11111",
			country: "USA",
			state: "NY",
			city: "Test city",
		},
	};
	const order = (id: string): ProviderOrder => ({
		id: "order",
		externalId: id,
		patientId: "patient",
		prescriptionIds: ["remote-rx"],
		pharmacyId: "pharmacy",
		orderState: "PENDING",
		fulfillmentType: null,
		fulfillmentState: null,
	});
	const provider = {
		configured: true as boolean,
		environment: "sandbox" as const,
		capabilities: {
			verifyEligibility: true,
			submitOrders: true,
			lookupOrders: true,
			reconcileUnknownOutcomes: true,
		},
		verifyLink: vi.fn(async () => structuredClone(verified)),
		submitOrder: vi.fn(async ({ externalId }) => order(externalId)),
		getOrder: vi.fn(async () => null as ProviderOrder | null),
		findOrder: vi.fn(async () => null as ProviderOrder | null),
	} satisfies RefillsProvider;
	let now = date;
	const service = new RefillAgentService(f.db, provider, () => now, observe);
	async function input() {
		const result = await service.review("u", "rx");
		return {
			reviewToken: (result.review as { token: string }).token,
			confirmed: true,
			idempotencyKey: "request-key-123",
		};
	}
	return {
		...f,
		provider,
		service,
		verified,
		order,
		input,
		advance: (ms: number) => {
			now = new Date(now.getTime() + ms);
		},
	};
}
describe("durable provider refill agent", () => {
	it("requires ownership on every read, send and refresh", async () => {
		const f = fixture();
		await expect(f.service.review("other", "rx")).rejects.toMatchObject({
			status: 404,
		});
		await expect(f.service.refresh("other", "rx")).rejects.toMatchObject({
			status: 404,
		});
		await expect(
			f.service.submit("other", "rx", await f.input()),
		).rejects.toMatchObject({ status: 404 });
		expect(f.provider.submitOrder).not.toHaveBeenCalled();
	});
	it("leaves manual work available without credentials or mapping", async () => {
		const f = fixture();
		f.provider.configured = false;
		expect(await f.service.review("u", "rx")).toMatchObject({
			canSubmit: false,
			reasonCode: "provider_not_configured",
			nextStep: { action: "contact_pharmacy" },
			manualFallback: { available: true, action: "contact_pharmacy" },
			review: null,
		});
		f.provider.configured = true;
		await f.db.refillProviderLink.update({
			where: { id: "link" },
			data: { enabled: false },
		});
		expect(await f.service.review("u", "rx")).toMatchObject({
			canSubmit: false,
			reasonCode: "prescription_not_linked",
			review: null,
		});
	});
	it("gates unsupported provider capabilities before eligibility or submission", async () => {
		const f = fixture();
		f.provider.capabilities.submitOrders = false;
		const result = await f.service.review("u", "rx");
		expect(result).toMatchObject({
			canSubmit: false,
			reasonCode: "provider_submission_unsupported",
			nextStep: { action: "contact_pharmacy" },
		});
		expect(f.provider.verifyLink).not.toHaveBeenCalled();
		expect(f.provider.submitOrder).not.toHaveBeenCalled();
	});
	it("returns stable eligibility reasons without exposing provider errors", async () => {
		const f = fixture();
		f.provider.verifyLink.mockRejectedValueOnce(
			new RefillProviderError("provider_prescription_unavailable"),
		);
		const result = await f.service.review("u", "rx");
		expect(result).toMatchObject({
			canSubmit: false,
			reasonCode: "prescription_not_eligible",
			blockedReason: expect.stringContaining("not currently show"),
		});
		expect(JSON.stringify(result)).not.toContain(
			"provider_prescription_unavailable",
		);
	});
	it("reserves once across concurrent duplicate submissions and never changes supply", async () => {
		const f = fixture(),
			input = await f.input();
		const results = await Promise.all([
			f.service.submit("u", "rx", input),
			f.service.submit("u", "rx", input),
		]);
		expect(results.map((r) => r.latestRequest?.id)[0]).toBe(
			results[1].latestRequest?.id,
		);
		expect(f.provider.submitOrder).toHaveBeenCalledTimes(1);
		expect(f.rows("refillAgentRequest")).toHaveLength(1);
		expect(f.rows("inventoryEntry")).toHaveLength(0);
		expect(f.rows("refillIntent")).toHaveLength(0);
	});
	it("requires explicit confirmation and rejects expired, changed local or changed provider reviews", async () => {
		const f = fixture(),
			input = await f.input();
		await expect(
			f.service.submit("u", "rx", { ...input, confirmed: false }),
		).rejects.toMatchObject({ status: 400 });
		f.advance(11 * 60_000);
		await expect(f.service.submit("u", "rx", input)).rejects.toMatchObject({
			status: 409,
		});
		const current = await f.input();
		f.verified.address.street1 = "Changed address";
		await expect(f.service.submit("u", "rx", current)).rejects.toMatchObject({
			status: 409,
		});
		const final = await f.input();
		await f.db.prescription.update({
			where: { id: "rx" },
			data: { medicationName: "Changed local" },
		});
		await expect(f.service.submit("u", "rx", final)).rejects.toMatchObject({
			status: 409,
		});
		expect(f.provider.submitOrder).not.toHaveBeenCalled();
	});
	it("rejects a changed key payload and a reused review with another key", async () => {
		const f = fixture(),
			input = await f.input();
		await f.service.submit("u", "rx", input);
		await expect(
			f.service.submit("u", "rx", { ...input, reviewToken: "different" }),
		).rejects.toMatchObject({ status: 409 });
		await expect(
			f.service.submit("u", "rx", { ...input, idempotencyKey: "another-key" }),
		).rejects.toMatchObject({ status: 409 });
		expect(f.provider.submitOrder).toHaveBeenCalledTimes(1);
	});
	it("keeps an uncertain send blocked even after no match is found", async () => {
		const f = fixture(),
			input = await f.input();
		f.provider.submitOrder.mockRejectedValueOnce(
			new RefillProviderError("provider_timeout", "unknown"),
		);
		const sent = await f.service.submit("u", "rx", input);
		expect(sent.latestRequest?.status).toBe("unknown");
		expect((await f.service.review("u", "rx")).canSubmit).toBe(false);
		await f.service.refresh("u", "rx");
		await f.service.submit("u", "rx", input);
		expect(f.provider.submitOrder).toHaveBeenCalledTimes(1);
		expect(f.rows("refillAgentRequest")[0].status).toBe("unknown");
	});
	it("allows a fresh review after a definite non-submission, never reuses the old attempt", async () => {
		const f = fixture(),
			input = await f.input();
		f.provider.submitOrder.mockRejectedValueOnce(
			new RefillProviderError("provider_authentication", "not_submitted"),
		);
		expect(
			(await f.service.submit("u", "rx", input)).latestRequest?.status,
		).toBe("failed");
		expect((await f.service.review("u", "rx")).canSubmit).toBe(true);
		await f.service.submit("u", "rx", input);
		expect(f.provider.submitOrder).toHaveBeenCalledTimes(1);
	});
	it("reconciles unknown by verified external ID without resending or adding stock", async () => {
		const f = fixture(),
			input = await f.input();
		f.provider.submitOrder.mockRejectedValueOnce(
			new Error("transport interruption"),
		);
		const sent = await f.service.submit("u", "rx", input);
		f.provider.findOrder.mockResolvedValueOnce({
			...f.order(sent.latestRequest!.id),
			fulfillmentType: "PICK_UP",
			fulfillmentState: "READY",
		});
		await f.db.refillAgentRequest.update({
			where: { id: sent.latestRequest!.id },
			data: { refreshClaimedAt: null },
		});
		const refreshed = await f.service.refresh("u", "rx");
		expect(refreshed.latestRequest).toMatchObject({
			status: "ready",
			providerConfirmed: true,
		});
		expect(f.provider.submitOrder).toHaveBeenCalledTimes(1);
		expect(f.rows("inventoryEntry")).toHaveLength(0);
	});
	it("rejects reconciliation with another patient's or pharmacy's order", async () => {
		const f = fixture(),
			input = await f.input();
		const sent = await f.service.submit("u", "rx", input);
		await f.db.refillAgentRequest.update({
			where: { id: sent.latestRequest!.id },
			data: { refreshClaimedAt: null },
		});
		f.provider.getOrder.mockResolvedValueOnce({
			...f.order(sent.latestRequest!.id),
			patientId: "someone-else",
			fulfillmentState: "READY",
		});
		expect((await f.service.refresh("u", "rx")).latestRequest?.status).toBe(
			"sent",
		);
	});
	it("does not equate SENT with pharmacy receipt or pickup with supply reconciliation", () => {
		const f = fixture();
		expect(
			providerOrderStatus({ ...f.order("x"), fulfillmentState: "SENT" }),
		).toBe("sent");
		expect(
			providerOrderStatus({
				...f.order("x"),
				fulfillmentType: "PICK_UP",
				fulfillmentState: "PICKED_UP",
			}),
		).toBe("picked_up");
	});
	it("reuses a still valid review and rejects unknown or mismatched fulfillment states", async () => {
		const f = fixture();
		expect((await f.input()).reviewToken).toBe((await f.input()).reviewToken);
		expect(f.rows("refillAgentReview")).toHaveLength(1);
		expect(
			providerOrderStatus({ ...f.order("x"), orderState: "UNRECOGNIZED" }),
		).toBe("unknown");
		expect(
			providerOrderStatus({
				...f.order("x"),
				fulfillmentType: "MAIL_ORDER",
				fulfillmentState: "READY",
			}),
		).toBe("unknown");
	});
	it("blocks another local prescription mapped to the same provider record", async () => {
		const f = fixture(),
			first = await f.input();
		await f.db.prescription.create({
			data: {
				id: "rx-copy",
				userId: "u",
				archivedAt: null,
				updatedAt: date,
				medicationName: "Duplicate",
			},
		});
		await f.raw.refillProviderLink.create({
			data: {
				...f.rows("refillProviderLink")[0],
				id: "copy",
				prescriptionId: "rx-copy",
			},
		});
		const second = await f.service.review("u", "rx-copy");
		await f.service.submit("u", "rx", first);
		await expect(
			f.service.submit("u", "rx-copy", {
				reviewToken: (second.review as { token: string }).token,
				confirmed: true,
				idempotencyKey: "another-rx-key",
			}),
		).rejects.toMatchObject({ status: 409 });
		expect(f.provider.submitOrder).toHaveBeenCalledTimes(1);
	});
	it("retains a terminal provider status when a later read is stale", async () => {
		const f = fixture(),
			input = await f.input();
		const sent = await f.service.submit("u", "rx", input);
		await f.db.refillAgentRequest.update({
			where: { id: sent.latestRequest!.id },
			data: { refreshClaimedAt: null, status: "picked_up" },
		});
		f.provider.getOrder.mockResolvedValueOnce(f.order(sent.latestRequest!.id));
		expect((await f.service.refresh("u", "rx")).latestRequest?.status).toBe(
			"picked_up",
		);
	});
	it("does not regress a known provider status to unknown", async () => {
		const f = fixture(),
			input = await f.input();
		const sent = await f.service.submit("u", "rx", input);
		await f.db.refillAgentRequest.update({
			where: { id: sent.latestRequest!.id },
			data: { refreshClaimedAt: null },
		});
		f.provider.getOrder.mockResolvedValueOnce({
			...f.order(sent.latestRequest!.id),
			orderState: "UNRECOGNIZED",
		});
		expect((await f.service.refresh("u", "rx")).latestRequest?.status).toBe(
			"sent",
		);
	});
	it("does not call the provider when a request is already terminal", async () => {
		const f = fixture(),
			input = await f.input();
		const sent = await f.service.submit("u", "rx", input);
		await f.db.refillAgentRequest.update({
			where: { id: sent.latestRequest!.id },
			data: { status: "delivered", refreshClaimedAt: null },
		});
		f.provider.getOrder.mockClear();
		const result = await f.service.refresh("u", "rx");
		expect(result).toMatchObject({
			reasonCode: "request_fulfilled",
			nextStep: { action: "confirm_supply" },
			latestRequest: { canRefresh: false },
		});
		expect(f.provider.getOrder).not.toHaveBeenCalled();
	});
	it("cannot reclaim and regress a request completed by the background worker", async () => {
		const f = fixture(),
			input = await f.input();
		const sent = await f.service.submit("u", "rx", input);
		if (!sent.latestRequest) throw new Error("expected a persisted request");
		f.provider.getOrder.mockClear();
		f.provider.findOrder.mockClear();
		const updateMany = f.raw.refillAgentRequest.updateMany.bind(
			f.raw.refillAgentRequest,
		);
		let raced = false;
		f.raw.refillAgentRequest.updateMany = vi.fn(async (args) => {
			if (!raced && args.data?.refreshClaimedAt instanceof Date) {
				raced = true;
				const row = f.rows("refillAgentRequest")[0];
				Object.assign(row, {
					status: "delivered",
					nextReconcileAt: null,
					refreshClaimedAt: null,
					reconcileAttempts: 0,
					updatedAt: new Date(row.updatedAt.getTime() + 1),
				});
			}
			return updateMany(args);
		});

		const result = await f.service.refresh("u", "rx");
		expect(result).toMatchObject({
			reasonCode: "request_fulfilled",
			latestRequest: { id: sent.latestRequest.id, status: "delivered" },
		});
		expect(f.rows("refillAgentRequest")[0]).toMatchObject({
			status: "delivered",
			nextReconcileAt: null,
			refreshClaimedAt: null,
		});
		expect(f.provider.getOrder).not.toHaveBeenCalled();
		expect(f.provider.findOrder).not.toHaveBeenCalled();
	});
	it("emits only bounded operational fields, without account or prescription data", async () => {
		const events: RefillAgentEvent[] = [];
		const f = fixture((event) => events.push(event));
		const input = await f.input();
		await f.service.submit("u", "rx", input);
		expect(
			events.some(
				(event) =>
					event.operation === "submit" && event.outcome === "confirmed",
			),
		).toBe(true);
		for (const event of events) {
			expect(Object.keys(event).sort()).toEqual(
				expect.arrayContaining(["environment", "operation", "outcome"]),
			);
			const serialized = JSON.stringify(event);
			expect(serialized).not.toContain("patient");
			expect(serialized).not.toContain("remote-rx");
			expect(serialized).not.toContain("Test address");
		}
	});
	it("batches only owned active prescription inventory and includes missing counts", async () => {
		const f = fixture();
		await f.db.prescription.create({
			data: {
				id: "other-rx",
				userId: "other",
				archivedAt: null,
				medicationName: "Other",
			},
		});
		await f.db.prescription.create({
			data: {
				id: "archived",
				userId: "u",
				archivedAt: date,
				medicationName: "Archived",
			},
		});
		const result = await new RefillService(f.db).list("u");
		expect(result.inventories).toHaveLength(1);
		expect(result.inventories[0]).toMatchObject({
			prescriptionId: "rx",
			inventory: null,
			estimate: null,
		});
	});
});
