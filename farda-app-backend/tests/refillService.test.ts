import {
	computeRefill,
	DEFAULT_REFILL_LEAD_DAYS,
	dailyRateFromSchedule,
	parseQty,
	stubPharmacyProvider,
} from "@src/services/RefillService";
import { describe, expect, it } from "vitest";

/**
 * Pure-function tests for the refill depletion / refill-due calc (GTM-541).
 * No DB, no Express — deterministic and CI-friendly, matching unit.test.ts.
 */

describe("parseQty", () => {
	it("parses a plain integer", () => {
		expect(parseQty("30")).toBe(30);
	});
	it("parses the leading number out of free text", () => {
		expect(parseQty("30 tablets")).toBe(30);
		expect(parseQty("qty 90")).toBe(90);
	});
	it("floors a decimal qty", () => {
		expect(parseQty("30.5")).toBe(30);
	});
	it("returns null for non-numeric / null / negative", () => {
		expect(parseQty("none")).toBeNull();
		expect(parseQty(null)).toBeNull();
		expect(parseQty(undefined)).toBeNull();
		expect(parseQty("-5")).toBeNull();
	});
});

describe("dailyRateFromSchedule", () => {
	it("returns 0 for an empty schedule", () => {
		expect(dailyRateFromSchedule([])).toBe(0);
	});
	it("counts 1/day when one dose per distinct day", () => {
		const dates = [
			new Date("2026-06-01T09:00:00Z"),
			new Date("2026-06-02T09:00:00Z"),
			new Date("2026-06-03T09:00:00Z"),
		];
		expect(dailyRateFromSchedule(dates)).toBe(1);
	});
	it("counts 2/day when two doses share each day", () => {
		const dates = [
			new Date("2026-06-01T09:00:00Z"),
			new Date("2026-06-01T21:00:00Z"),
			new Date("2026-06-02T09:00:00Z"),
			new Date("2026-06-02T21:00:00Z"),
		];
		expect(dailyRateFromSchedule(dates)).toBe(2);
	});
});

describe("computeRefill", () => {
	const now = new Date("2026-06-27T00:00:00Z");

	it("computes days-left, depletion and refill-due from qty + rate (estimated)", () => {
		const r = computeRefill({
			initialQty: 30,
			dosesTaken: 0,
			dailyRate: 1,
			now,
		});
		expect(r.remaining).toBe(30);
		expect(r.remainingSource).toBe("estimated");
		expect(r.daysLeft).toBe(30);
		// depletion = now + 30 days = 2026-07-27
		expect(r.predictedDepletion).toBe("2026-07-27");
		// refill-due = depletion - 7 = 2026-07-20
		expect(r.refillDue).toBe("2026-07-20");
		expect(r.isRefillDue).toBe(false);
	});

	it("subtracts doses taken from initial qty", () => {
		const r = computeRefill({
			initialQty: 30,
			dosesTaken: 10,
			dailyRate: 2,
			now,
		});
		expect(r.remaining).toBe(20);
		expect(r.daysLeft).toBe(10); // 20 / 2
	});

	it("flags isRefillDue when refill-due is today/past (low supply)", () => {
		const r = computeRefill({
			initialQty: 5,
			dosesTaken: 0,
			dailyRate: 1,
			now,
			leadTimeDays: DEFAULT_REFILL_LEAD_DAYS,
		});
		// 5 days left, depletion = now+5; refill-due = now+5-7 = now-2 (past)
		expect(r.daysLeft).toBe(5);
		expect(r.isRefillDue).toBe(true);
	});

	it("prefers a measured (weight-sensor) reading over the qty estimate", () => {
		const r = computeRefill({
			initialQty: 30,
			dosesTaken: 0,
			dailyRate: 1,
			measuredRemaining: 12,
			now,
		});
		expect(r.remaining).toBe(12);
		expect(r.remainingSource).toBe("measured");
		expect(r.daysLeft).toBe(12);
	});

	it("clamps remaining at 0 and reports due when depleted", () => {
		const r = computeRefill({
			initialQty: 10,
			dosesTaken: 25,
			dailyRate: 1,
			now,
		});
		expect(r.remaining).toBe(0);
		expect(r.isRefillDue).toBe(true);
	});

	it("returns nulls when qty is unknown", () => {
		const r = computeRefill({
			initialQty: null,
			dosesTaken: 0,
			dailyRate: 1,
			now,
		});
		expect(r.remaining).toBeNull();
		expect(r.daysLeft).toBeNull();
		expect(r.predictedDepletion).toBeNull();
		expect(r.refillDue).toBeNull();
	});

	it("returns nulls when the daily rate is unknown (<= 0)", () => {
		const r = computeRefill({
			initialQty: 30,
			dosesTaken: 0,
			dailyRate: 0,
			now,
		});
		expect(r.remaining).toBe(30);
		expect(r.daysLeft).toBeNull();
		expect(r.predictedDepletion).toBeNull();
	});
});

describe("stubPharmacyProvider (STUB seam only)", () => {
	it("reports the pharmacy auto-refill integration as unsupported", async () => {
		const result = await stubPharmacyProvider.submitRefill({
			rxNumber: "RX-1",
			storeNumber: "S-7",
			pharmacyName: "Acme",
		});
		expect(result.status).toBe("unsupported");
		expect(result.confirmationId).toBeNull();
	});
});
