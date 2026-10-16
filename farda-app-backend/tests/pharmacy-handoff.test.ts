import { describe, expect, it } from "vitest";
import {
	listPharmacies,
	PHARMACY_DIRECTORY,
	PharmacyHandoffService,
} from "../src/refills/pharmacy-handoff";
import { memoryDb } from "./consumer-memory-db";

const reviewed = new Date("2026-10-16T00:00:00Z");
function fixture(prescription: Record<string, unknown> = {}) {
	const memory = memoryDb({
		prescription: [
			{ id: "rx-owned", userId: "owner", archivedAt: null, ...prescription },
		],
	});
	return { ...memory, service: new PharmacyHandoffService(memory.db) };
}

describe("safe pharmacy handoff", () => {
	it("keeps the curated catalog on allowlisted official HTTPS origins without query data", () => {
		const allowed = new Set([
			"www.cvs.com",
			"www.walgreens.com",
			"www.walmart.com",
			"rx.costco.com",
			"www.costco.com",
			"www.kroger.com",
			"pharmacy.amazon.com",
			"www.publix.com",
			"www.albertsons.com",
			"www.safeway.com",
			"www.heb.com",
			"www.samsclub.com",
			"www.meijer.com",
		]);
		expect(PHARMACY_DIRECTORY.length).toBeGreaterThanOrEqual(10);
		for (const pharmacy of PHARMACY_DIRECTORY)
			for (const action of Object.values(pharmacy.actions)) {
				const url = new URL(action.url);
				expect(url.protocol).toBe("https:");
				expect(allowed.has(url.hostname)).toBe(true);
				expect(url.search).toBe("");
				expect(url.hash).toBe("");
				expect(url.username).toBe("");
			}
	});

	it("matches normalized aliases without treating the catalog as exhaustive", () => {
		expect(listPharmacies("H E B").map((item) => item.id)).toContain("heb");
		expect(listPharmacies("Fred Meyer Pharmacy")).toEqual([]);
		expect(listPharmacies("independent neighborhood pharmacy")).toEqual([]);
		expect(fixture().service.directory().meta.scope).toBe(
			"curated_major_us_chains",
		);
	});

	it("rejects a handoff for a prescription owned by another account", async () => {
		await expect(
			fixture().service.handoff("other", "rx-owned", "cvs", "refill"),
		).rejects.toMatchObject({ status: 404 });
	});

	it("returns no prescription details or URL parameters", async () => {
		const result = await fixture({
			rxNumber: "PRIVATE-RX",
			medicationName: "PRIVATE MED",
			pharmacyOrDoctorName: "CVS Pharmacy",
			contactDetails: "+12125550123",
			labelReviewedAt: reviewed,
		}).service.handoff("owner", "rx-owned", "cvs", "refill");
		expect(result.data.savedPharmacyPhone).toBe("+12125550123");
		expect(result.data.copyFields).toEqual(["rxNumber"]);
		expect(JSON.stringify(result)).not.toContain("PRIVATE-RX");
		expect(JSON.stringify(result)).not.toContain("PRIVATE MED");
		expect(
			new URL(
				"url" in result.data.action
					? result.data.action.url
					: "https://invalid.example",
			).search,
		).toBe("");
	});

	it("only returns a phone from a reviewed matching pharmacy label", async () => {
		for (const prescription of [
			{ pharmacyOrDoctorName: "CVS", contactDetails: "+12125550123" },
			{
				pharmacyOrDoctorName: "not CVS",
				contactDetails: "+12125550123",
				labelReviewedAt: reviewed,
			},
			{
				pharmacyOrDoctorName: "Walgreens",
				contactDetails: "+12125550123",
				labelReviewedAt: reviewed,
			},
			{
				pharmacyOrDoctorName: "CVS",
				contactDetails: "Call +1 212 555 0123",
				labelReviewedAt: reviewed,
			},
		]) {
			const result = await fixture(prescription).service.handoff(
				"owner",
				"rx-owned",
				"cvs",
				"refill",
			);
			expect(result.data).not.toHaveProperty("savedPharmacyPhone");
		}
	});

	it.each([
		"renewal",
		"new_rx",
	] as const)("routes %s to the prescriber without implying an order", async (purpose) => {
		const result = await fixture().service.handoff(
			"owner",
			"rx-owned",
			"cvs",
			purpose,
		);
		expect(result.data.action).toEqual({ mode: "call_prescriber" });
		expect(result.data.notice).toContain("licensed prescriber");
	});
});
