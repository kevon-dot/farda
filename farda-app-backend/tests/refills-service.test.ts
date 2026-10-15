import { describe, expect, it } from "vitest";
import { RefillService } from "../src/refills/service";
import { memoryDb } from "./consumer-memory-db";

function fixture() {
	const f = memoryDb({ prescription: [{ id: "p1", userId: "u1" }] });
	return { ...f, service: new RefillService(f.db) };
}
const count = {
	quantity: 6,
	observedAt: new Date("2026-10-01T09:00Z"),
	idempotencyKey: "count-request-1",
};
describe("manual refill planning and supply reconciliation", () => {
	it("creates one active plan on repeated planning and labels self report", async () => {
		const f = fixture();
		const one = await f.service.create("u1", {
			prescriptionId: "p1",
			kind: "refill",
		});
		const two = await f.service.create("u1", {
			prescriptionId: "p1",
			kind: "refill",
		});
		expect(one.refill.id).toBe(two.refill.id);
		expect(two.duplicate).toBe(true);
		expect(one.refill.pharmacyConfirmed).toBe(false);
		expect(one.refill.userReported).toBe(true);
	});
	it("rejects another account for inventory and refill planning", async () => {
		const f = fixture();
		await expect(
			f.service.create("u2", { prescriptionId: "p1", kind: "refill" }),
		).rejects.toMatchObject({ status: 404 });
		await expect(f.service.count("u2", "p1", count)).rejects.toMatchObject({
			status: 404,
		});
	});
	it("repeating count idempotency does not create another ledger entry", async () => {
		const f = fixture();
		await f.service.count("u1", "p1", count);
		await f.service.count("u1", "p1", count);
		expect(f.rows("inventoryEntry")).toHaveLength(1);
		expect(f.rows("inventoryBalance")[0].revision).toBe(1);
	});
	it("rejects same request key with changed count", async () => {
		const f = fixture();
		await f.service.count("u1", "p1", count);
		await expect(
			f.service.count("u1", "p1", { ...count, quantity: 100 }),
		).rejects.toMatchObject({ status: 409 });
		expect(f.rows("inventoryBalance")[0].quantity).toBe(6);
	});
	it("rejects count overwrite after another device updated the revision", async () => {
		const f = fixture();
		await f.service.count("u1", "p1", count);
		await expect(
			f.service.count("u1", "p1", {
				...count,
				idempotencyKey: "count-request-2",
				quantity: 4,
				revision: 0,
			}),
		).rejects.toMatchObject({ status: 409 });
	});
	it("cannot add stock before user reports receipt", async () => {
		const f = fixture();
		await f.service.count("u1", "p1", count);
		const { refill } = await f.service.create("u1", {
			prescriptionId: "p1",
			kind: "refill",
		});
		await expect(
			f.service.receipt("u1", refill.id, {
				quantity: 30,
				inventoryRevision: 1,
				alreadyIncluded: false,
				idempotencyKey: "receipt-request-1",
			}),
		).rejects.toMatchObject({ status: 409 });
		expect(f.rows("inventoryBalance")[0].quantity).toBe(6);
	});
	it("receipt status alone does not change stock; explicit addition happens once", async () => {
		const f = fixture();
		await f.service.count("u1", "p1", count);
		const { refill } = await f.service.create("u1", {
			prescriptionId: "p1",
			kind: "refill",
		});
		await f.service.status("u1", refill.id, "received");
		expect(f.rows("inventoryBalance")[0].quantity).toBe(6);
		const input = {
			quantity: 30,
			inventoryRevision: 1,
			alreadyIncluded: false,
			idempotencyKey: "receipt-request-1",
		};
		const [one, two] = await Promise.all([
			f.service.receipt("u1", refill.id, input),
			f.service.receipt("u1", refill.id, input),
		]);
		expect(one.inventory?.quantity).toBe(36);
		expect(two.duplicate).toBe(true);
		expect(f.rows("inventoryBalance")[0].quantity).toBe(36);
		expect(
			f.rows("inventoryEntry").filter((e) => e.kind === "receipt"),
		).toHaveLength(1);
	});
	it("new idempotency key still cannot duplicate same receipt", async () => {
		const f = fixture();
		await f.service.count("u1", "p1", count);
		const { refill } = await f.service.create("u1", {
			prescriptionId: "p1",
			kind: "refill",
		});
		await f.service.status("u1", refill.id, "received");
		const input = {
			quantity: 30,
			inventoryRevision: 1,
			alreadyIncluded: false,
			idempotencyKey: "receipt-request-1",
		};
		await f.service.receipt("u1", refill.id, input);
		const result = await f.service.receipt("u1", refill.id, {
			...input,
			idempotencyKey: "receipt-request-2",
		});
		expect(result.duplicate).toBe(true);
		expect(f.rows("inventoryBalance")[0].quantity).toBe(36);
	});
	it("already-included supply records receipt without adding again", async () => {
		const f = fixture();
		await f.service.count("u1", "p1", count);
		const { refill } = await f.service.create("u1", {
			prescriptionId: "p1",
			kind: "refill",
		});
		await f.service.status("u1", refill.id, "received");
		const result = await f.service.receipt("u1", refill.id, {
			quantity: 30,
			inventoryRevision: 1,
			alreadyIncluded: true,
			idempotencyKey: "receipt-request-1",
		});
		expect(result.inventory?.quantity).toBe(6);
		expect(result.receipt.delta).toBe(0);
		expect(result.receipt.quantity).toBe(30);
	});
	it("blocks an older receipt from being added to a newer count", async () => {
		const f = fixture();
		await f.service.count("u1", "p1", {
			...count,
			observedAt: new Date(Date.now() + 1000),
		});
		const { refill } = await f.service.create("u1", {
			prescriptionId: "p1",
			kind: "refill",
		});
		await f.service.status("u1", refill.id, "received");
		await expect(
			f.service.receipt("u1", refill.id, {
				quantity: 30,
				inventoryRevision: 1,
				alreadyIncluded: false,
				idempotencyKey: "receipt-request-1",
			}),
		).rejects.toMatchObject({ status: 409 });
	});
});
