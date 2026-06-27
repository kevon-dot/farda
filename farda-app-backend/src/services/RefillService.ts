/******************************************************************************
        Refill prediction + pharmacy-readiness service (GTM-541)
*******************************************************************************

  PURE, TESTABLE depletion math. No DB, no Express, no I/O here so the calc can
  be unit-tested deterministically (vitest, prisma mocked) and reused by both
  the `/refills` endpoint and any future background job.

  MODEL (built on the ALREADY-MERGED multi-med + dose schema, #76 / GTM-537):

    * remaining pills = initial prescription qty − doses already taken
        - initial qty comes from Medicine.qty (a free-text string the OCR step
          fills in, e.g. "30" or "30 tablets"); we parse the leading number.
        - "doses taken" = Dose rows with a non-null takenAt for the
          prescription.
    * daily dose rate comes from the SCHEDULE: count the distinct scheduled
      doses per day across the prescription's Dose rows (so a 2x/day Rx → rate
      2). We measure the rate from the schedule rather than guessing, so a
      custom/uneven schedule is handled.
    * days-left      = floor(remaining / dailyRate)
    * predictedDepletion = today + days-left
    * refill-due     = predictedDepletion − leadTimeDays (so the user requests
      the refill BEFORE running out; default lead time below).

  HARDWARE / DATA FLAG: today "remaining" is derived from qty + logged doses.
  The smart-vial weight sensor will eventually give a DIRECT remaining-pill
  count (weight ÷ pill mass) that is more accurate than "qty − dosesTaken"
  (which assumes every scheduled+taken dose removed exactly one pill and that
  the user never took an untracked pill). `computeRefill` accepts an OPTIONAL
  `measuredRemaining` override so when real weight capture lands it can feed the
  authoritative count straight in without changing the call sites or the
  downstream date math. Until then we fall back to the qty−doses estimate and
  mark the source as "estimated".
******************************************************************************/

/** Default days of runway we want the user to refill BEFORE depletion. */
export const DEFAULT_REFILL_LEAD_DAYS = 7;

/** Where the remaining-pill count came from — flagged so the UI/analytics can
 *  distinguish a precise (weight-sensor) reading from the qty−doses estimate. */
export type RemainingSource = "measured" | "estimated";

export interface RefillInput {
	/** Initial pill count for the prescription (parsed from Medicine.qty). May be
	 *  null/unknown when the OCR step did not capture a quantity. */
	initialQty: number | null;
	/** Number of doses already taken (Dose rows with takenAt != null). */
	dosesTaken: number;
	/** Doses consumed per day, derived from the schedule. <= 0 means unknown. */
	dailyRate: number;
	/** Optional DIRECT remaining count from the weight sensor (hardware flag).
	 *  When provided it overrides the qty−doses estimate. */
	measuredRemaining?: number | null;
	/** Lead time (days) to subtract so the refill is due before depletion. */
	leadTimeDays?: number;
	/** Reference "now" (injected for deterministic tests). Defaults to new Date. */
	now?: Date;
}

export interface RefillPrediction {
	/** Remaining pills (clamped at 0). Null when it cannot be determined (no qty
	 *  and no measured reading). */
	remaining: number | null;
	remainingSource: RemainingSource;
	dailyRate: number;
	/** Whole days of supply left. Null when remaining or rate is unknown. */
	daysLeft: number | null;
	/** ISO date (UTC midnight) the supply is predicted to run out. Null when
	 *  unknown. */
	predictedDepletion: string | null;
	/** ISO date the user should request a refill (depletion − lead time). Null
	 *  when unknown. */
	refillDue: string | null;
	/** True when refillDue is today or in the past (i.e. act now). */
	isRefillDue: boolean;
}

/**
 * Parse the leading integer out of a free-text quantity string such as "30",
 * "30 tablets", or "qty 90". Returns null when no number is present.
 *
 * Pure + exported so the route and tests share one parser.
 */
export function parseQty(raw: string | null | undefined): number | null {
	if (raw == null) return null;
	const match = String(raw).match(/-?\d+(?:\.\d+)?/);
	if (!match) return null;
	const n = Number(match[0]);
	if (!Number.isFinite(n) || n < 0) return null;
	return Math.floor(n);
}

/**
 * Derive the daily dose rate from a prescription's scheduled doses by counting
 * the distinct calendar days they fall on and dividing the total by that span.
 * Measuring from the schedule (rather than a config field) makes uneven/custom
 * schedules work. Returns 0 when there is nothing to measure.
 *
 * @param scheduledDates the `scheduledFor` timestamps of the Rx's Dose rows.
 */
export function dailyRateFromSchedule(scheduledDates: Date[]): number {
	if (scheduledDates.length === 0) return 0;
	const days = new Set<string>();
	for (const d of scheduledDates) {
		// Group by UTC calendar day (YYYY-MM-DD).
		days.add(d.toISOString().slice(0, 10));
	}
	if (days.size === 0) return 0;
	return scheduledDates.length / days.size;
}

/** UTC-midnight ISO date string (YYYY-MM-DD) for a Date. */
function toIsoDate(d: Date): string {
	return d.toISOString().slice(0, 10);
}

/** Add whole days to a date, returning a new UTC-midnight Date. */
function addDays(base: Date, days: number): Date {
	const d = new Date(
		Date.UTC(base.getUTCFullYear(), base.getUTCMonth(), base.getUTCDate()),
	);
	d.setUTCDate(d.getUTCDate() + days);
	return d;
}

/**
 * The core depletion + refill-due calculation. PURE: no DB, no clock unless you
 * inject `now`. Given inventory + the daily rate, returns days-left, the
 * predicted depletion date, and the refill-due date.
 */
export function computeRefill(input: RefillInput): RefillPrediction {
	const now = input.now ?? new Date();
	const leadTimeDays = input.leadTimeDays ?? DEFAULT_REFILL_LEAD_DAYS;
	const dailyRate = input.dailyRate > 0 ? input.dailyRate : 0;

	// Prefer a direct (weight-sensor) reading when present; otherwise estimate
	// from initial qty − doses taken.
	let remaining: number | null;
	let remainingSource: RemainingSource;
	if (input.measuredRemaining != null && input.measuredRemaining >= 0) {
		remaining = Math.floor(input.measuredRemaining);
		remainingSource = "measured";
	} else if (input.initialQty != null) {
		remaining = Math.max(0, input.initialQty - Math.max(0, input.dosesTaken));
		remainingSource = "estimated";
	} else {
		remaining = null;
		remainingSource = "estimated";
	}

	// Without a remaining count or a positive rate we cannot project a date.
	if (remaining == null || dailyRate <= 0) {
		return {
			remaining,
			remainingSource,
			dailyRate,
			daysLeft: null,
			predictedDepletion: null,
			refillDue: null,
			isRefillDue: remaining != null && remaining <= 0,
		};
	}

	const daysLeft = Math.floor(remaining / dailyRate);
	const depletion = addDays(now, daysLeft);
	const refillDueDate = addDays(depletion, -leadTimeDays);

	// "Due" when the refill-due date is today or already past.
	const todayMidnight = addDays(now, 0);
	const isRefillDue = refillDueDate.getTime() <= todayMidnight.getTime();

	return {
		remaining,
		remainingSource,
		dailyRate,
		daysLeft,
		predictedDepletion: toIsoDate(depletion),
		refillDue: toIsoDate(refillDueDate),
		isRefillDue,
	};
}

/******************************************************************************
        Pharmacy auto-refill integration — STUB / SEAM ONLY (GTM-541)
*******************************************************************************

  Scope explicitly STOPS here: we do NOT build a real pharmacy integration
  (Surescripts / NCPDP SCRIPT / a chain's refill API). This interface is the
  seam a real adapter would implement later. The `/refills` endpoint and the
  RefillEvent log are fully functional WITHOUT it; an auto-refill provider is
  purely additive.
******************************************************************************/

export interface PharmacyRefillRequest {
	rxNumber: string | null;
	storeNumber: string | null;
	pharmacyName: string | null;
}

export interface PharmacyRefillResult {
	/** Provider-side confirmation id, when the request was accepted. */
	confirmationId: string | null;
	status: "submitted" | "unsupported";
}

export interface PharmacyRefillProvider {
	submitRefill(request: PharmacyRefillRequest): Promise<PharmacyRefillResult>;
}

/**
 * The only provider wired today: a no-op stub that reports the integration is
 * unsupported. A real adapter (per-pharmacy) would replace this behind the same
 * interface without touching the route or the event log.
 *
 * TODO(GTM-541 follow-up): implement a real PharmacyRefillProvider (e.g.
 * Surescripts / a chain refill API) and select it via config. Requires
 * credentials + a BAA with the pharmacy network — out of scope for this build.
 */
export const stubPharmacyProvider: PharmacyRefillProvider = {
	async submitRefill(): Promise<PharmacyRefillResult> {
		return { confirmationId: null, status: "unsupported" };
	},
};
