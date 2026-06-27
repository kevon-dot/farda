import { z } from "zod";

/**
 * Strict schema for OCR / vision-model output (#33).
 *
 * THREAT MODEL: The text below is produced by GPT-4o reading an arbitrary,
 * user-supplied prescription image. It is UNTRUSTED. A crafted image can
 * coax the model into emitting arbitrary strings (prompt injection) or a
 * malformed shape. Nothing here may be persisted, surfaced as medical
 * guidance, or used to drive privileged actions unless it first passes this
 * schema. We therefore:
 *   - reject unexpected keys (`.strict()`) so injected extra fields can't ride along,
 *   - bound every string length so a runaway/garbage payload can't be stored,
 *   - coerce loosely-typed numeric fields (model often returns numbers as strings),
 *   - require the minimum fields that make a result usable, and treat the rest as optional.
 *
 * These typed fields are descriptive metadata ONLY. They are never executed,
 * interpreted as commands, or used for authorization decisions.
 */

// Generous-but-bounded caps. Real prescription fields are short; anything
// beyond these limits is almost certainly noise or an injection attempt.
const SHORT = 256;
const MEDIUM = 512;
const LONG = 2000;

const boundedString = (max: number) => z.string().max(max);

/**
 * A single medication. `medicine_name` is required (a medication without a
 * name is not actionable). Everything else is optional free text the model
 * may or may not find on the label.
 */
export const OcrMedicineSchema = z
	.object({
		medicine_name: boundedString(SHORT).min(1, "medicine_name is required"),
		generic_name: boundedString(SHORT).optional(),
		dosage: boundedString(SHORT).optional(),
		strength: boundedString(SHORT).optional(),
		instructions: boundedString(LONG).optional(),
		frequency: boundedString(MEDIUM).optional(),
		// qty / count of units. Accept number or numeric-ish string, keep as string.
		qty: z
			.union([z.string().max(SHORT), z.number()])
			.transform((v) => String(v))
			.optional(),
		refills_info: boundedString(MEDIUM).optional(),
		side_effects: boundedString(LONG).optional(),
	})
	.strict();

export type OcrMedicine = z.infer<typeof OcrMedicineSchema>;

/**
 * Full OCR extraction result. `medicines_names` preserves the FULL list of
 * medications found on the prescription, and OcrRoutes.savePrescription now
 * persists each one as its own Medicine row (one prescription -> many
 * medicines).
 */
export const OcrResultSchema = z
	.object({
		pharmacy_or_doctor_name: boundedString(SHORT).optional(),
		contact_details: boundedString(MEDIUM).optional(),
		date_filled: boundedString(SHORT).optional(),
		date_expired: boundedString(SHORT).optional(),
		address: boundedString(MEDIUM).optional(),
		rx_number: boundedString(SHORT).optional(),
		store_number: boundedString(SHORT).optional(),
		// At least one medication must be present and valid; an empty array is
		// not a usable prescription and is rejected.
		medicines_names: z
			.array(OcrMedicineSchema)
			.min(1, "at least one medication is required")
			.max(50, "too many medications — likely malformed output"),
	})
	.strict();

export type OcrResult = z.infer<typeof OcrResultSchema>;

/**
 * Validate raw, JSON-parsed model output against the strict schema.
 * Returns a discriminated result so callers can reject/flag on failure
 * instead of silently persisting garbage.
 */
export function validateOcrResult(
	raw: unknown,
): { ok: true; data: OcrResult } | { ok: false; error: z.ZodError } {
	const parsed = OcrResultSchema.safeParse(raw);
	if (parsed.success) {
		return { ok: true, data: parsed.data };
	}
	return { ok: false, error: parsed.error };
}
