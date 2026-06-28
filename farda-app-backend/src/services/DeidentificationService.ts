import { createHash } from "node:crypto";
import env from "@src/common/constants/env";

/******************************************************************************
        De-identification transform — HIPAA Safe-Harbor (GTM-522)
******************************************************************************/

/**
 * Pure transform mapping an IDENTIFIED record (PHI) -> a DE-IDENTIFIED record,
 * applying the HIPAA Safe-Harbor method (45 CFR §164.514(b)(2)): all 18
 * identifier classes are removed, generalised or replaced by a one-way
 * pseudonym so the result cannot reasonably be used to re-identify a person.
 *
 * Key properties (all exercised by the unit tests):
 *   - Deterministic: same input + same salt -> same pseudonym (so de-identified
 *     events for one person correlate WITHOUT storing the real id).
 *   - One-way: the pseudonym is sha256(salt + value); the reverse mapping is
 *     NEVER produced or stored here. Different salt -> different pseudonym.
 *   - No reverse-mapping leak: the output carries the pseudonym only, never the
 *     source id/name/contact/exact-date it was derived from.
 *   - PHI-free output keys: the result object contains none of the 18
 *     identifier field names.
 *
 * The functions are pure (no DB). A caller persists the result into the
 * `DeidentifiedSubject` / `DeidentifiedEvent` tables and writes a provenance
 * entry (see the projection seam in DataPipelineService).
 */

/** The 18 HIPAA Safe-Harbor identifier classes (45 CFR §164.514(b)(2)(i)). */
export const HIPAA_IDENTIFIER_CLASSES = [
	"names",
	"geographic_subdivisions", // smaller than a state
	"dates", // all elements except year, + ages > 89
	"phone_numbers",
	"fax_numbers",
	"email_addresses",
	"social_security_numbers",
	"medical_record_numbers",
	"health_plan_beneficiary_numbers",
	"account_numbers",
	"certificate_license_numbers",
	"vehicle_identifiers", // VIN, plates
	"device_identifiers_and_serials",
	"urls",
	"ip_addresses",
	"biometric_identifiers",
	"full_face_photos",
	"other_unique_identifying_numbers",
] as const;

export type HipaaIdentifierClass = (typeof HIPAA_IDENTIFIER_CLASSES)[number];

/** Identified input record (PHI) — a flattened view of a user + their data. */
export interface IdentifiedRecord {
	userId: string;
	// names
	name?: string | null;
	// contact
	email?: string | null;
	phoneNumber?: string | null;
	faxNumber?: string | null;
	// geo
	address?: string | null;
	zip?: string | null;
	region?: string | null; // a broad region (state/country) is allowed
	// dates / age
	dateOfBirth?: string | Date | null;
	age?: number | null;
	// other identifiers
	ssn?: string | null;
	medicalRecordNumber?: string | null;
	healthPlanBeneficiaryNumber?: string | null;
	accountNumber?: string | null;
	certificateOrLicenseNumber?: string | null;
	vehicleIdentifier?: string | null;
	deviceId?: string | null;
	url?: string | null;
	ipAddress?: string | null;
	biometricId?: string | null;
	facePhotoUrl?: string | null;
	otherUniqueId?: string | null;
}

/** De-identified subject — pseudonym + coarse, non-identifying cohort attrs. */
export interface DeidentifiedSubjectRecord {
	subjectKey: string;
	ageBand: string | null;
	region: string | null;
}

/** An identified event to project (PHI-bearing free text is dropped). */
export interface IdentifiedEvent {
	userId: string;
	eventType: string;
	/** Absolute timestamp — generalised to a date-shifted dayOffset on output. */
	occurredAt: string | Date;
	/** Free-text PHI (mood/note/medication name) — DROPPED, never projected. */
	note?: string | null;
	/** Non-PHI numeric measure to retain (e.g. minutesLate). */
	value?: number | null;
}

/** De-identified event — date-shifted, PHI-free. */
export interface DeidentifiedEventRecord {
	subjectKey: string;
	eventType: string;
	dayOffset: number;
	hourBucket: number | null;
	value: number | null;
}

const MS_PER_DAY = 24 * 60 * 60 * 1000;

/**
 * Resolve the de-id salt. Fail-closed: a missing salt throws rather than
 * silently producing weak/guessable pseudonyms. The salt comes from env and is
 * never persisted into the de-id layer.
 */
function requireSalt(saltOverride?: string): string {
	const salt = saltOverride ?? env.DEID_SALT;
	if (!salt || salt.trim().length === 0) {
		throw new Error(
			"DEID_SALT is not configured; refusing to de-identify (fail-closed)",
		);
	}
	return salt;
}

/**
 * One-way, salted pseudonym for a stable identifier (e.g. the user id).
 * `pseudonym = sha256(salt + ":" + value)`. Deterministic for a given salt;
 * irreversible; salt change -> different pseudonym. The reverse mapping is
 * never produced.
 */
export function pseudonymize(value: string, saltOverride?: string): string {
	const salt = requireSalt(saltOverride);
	return createHash("sha256").update(`${salt}:${value}`).digest("hex");
}

/**
 * Generalise an age (or DOB) to a Safe-Harbor age BAND. Ages over 89 are
 * collapsed into a single "90+" band (Safe-Harbor caps ages > 89). Exact
 * ages/DOBs are never returned.
 */
export function ageBand(
	age: number | null | undefined,
	dateOfBirth?: string | Date | null,
	now: Date = new Date(),
): string | null {
	let years = age ?? null;
	if (years == null && dateOfBirth != null) {
		const dob = new Date(dateOfBirth);
		if (!Number.isNaN(dob.getTime())) {
			years = Math.floor(
				(now.getTime() - dob.getTime()) / (365.25 * MS_PER_DAY),
			);
		}
	}
	if (years == null || years < 0) return null;
	if (years > 89) return "90+"; // Safe-Harbor: aggregate everyone over 89.
	const lower = Math.floor(years / 10) * 10;
	return `${lower}-${lower + 9}`;
}

/**
 * Generalise geography to a broad region only. A precise address/ZIP is
 * dropped entirely; an explicit broad region (state/country) is passed through.
 * (Safe-Harbor permits geography no finer than the first 3 ZIP digits with a
 * population guard; we conservatively keep only a coarse region label.)
 */
export function generalizeRegion(
	region?: string | null,
	_address?: string | null,
	_zip?: string | null,
): string | null {
	// Deliberately ignore address/zip — never derive a finer geo than `region`.
	const r = region?.trim();
	return r && r.length > 0 ? r : null;
}

/**
 * Map an identified record -> a de-identified subject. Strips/aggregates all 18
 * identifier classes: names/contact/ids -> dropped; age/DOB -> band; geo ->
 * coarse region; userId -> one-way pseudonym.
 */
export function deidentifySubject(
	record: IdentifiedRecord,
	saltOverride?: string,
	now: Date = new Date(),
): DeidentifiedSubjectRecord {
	return {
		subjectKey: pseudonymize(record.userId, saltOverride),
		ageBand: ageBand(record.age, record.dateOfBirth, now),
		region: generalizeRegion(record.region, record.address, record.zip),
	};
}

/**
 * Map an identified event -> a de-identified event. The absolute timestamp is
 * date-SHIFTED to a per-subject relative dayOffset (so no exact date survives),
 * the hour is coarsened to a bucket, and any free-text PHI is dropped.
 *
 * `epoch` is the per-subject de-id origin (e.g. their first event date); the
 * caller supplies it so the same subject's events share a consistent shift.
 */
export function deidentifyEvent(
	event: IdentifiedEvent,
	epoch: Date,
	saltOverride?: string,
): DeidentifiedEventRecord {
	const occurred = new Date(event.occurredAt);
	const dayOffset = Math.floor(
		(occurred.getTime() - epoch.getTime()) / MS_PER_DAY,
	);
	const hourBucket = Number.isNaN(occurred.getTime())
		? null
		: occurred.getUTCHours();
	return {
		subjectKey: pseudonymize(event.userId, saltOverride),
		eventType: event.eventType,
		dayOffset: Number.isFinite(dayOffset) ? dayOffset : 0,
		hourBucket,
		value: event.value ?? null,
		// NOTE: event.note (free-text PHI) is intentionally NOT projected.
	};
}

/**
 * Guard: assert an object carries NO known PHI identifier keys. Used in tests
 * and can be used at the persistence seam to fail-closed if a PHI field ever
 * leaks into a de-identified payload.
 */
const PHI_KEYS = new Set<string>([
	"name",
	"email",
	"phoneNumber",
	"faxNumber",
	"address",
	"zip",
	"dateOfBirth",
	"age",
	"ssn",
	"medicalRecordNumber",
	"healthPlanBeneficiaryNumber",
	"accountNumber",
	"certificateOrLicenseNumber",
	"vehicleIdentifier",
	"deviceId",
	"url",
	"ipAddress",
	"biometricId",
	"facePhotoUrl",
	"otherUniqueId",
	"userId",
	"note",
	"occurredAt",
]);

export function hasNoPhiKeys(obj: Record<string, unknown>): boolean {
	return !Object.keys(obj).some((k) => PHI_KEYS.has(k));
}

export const DeidentificationService = {
	HIPAA_IDENTIFIER_CLASSES,
	pseudonymize,
	ageBand,
	generalizeRegion,
	deidentifySubject,
	deidentifyEvent,
	hasNoPhiKeys,
};

export default DeidentificationService;
