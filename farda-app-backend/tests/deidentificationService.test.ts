import {
	ageBand,
	deidentifyEvent,
	deidentifySubject,
	generalizeRegion,
	HIPAA_IDENTIFIER_CLASSES,
	hasNoPhiKeys,
	type IdentifiedEvent,
	type IdentifiedRecord,
	pseudonymize,
} from "@src/services/DeidentificationService";
import { describe, expect, it } from "vitest";

/**
 * Pure-function tests for the HIPAA Safe-Harbor de-identification transform
 * (GTM-522). No DB, no env mutation beyond a per-call salt override, so the
 * suite is deterministic and CI-friendly (matching unit.test.ts / refillService).
 */

const SALT = "test-salt-A";
const OTHER_SALT = "test-salt-B";

// A fully-populated identified record carrying ALL 18 Safe-Harbor identifier
// classes, so we can assert each one is removed/transformed in the output.
const identified: IdentifiedRecord = {
	userId: "user-123",
	name: "Jane Q. Patient", // 1 names
	region: "California", // 2 geo (broad region kept; finer geo dropped)
	address: "123 Main St, Apt 4",
	zip: "90210",
	dateOfBirth: "1980-05-01", // 3 dates / ages
	age: 45,
	phoneNumber: "+1-555-123-4567", // 4 phone
	faxNumber: "+1-555-765-4321", // 5 fax
	email: "jane@example.com", // 6 email
	ssn: "123-45-6789", // 7 SSN
	medicalRecordNumber: "MRN-998877", // 8 MRN
	healthPlanBeneficiaryNumber: "HP-554433", // 9 health plan beneficiary #
	accountNumber: "ACCT-001122", // 10 account #
	certificateOrLicenseNumber: "DL-X1234", // 11 certificate/license #
	vehicleIdentifier: "1HGCM82633A004352", // 12 vehicle id (VIN)
	deviceId: "device-serial-42", // 13 device id/serial
	url: "https://jane.example.com", // 14 URL
	ipAddress: "203.0.113.7", // 15 IP
	biometricId: "fp-aabbcc", // 16 biometric
	facePhotoUrl: "https://img/jane.jpg", // 17 full-face photo
	otherUniqueId: "loyalty-7788", // 18 other unique id
};

describe("HIPAA identifier coverage", () => {
	it("enumerates all 18 Safe-Harbor identifier classes", () => {
		expect(HIPAA_IDENTIFIER_CLASSES).toHaveLength(18);
	});
});

describe("pseudonymize (one-way, salted)", () => {
	it("is deterministic: same input + same salt -> same pseudonym", () => {
		expect(pseudonymize("user-123", SALT)).toBe(pseudonymize("user-123", SALT));
	});

	it("different salt -> different pseudonym", () => {
		expect(pseudonymize("user-123", SALT)).not.toBe(
			pseudonymize("user-123", OTHER_SALT),
		);
	});

	it("different input -> different pseudonym", () => {
		expect(pseudonymize("user-123", SALT)).not.toBe(
			pseudonymize("user-999", SALT),
		);
	});

	it("is one-way: the pseudonym never contains the source value", () => {
		const token = pseudonymize("user-123", SALT);
		expect(token).not.toContain("user-123");
		// SHA-256 hex is 64 chars.
		expect(token).toMatch(/^[0-9a-f]{64}$/);
	});

	it("fails closed when no salt is configured", () => {
		// No salt override AND no env salt set in this CI process -> throws.
		expect(() => pseudonymize("user-123")).toThrow(/DEID_SALT/);
	});
});

describe("ageBand (date generalisation)", () => {
	it("bands an exact age into a decade", () => {
		expect(ageBand(45)).toBe("40-49");
		expect(ageBand(30)).toBe("30-39");
		expect(ageBand(39)).toBe("30-39");
	});
	it("collapses ages over 89 into 90+ (Safe-Harbor)", () => {
		expect(ageBand(91)).toBe("90+");
		expect(ageBand(120)).toBe("90+");
	});
	it("derives a band from a DOB when age is absent", () => {
		const now = new Date("2026-06-28T00:00:00Z");
		expect(ageBand(null, "1980-05-01", now)).toBe("40-49");
	});
	it("returns null for missing/invalid age", () => {
		expect(ageBand(null)).toBeNull();
		expect(ageBand(undefined)).toBeNull();
	});
});

describe("generalizeRegion (geo generalisation)", () => {
	it("keeps only a broad region; address/zip are dropped", () => {
		expect(generalizeRegion("California", "123 Main St", "90210")).toBe(
			"California",
		);
	});
	it("never derives a region from address/zip alone", () => {
		expect(generalizeRegion(null, "123 Main St", "90210")).toBeNull();
	});
});

describe("deidentifySubject — removes/transforms all 18 identifier classes", () => {
	const subject = deidentifySubject(identified, SALT);

	it("keyed by a one-way pseudonym (not the real userId)", () => {
		expect(subject.subjectKey).toBe(pseudonymize("user-123", SALT));
		expect(subject.subjectKey).not.toBe("user-123");
	});

	it("retains ONLY coarse, non-identifying cohort attributes", () => {
		expect(subject.ageBand).toBe("40-49"); // exact age generalised
		expect(subject.region).toBe("California"); // broad geo only
		expect(Object.keys(subject).sort()).toEqual(
			["ageBand", "region", "subjectKey"].sort(),
		);
	});

	it("output carries NO PHI identifier keys", () => {
		expect(hasNoPhiKeys(subject as unknown as Record<string, unknown>)).toBe(
			true,
		);
	});

	it("no reverse-mapping leak: no identifier value survives in the output", () => {
		const serialized = JSON.stringify(subject);
		for (const phi of [
			"user-123",
			"Jane",
			"Patient",
			"90210",
			"123 Main St",
			"1980-05-01",
			"555-123-4567",
			"555-765-4321",
			"jane@example.com",
			"123-45-6789",
			"MRN-998877",
			"HP-554433",
			"ACCT-001122",
			"DL-X1234",
			"1HGCM82633A004352",
			"device-serial-42",
			"jane.example.com",
			"203.0.113.7",
			"fp-aabbcc",
			"jane.jpg",
			"loyalty-7788",
		]) {
			expect(serialized).not.toContain(phi);
		}
	});
});

describe("deidentifyEvent — date-shifted, PHI-free events", () => {
	const epoch = new Date("2026-06-01T00:00:00Z");
	const event: IdentifiedEvent = {
		userId: "user-123",
		eventType: "DOSE_TAKEN",
		occurredAt: "2026-06-05T14:30:00Z",
		note: "felt nauseous after metformin", // free-text PHI — must be dropped
		value: 12,
	};

	it("shifts the absolute date to a relative dayOffset (no exact date)", () => {
		const deid = deidentifyEvent(event, epoch, SALT);
		expect(deid.dayOffset).toBe(4); // 2026-06-05 is 4 days after epoch
		expect(deid.hourBucket).toBe(14); // coarse hour only
		expect(JSON.stringify(deid)).not.toContain("2026-06-05");
	});

	it("drops free-text PHI (note) and keeps only structured fields", () => {
		const deid = deidentifyEvent(event, epoch, SALT);
		expect(Object.keys(deid).sort()).toEqual(
			["dayOffset", "eventType", "hourBucket", "subjectKey", "value"].sort(),
		);
		const serialized = JSON.stringify(deid);
		expect(serialized).not.toContain("nauseous");
		expect(serialized).not.toContain("metformin");
	});

	it("keys events by the same pseudonym as the subject (correlatable)", () => {
		const deid = deidentifyEvent(event, epoch, SALT);
		expect(deid.subjectKey).toBe(
			deidentifySubject(identified, SALT).subjectKey,
		);
	});

	it("output carries NO PHI identifier keys", () => {
		const deid = deidentifyEvent(event, epoch, SALT);
		expect(hasNoPhiKeys(deid as unknown as Record<string, unknown>)).toBe(true);
	});
});
