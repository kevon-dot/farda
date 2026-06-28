/******************************************************************************
        Adherence-metrics computation engine (GTM-540 / GTM-502)
*******************************************************************************

  PURE, TESTABLE adherence math. No DB, no Express, no I/O here so every metric
  can be unit-tested deterministically (vitest, prisma mocked) and reused by the
  `/api/metrics/adherence` endpoint and any future background job / report.

  INPUT MODEL (built on the ALREADY-MERGED Dose + Prescription/Medicine schema,
  #76 / GTM-537):

    * A `DoseEvent` mirrors a Dose row: `scheduledFor` (when it was due) and an
      optional `takenAt` (null = not taken). An optional `confidence` score in
      [0, 1] carries the data-confidence weight (GTM-520, see metric 9).
    * "Supplied days" for MPR come from the prescription/medicine inventory:
      initial pill qty across the Rx's medicines ÷ the daily dose rate.

  Each metric returns not just a bare number but the denominators/inputs it used
  so the value is EXPLAINABLE (e.g. PDC returns coveredDays + totalDays, not just
  the ratio). Callers can surface "12 of 14 days covered" rather than "0.857".

  DATE HANDLING: days are bucketed by UTC calendar day (YYYY-MM-DD), matching
  RefillService.dailyRateFromSchedule so the two engines agree on "a day".
******************************************************************************/

/** Default on-time window (minutes) either side of `scheduledFor`. A dose taken
 *  within ±this of its scheduled time counts as "on time"; outside (but taken)
 *  is "late". Configurable per call so a tighter/looser clinic policy can be
 *  applied without code changes. */
export const DEFAULT_ON_TIME_WINDOW_MINUTES = 30;

const MS_PER_MINUTE = 60_000;
const MS_PER_DAY = 86_400_000;

/**
 * A single dose event, mirroring the Dose row (scheduledFor / takenAt) plus the
 * optional GTM-520 data-confidence weight.
 */
export interface DoseEvent {
	scheduledFor: Date;
	takenAt?: Date | null;
	/**
	 * GTM-520 SEAM: data-confidence score in [0, 1] for THIS dose event (how sure
	 * we are the taken/missed signal is real). The confidence engine (GTM-520) is
	 * NOT built yet, so this is optional and every consumer DEFAULTS it to 1.0
	 * (see `confidenceOf`). When GTM-520 lands it wires real per-event scores in
	 * here without touching any metric below.
	 */
	confidence?: number | null;
}

/** Inventory inputs for MPR (medication possession ratio). */
export interface InventoryInput {
	/** Total initial pill count across the Rx's medicines (parsed Medicine.qty).
	 *  Null/unknown when the OCR step captured no quantity. */
	initialQty: number | null;
	/** Doses consumed per day, derived from the schedule (RefillService rate). */
	dailyRate: number;
}

/** Options shared by the metric computations. */
export interface MetricOptions {
	/** Inclusive window start (UTC). */
	rangeStart: Date;
	/** Inclusive window end (UTC). */
	rangeEnd: Date;
	/** On-time tolerance in minutes (defaults to DEFAULT_ON_TIME_WINDOW_MINUTES). */
	onTimeWindowMinutes?: number;
}

/******************************************************************************
                                Helpers
******************************************************************************/

/** UTC-midnight ISO date string (YYYY-MM-DD) for a Date. */
function toDayKey(d: Date): string {
	return d.toISOString().slice(0, 10);
}

/** Whole UTC days in the inclusive [start, end] window (>= 1 for a valid range,
 *  0 when end is before start). */
export function daysInWindow(start: Date, end: Date): number {
	const a = Date.UTC(
		start.getUTCFullYear(),
		start.getUTCMonth(),
		start.getUTCDate(),
	);
	const b = Date.UTC(end.getUTCFullYear(), end.getUTCMonth(), end.getUTCDate());
	if (b < a) return 0;
	return Math.floor((b - a) / MS_PER_DAY) + 1;
}

/** Default a dose event's confidence to 1.0 (GTM-520 seam). Clamps to [0, 1]. */
export function confidenceOf(event: DoseEvent): number {
	const c = event.confidence;
	if (c == null || !Number.isFinite(c)) return 1;
	return Math.min(1, Math.max(0, c));
}

/** True when a taken dose fell within the on-time window of its schedule. */
function isOnTime(event: DoseEvent, windowMinutes: number): boolean {
	if (event.takenAt == null) return false;
	const deltaMs = Math.abs(
		event.takenAt.getTime() - event.scheduledFor.getTime(),
	);
	return deltaMs <= windowMinutes * MS_PER_MINUTE;
}

/** Keep only events scheduled inside the inclusive [start, end] window. */
function withinRange(events: DoseEvent[], start: Date, end: Date): DoseEvent[] {
	const lo = start.getTime();
	const hi = end.getTime();
	return events.filter((e) => {
		const t = e.scheduledFor.getTime();
		return t >= lo && t <= hi;
	});
}

/******************************************************************************
        1. PDC — Proportion of Days Covered
******************************************************************************/

export interface PdcResult {
	value: number; // coveredDays / totalDays, 0 when totalDays is 0
	coveredDays: number; // distinct days with >= 1 dose taken
	scheduledDays: number; // distinct days that had >= 1 scheduled dose
	totalDays: number; // calendar days in the window
}

/**
 * PDC: the proportion of days in the window on which the user took at least one
 * required (scheduled) dose. A "covered" day is a calendar day that had a
 * scheduled dose AND at least one of that day's doses was taken.
 */
export function computePdc(
	events: DoseEvent[],
	opts: MetricOptions,
): PdcResult {
	const totalDays = daysInWindow(opts.rangeStart, opts.rangeEnd);
	const inRange = withinRange(events, opts.rangeStart, opts.rangeEnd);

	const scheduledDayKeys = new Set<string>();
	const coveredDayKeys = new Set<string>();
	for (const e of inRange) {
		const key = toDayKey(e.scheduledFor);
		scheduledDayKeys.add(key);
		if (e.takenAt != null) coveredDayKeys.add(key);
	}

	const coveredDays = coveredDayKeys.size;
	const value = totalDays > 0 ? coveredDays / totalDays : 0;
	return {
		value,
		coveredDays,
		scheduledDays: scheduledDayKeys.size,
		totalDays,
	};
}

/******************************************************************************
        2. MPR — Medication Possession Ratio
******************************************************************************/

export interface MprResult {
	value: number | null; // suppliedDays / elapsedDays, null when undeterminable
	suppliedDays: number | null; // initialQty / dailyRate
	elapsedDays: number; // calendar days in the window
}

/**
 * MPR: supplied days of medication ÷ elapsed days in the window. Supplied days =
 * initial pill qty ÷ daily dose rate. Null when qty or rate is unknown (we can't
 * fabricate a ratio), mirroring RefillService's "can't project" guard.
 */
export function computeMpr(
	inventory: InventoryInput,
	opts: MetricOptions,
): MprResult {
	const elapsedDays = daysInWindow(opts.rangeStart, opts.rangeEnd);
	if (
		inventory.initialQty == null ||
		inventory.dailyRate <= 0 ||
		elapsedDays <= 0
	) {
		return {
			value: null,
			suppliedDays:
				inventory.initialQty != null && inventory.dailyRate > 0
					? inventory.initialQty / inventory.dailyRate
					: null,
			elapsedDays,
		};
	}
	const suppliedDays = inventory.initialQty / inventory.dailyRate;
	return {
		value: suppliedDays / elapsedDays,
		suppliedDays,
		elapsedDays,
	};
}

/******************************************************************************
        3/4/5. Dose-outcome rates (on-time / missed / late)
******************************************************************************/

export interface DoseRateResult {
	onTimeRate: number; // onTime / scheduled
	missedRate: number; // missed / scheduled
	lateRate: number; // late (taken, out of window) / scheduled
	onTime: number;
	missed: number;
	late: number;
	scheduled: number; // total scheduled doses in the window (denominator)
}

/**
 * Compute the on-time / missed / late dose rates over the window in one pass
 * (they share the same `scheduled` denominator, so deriving them together keeps
 * them consistent). Each scheduled dose is exactly one of: on-time, late, or
 * missed, so the three counts always sum to `scheduled`.
 */
export function computeDoseRates(
	events: DoseEvent[],
	opts: MetricOptions,
): DoseRateResult {
	const windowMinutes =
		opts.onTimeWindowMinutes ?? DEFAULT_ON_TIME_WINDOW_MINUTES;
	const inRange = withinRange(events, opts.rangeStart, opts.rangeEnd);

	let onTime = 0;
	let late = 0;
	let missed = 0;
	for (const e of inRange) {
		if (e.takenAt == null) {
			missed += 1;
		} else if (isOnTime(e, windowMinutes)) {
			onTime += 1;
		} else {
			late += 1;
		}
	}

	const scheduled = inRange.length;
	const ratio = (n: number) => (scheduled > 0 ? n / scheduled : 0);
	return {
		onTimeRate: ratio(onTime),
		missedRate: ratio(missed),
		lateRate: ratio(late),
		onTime,
		missed,
		late,
		scheduled,
	};
}

/******************************************************************************
        6/7. Adherence streaks (current + longest)
******************************************************************************/

export interface StreakResult {
	currentStreak: number; // consecutive most-recent fully-adherent days
	longestStreak: number; // longest run of fully-adherent days in the window
	adherentDays: number; // total fully-adherent days in the window
	totalDays: number;
}

/**
 * A day is "fully adherent" when EVERY scheduled dose on that day was taken.
 * Days with no scheduled doses are treated as neutral and DO NOT break a streak
 * (you can't miss a dose you weren't due) — they are skipped over so a Sunday
 * with nothing scheduled doesn't reset the streak.
 *
 *   - currentStreak: counting back from the most-recent scheduled day, the run
 *     of fully-adherent days until the first day with a miss.
 *   - longestStreak: the longest such run anywhere in the window.
 */
export function computeStreaks(
	events: DoseEvent[],
	opts: MetricOptions,
): StreakResult {
	const totalDays = daysInWindow(opts.rangeStart, opts.rangeEnd);
	const inRange = withinRange(events, opts.rangeStart, opts.rangeEnd);

	// Per-day: did every scheduled dose get taken?
	const dayScheduled = new Map<string, number>();
	const dayTaken = new Map<string, number>();
	for (const e of inRange) {
		const key = toDayKey(e.scheduledFor);
		dayScheduled.set(key, (dayScheduled.get(key) ?? 0) + 1);
		if (e.takenAt != null) dayTaken.set(key, (dayTaken.get(key) ?? 0) + 1);
	}

	// Ordered list of scheduled days (ascending) with an adherent flag.
	const days = [...dayScheduled.keys()].sort();
	const adherentFlags = days.map(
		(key) => (dayTaken.get(key) ?? 0) >= (dayScheduled.get(key) ?? 0),
	);

	let adherentDays = 0;
	let longestStreak = 0;
	let run = 0;
	for (const ok of adherentFlags) {
		if (ok) {
			adherentDays += 1;
			run += 1;
			if (run > longestStreak) longestStreak = run;
		} else {
			run = 0;
		}
	}

	// Current streak: walk back from the most-recent scheduled day.
	let currentStreak = 0;
	for (let i = adherentFlags.length - 1; i >= 0; i--) {
		if (adherentFlags[i]) currentStreak += 1;
		else break;
	}

	return { currentStreak, longestStreak, adherentDays, totalDays };
}

/******************************************************************************
        8. Dose-timing consistency
******************************************************************************/

export interface TimingConsistencyResult {
	/** Standard deviation (minutes) of (takenAt − scheduledFor) across taken
	 *  doses. Lower = more consistent timing. Null when < 2 taken doses. */
	stddevMinutes: number | null;
	/** Interquartile range (minutes) of the same deltas. Null when < 2 taken
	 *  doses. Robust to outliers, complementing the stddev. */
	iqrMinutes: number | null;
	/** Mean signed delta (minutes); positive = tends to take late. */
	meanDeltaMinutes: number | null;
	/** Number of taken doses the spread was measured over. */
	sampleSize: number;
}

/**
 * Dose-timing consistency: the SPREAD of how far (in minutes) actual take-times
 * land from their scheduled time. We report both the standard deviation and the
 * IQR (robust to outliers) of the signed deltas, plus the mean signed delta so a
 * consumer can see both consistency (spread) and bias (early/late tendency).
 *
 * Only TAKEN doses contribute (a missed dose has no take-time). Needs >= 2
 * samples for a spread; returns nulls otherwise.
 */
export function computeTimingConsistency(
	events: DoseEvent[],
	opts: MetricOptions,
): TimingConsistencyResult {
	const inRange = withinRange(events, opts.rangeStart, opts.rangeEnd);
	const deltas: number[] = [];
	for (const e of inRange) {
		if (e.takenAt != null) {
			deltas.push(
				(e.takenAt.getTime() - e.scheduledFor.getTime()) / MS_PER_MINUTE,
			);
		}
	}

	const sampleSize = deltas.length;
	if (sampleSize < 2) {
		return {
			stddevMinutes: null,
			iqrMinutes: null,
			meanDeltaMinutes: sampleSize === 1 ? deltas[0] : null,
			sampleSize,
		};
	}

	const mean = deltas.reduce((s, d) => s + d, 0) / sampleSize;
	const variance = deltas.reduce((s, d) => s + (d - mean) ** 2, 0) / sampleSize;
	const stddevMinutes = Math.sqrt(variance);

	const sorted = [...deltas].sort((a, b) => a - b);
	const q1 = quantile(sorted, 0.25);
	const q3 = quantile(sorted, 0.75);
	const iqrMinutes = q3 - q1;

	return {
		stddevMinutes,
		iqrMinutes,
		meanDeltaMinutes: mean,
		sampleSize,
	};
}

/** Linear-interpolation quantile of a pre-sorted ascending array. */
function quantile(sorted: number[], q: number): number {
	if (sorted.length === 1) return sorted[0];
	const pos = (sorted.length - 1) * q;
	const base = Math.floor(pos);
	const rest = pos - base;
	const lower = sorted[base];
	const upper = sorted[base + 1] ?? lower;
	return lower + rest * (upper - lower);
}

/******************************************************************************
        9. Confidence-weighted adherence (GTM-520 seam)
******************************************************************************/

export interface ConfidenceWeightedResult {
	/** Confidence-weighted adherence = Σ(confidence·taken) / Σ(confidence) over
	 *  scheduled doses. With all confidences defaulted to 1.0 this equals the
	 *  plain taken-rate; once GTM-520 supplies real scores, low-confidence events
	 *  contribute less. Null when there are no scheduled doses. */
	value: number | null;
	/** Σ confidence over taken doses. */
	weightedTaken: number;
	/** Σ confidence over all scheduled doses (the denominator). */
	weightedScheduled: number;
	/** Count of scheduled doses considered. */
	scheduled: number;
	/** True while every event's confidence is the GTM-520 default (1.0), i.e. the
	 *  confidence engine has not yet supplied real scores. */
	usingDefaultConfidence: boolean;
}

/**
 * Confidence-weighted adherence. Each scheduled dose contributes its data-
 * confidence weight; the metric is the confidence-weighted fraction of doses
 * taken.
 *
 * GTM-520 SEAM: confidence defaults to 1.0 per event (see `confidenceOf`), so
 * today this reduces to the plain taken-rate. When the confidence engine lands
 * and populates DoseEvent.confidence, this metric automatically down-weights
 * low-confidence signals with NO change here.
 */
export function computeConfidenceWeightedAdherence(
	events: DoseEvent[],
	opts: MetricOptions,
): ConfidenceWeightedResult {
	const inRange = withinRange(events, opts.rangeStart, opts.rangeEnd);

	let weightedTaken = 0;
	let weightedScheduled = 0;
	let usingDefaultConfidence = true;
	for (const e of inRange) {
		const w = confidenceOf(e);
		if (e.confidence != null && Number.isFinite(e.confidence)) {
			usingDefaultConfidence = false;
		}
		weightedScheduled += w;
		if (e.takenAt != null) weightedTaken += w;
	}

	const value =
		weightedScheduled > 0 ? weightedTaken / weightedScheduled : null;
	return {
		value,
		weightedTaken,
		weightedScheduled,
		scheduled: inRange.length,
		usingDefaultConfidence,
	};
}

/******************************************************************************
        Aggregate — all 9 metrics in one explainable object
******************************************************************************/

export interface AdherenceMetrics {
	window: {
		rangeStart: string;
		rangeEnd: string;
		onTimeWindowMinutes: number;
		totalDays: number;
	};
	pdc: PdcResult;
	mpr: MprResult;
	doseRates: DoseRateResult;
	streaks: StreakResult;
	timingConsistency: TimingConsistencyResult;
	confidenceWeightedAdherence: ConfidenceWeightedResult;
}

/**
 * Compute all 9 adherence metrics for a user over a window from their dose
 * events + inventory. Pure: deterministic given its inputs. The nine metrics:
 *   1 PDC, 2 MPR, 3 on-time rate, 4 missed rate, 5 late rate (3-5 in doseRates),
 *   6 current streak, 7 longest streak (in streaks), 8 timing consistency,
 *   9 confidence-weighted adherence.
 */
export function computeAdherenceMetrics(
	events: DoseEvent[],
	inventory: InventoryInput,
	opts: MetricOptions,
): AdherenceMetrics {
	const onTimeWindowMinutes =
		opts.onTimeWindowMinutes ?? DEFAULT_ON_TIME_WINDOW_MINUTES;
	const resolvedOpts: MetricOptions = { ...opts, onTimeWindowMinutes };

	return {
		window: {
			rangeStart: opts.rangeStart.toISOString(),
			rangeEnd: opts.rangeEnd.toISOString(),
			onTimeWindowMinutes,
			totalDays: daysInWindow(opts.rangeStart, opts.rangeEnd),
		},
		pdc: computePdc(events, resolvedOpts),
		mpr: computeMpr(inventory, resolvedOpts),
		doseRates: computeDoseRates(events, resolvedOpts),
		streaks: computeStreaks(events, resolvedOpts),
		timingConsistency: computeTimingConsistency(events, resolvedOpts),
		confidenceWeightedAdherence: computeConfidenceWeightedAdherence(
			events,
			resolvedOpts,
		),
	};
}
