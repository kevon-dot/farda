import {
	computeAdherenceMetrics,
	computeConfidenceWeightedAdherence,
	computeDoseRates,
	computeMpr,
	computePdc,
	computeStreaks,
	computeTimingConsistency,
	confidenceOf,
	DEFAULT_ON_TIME_WINDOW_MINUTES,
	type DoseEvent,
	daysInWindow,
	type MetricOptions,
} from "@src/services/AdherenceMetricsService";
import { describe, expect, it } from "vitest";

/**
 * Pure-function tests for the adherence-metrics engine (GTM-540 / GTM-502).
 * No DB, no Express — deterministic and CI-friendly, matching refillService.
 *
 * Convention: schedule doses at 09:00 UTC on consecutive June 2026 days. A dose
 * taken at 09:05 is on-time (±5 min), one at 12:00 is late (>30 min), null is
 * missed.
 */

/** Build a dose scheduled at 09:00 UTC on day `d` of June 2026, with an optional
 *  taken offset (minutes from 09:00) and confidence. */
function dose(
	day: number,
	takenOffsetMin: number | null,
	confidence?: number,
): DoseEvent {
	const scheduledFor = new Date(Date.UTC(2026, 5, day, 9, 0, 0));
	const takenAt =
		takenOffsetMin == null
			? null
			: new Date(scheduledFor.getTime() + takenOffsetMin * 60_000);
	return { scheduledFor, takenAt, confidence };
}

const WINDOW: MetricOptions = {
	rangeStart: new Date(Date.UTC(2026, 5, 1, 0, 0, 0)),
	rangeEnd: new Date(Date.UTC(2026, 5, 14, 23, 59, 59)),
};

describe("daysInWindow + confidenceOf helpers", () => {
	it("counts inclusive UTC days", () => {
		expect(daysInWindow(WINDOW.rangeStart, WINDOW.rangeEnd)).toBe(14);
	});
	it("single-day window is 1 day", () => {
		const d = new Date(Date.UTC(2026, 5, 1, 9, 0, 0));
		expect(daysInWindow(d, d)).toBe(1);
	});
	it("end-before-start yields 0", () => {
		expect(daysInWindow(WINDOW.rangeEnd, WINDOW.rangeStart)).toBe(0);
	});
	it("defaults confidence to 1.0 and clamps to [0,1]", () => {
		expect(confidenceOf({ scheduledFor: new Date() })).toBe(1);
		expect(confidenceOf({ scheduledFor: new Date(), confidence: 0.4 })).toBe(
			0.4,
		);
		expect(confidenceOf({ scheduledFor: new Date(), confidence: 2 })).toBe(1);
		expect(confidenceOf({ scheduledFor: new Date(), confidence: -1 })).toBe(0);
		expect(confidenceOf({ scheduledFor: new Date(), confidence: null })).toBe(
			1,
		);
	});
});

describe("computePdc", () => {
	it("perfect adherence: covered == scheduled days", () => {
		const events = [1, 2, 3, 4, 5].map((d) => dose(d, 5));
		const r = computePdc(events, WINDOW);
		expect(r.coveredDays).toBe(5);
		expect(r.scheduledDays).toBe(5);
		expect(r.totalDays).toBe(14);
		expect(r.value).toBeCloseTo(5 / 14, 10);
	});

	it("all-missed: 0 covered days", () => {
		const events = [1, 2, 3, 4, 5].map((d) => dose(d, null));
		const r = computePdc(events, WINDOW);
		expect(r.coveredDays).toBe(0);
		expect(r.scheduledDays).toBe(5);
		expect(r.value).toBe(0);
	});

	it("a day with 2 doses where one is taken counts as covered", () => {
		const events = [dose(1, 5), { ...dose(1, null) }, dose(2, null)];
		const r = computePdc(events, WINDOW);
		expect(r.coveredDays).toBe(1); // day 1 covered, day 2 missed
		expect(r.scheduledDays).toBe(2);
	});

	it("empty window (no doses) -> value 0", () => {
		const r = computePdc([], WINDOW);
		expect(r.coveredDays).toBe(0);
		expect(r.value).toBe(0);
	});
});

describe("computeMpr", () => {
	it("supplied days / elapsed days", () => {
		// 30 pills at 1/day = 30 supplied days over a 14-day window -> 30/14.
		const r = computeMpr({ initialQty: 30, dailyRate: 1 }, WINDOW);
		expect(r.suppliedDays).toBe(30);
		expect(r.elapsedDays).toBe(14);
		expect(r.value).toBeCloseTo(30 / 14, 10);
	});

	it("2/day rate halves supplied days", () => {
		const r = computeMpr({ initialQty: 60, dailyRate: 2 }, WINDOW);
		expect(r.suppliedDays).toBe(30);
		expect(r.value).toBeCloseTo(30 / 14, 10);
	});

	it("null qty -> null value", () => {
		const r = computeMpr({ initialQty: null, dailyRate: 1 }, WINDOW);
		expect(r.value).toBeNull();
		expect(r.suppliedDays).toBeNull();
	});

	it("zero rate -> null value", () => {
		const r = computeMpr({ initialQty: 30, dailyRate: 0 }, WINDOW);
		expect(r.value).toBeNull();
	});
});

describe("computeDoseRates (on-time / missed / late)", () => {
	it("perfect on-time adherence", () => {
		const events = [1, 2, 3, 4].map((d) => dose(d, 5));
		const r = computeDoseRates(events, WINDOW);
		expect(r.scheduled).toBe(4);
		expect(r.onTime).toBe(4);
		expect(r.onTimeRate).toBe(1);
		expect(r.missedRate).toBe(0);
		expect(r.lateRate).toBe(0);
	});

	it("all missed", () => {
		const events = [1, 2, 3, 4].map((d) => dose(d, null));
		const r = computeDoseRates(events, WINDOW);
		expect(r.missed).toBe(4);
		expect(r.missedRate).toBe(1);
		expect(r.onTime).toBe(0);
		expect(r.late).toBe(0);
	});

	it("mixed on-time / late / missed sums to scheduled", () => {
		// day1 on-time(5m), day2 late(180m), day3 missed, day4 on-time at exactly
		// the +30m boundary (inclusive -> on-time).
		const events = [dose(1, 5), dose(2, 180), dose(3, null), dose(4, 30)];
		const r = computeDoseRates(events, WINDOW);
		expect(r.scheduled).toBe(4);
		expect(r.onTime).toBe(2);
		expect(r.late).toBe(1);
		expect(r.missed).toBe(1);
		expect(r.onTime + r.late + r.missed).toBe(r.scheduled);
		expect(r.onTimeRate).toBe(0.5);
		expect(r.lateRate).toBe(0.25);
		expect(r.missedRate).toBe(0.25);
	});

	it("early beyond the window counts as late", () => {
		const events = [dose(1, -45)]; // 45 min early
		const r = computeDoseRates(events, WINDOW);
		expect(r.late).toBe(1);
		expect(r.onTime).toBe(0);
	});

	it("a tighter on-time window reclassifies a borderline dose as late", () => {
		const events = [dose(1, 20)]; // 20 min late
		expect(computeDoseRates(events, WINDOW).onTime).toBe(1); // default ±30
		const tight = computeDoseRates(events, {
			...WINDOW,
			onTimeWindowMinutes: 10,
		});
		expect(tight.onTime).toBe(0);
		expect(tight.late).toBe(1);
	});

	it("empty window -> all rates 0", () => {
		const r = computeDoseRates([], WINDOW);
		expect(r.scheduled).toBe(0);
		expect(r.onTimeRate).toBe(0);
		expect(r.missedRate).toBe(0);
		expect(r.lateRate).toBe(0);
	});
});

describe("computeStreaks", () => {
	it("perfect adherence: current == longest == adherent days", () => {
		const events = [1, 2, 3, 4, 5].map((d) => dose(d, 5));
		const r = computeStreaks(events, WINDOW);
		expect(r.adherentDays).toBe(5);
		expect(r.longestStreak).toBe(5);
		expect(r.currentStreak).toBe(5);
	});

	it("all-missed: zero streaks", () => {
		const events = [1, 2, 3].map((d) => dose(d, null));
		const r = computeStreaks(events, WINDOW);
		expect(r.adherentDays).toBe(0);
		expect(r.longestStreak).toBe(0);
		expect(r.currentStreak).toBe(0);
	});

	it("miss in the middle: longest is the longer run, current is the tail run", () => {
		// days 1,2 ok | day 3 missed | days 4,5,6 ok -> longest 3, current 3.
		const events = [
			dose(1, 5),
			dose(2, 5),
			dose(3, null),
			dose(4, 5),
			dose(5, 5),
			dose(6, 5),
		];
		const r = computeStreaks(events, WINDOW);
		expect(r.adherentDays).toBe(5);
		expect(r.longestStreak).toBe(3);
		expect(r.currentStreak).toBe(3);
	});

	it("most-recent day missed breaks the current streak to 0", () => {
		const events = [dose(1, 5), dose(2, 5), dose(3, null)];
		const r = computeStreaks(events, WINDOW);
		expect(r.longestStreak).toBe(2);
		expect(r.currentStreak).toBe(0);
	});

	it("a day is adherent only if EVERY scheduled dose was taken", () => {
		// day1: 2 doses, one missed -> not adherent. day2: both taken -> adherent.
		const events = [
			dose(1, 5),
			{ ...dose(1, null) },
			dose(2, 5),
			{ ...dose(2, 5) },
		];
		const r = computeStreaks(events, WINDOW);
		expect(r.adherentDays).toBe(1);
		expect(r.currentStreak).toBe(1);
		expect(r.longestStreak).toBe(1);
	});

	it("single-day perfect window", () => {
		const r = computeStreaks([dose(1, 5)], WINDOW);
		expect(r.currentStreak).toBe(1);
		expect(r.longestStreak).toBe(1);
	});
});

describe("computeTimingConsistency", () => {
	it("returns nulls with < 2 taken doses", () => {
		expect(computeTimingConsistency([], WINDOW).stddevMinutes).toBeNull();
		const one = computeTimingConsistency([dose(1, 10)], WINDOW);
		expect(one.stddevMinutes).toBeNull();
		expect(one.meanDeltaMinutes).toBe(10);
		expect(one.sampleSize).toBe(1);
	});

	it("identical deltas -> zero spread", () => {
		const events = [dose(1, 10), dose(2, 10), dose(3, 10)];
		const r = computeTimingConsistency(events, WINDOW);
		expect(r.stddevMinutes).toBe(0);
		expect(r.iqrMinutes).toBe(0);
		expect(r.meanDeltaMinutes).toBe(10);
		expect(r.sampleSize).toBe(3);
	});

	it("computes population stddev of signed deltas", () => {
		// deltas: 0, 10, 20, 30 -> mean 15, variance ((225+25+25+225)/4)=125.
		const events = [dose(1, 0), dose(2, 10), dose(3, 20), dose(4, 30)];
		const r = computeTimingConsistency(events, WINDOW);
		expect(r.meanDeltaMinutes).toBe(15);
		expect(r.stddevMinutes).toBeCloseTo(Math.sqrt(125), 10);
		// IQR via linear interpolation on [0,10,20,30]: q1=7.5, q3=22.5 -> 15.
		expect(r.iqrMinutes).toBeCloseTo(15, 10);
	});

	it("ignores missed doses (only taken contribute)", () => {
		const events = [dose(1, 10), dose(2, null), dose(3, 20)];
		const r = computeTimingConsistency(events, WINDOW);
		expect(r.sampleSize).toBe(2);
		expect(r.meanDeltaMinutes).toBe(15);
	});
});

describe("computeConfidenceWeightedAdherence", () => {
	it("all default confidence reduces to plain taken-rate", () => {
		const events = [dose(1, 5), dose(2, null), dose(3, 5), dose(4, 5)];
		const r = computeConfidenceWeightedAdherence(events, WINDOW);
		expect(r.usingDefaultConfidence).toBe(true);
		expect(r.weightedScheduled).toBe(4);
		expect(r.weightedTaken).toBe(3);
		expect(r.value).toBe(0.75);
	});

	it("down-weights low-confidence events (GTM-520 wiring)", () => {
		// taken with conf 1.0 + missed with conf 0.2 + taken with conf 0.5.
		const events = [dose(1, 5, 1.0), dose(2, null, 0.2), dose(3, 5, 0.5)];
		const r = computeConfidenceWeightedAdherence(events, WINDOW);
		expect(r.usingDefaultConfidence).toBe(false);
		expect(r.weightedScheduled).toBeCloseTo(1.7, 10);
		expect(r.weightedTaken).toBeCloseTo(1.5, 10);
		expect(r.value).toBeCloseTo(1.5 / 1.7, 10);
	});

	it("perfect adherence -> value 1", () => {
		const events = [dose(1, 5), dose(2, 5)];
		expect(computeConfidenceWeightedAdherence(events, WINDOW).value).toBe(1);
	});

	it("empty window -> null value", () => {
		expect(computeConfidenceWeightedAdherence([], WINDOW).value).toBeNull();
	});
});

describe("computeAdherenceMetrics (aggregate, all 9)", () => {
	it("packages all nine metrics with an explainable window", () => {
		const events = [dose(1, 5), dose(2, 180), dose(3, null), dose(4, 5)];
		const m = computeAdherenceMetrics(
			events,
			{ initialQty: 30, dailyRate: 1 },
			WINDOW,
		);

		expect(m.window.totalDays).toBe(14);
		expect(m.window.onTimeWindowMinutes).toBe(DEFAULT_ON_TIME_WINDOW_MINUTES);

		// 1 PDC
		expect(m.pdc.coveredDays).toBe(3);
		// 2 MPR
		expect(m.mpr.value).toBeCloseTo(30 / 14, 10);
		// 3/4/5 dose rates
		expect(m.doseRates.onTime).toBe(2);
		expect(m.doseRates.late).toBe(1);
		expect(m.doseRates.missed).toBe(1);
		// 6/7 streaks
		expect(m.streaks.currentStreak).toBe(1); // day 4 ok, day 3 missed
		expect(m.streaks.longestStreak).toBe(2); // days 1,2 ok
		// 8 timing consistency (3 taken doses)
		expect(m.timingConsistency.sampleSize).toBe(3);
		// 9 confidence-weighted (defaults)
		expect(m.confidenceWeightedAdherence.usingDefaultConfidence).toBe(true);
		expect(m.confidenceWeightedAdherence.value).toBeCloseTo(3 / 4, 10);
	});

	it("respects a custom on-time window in the aggregate", () => {
		const events = [dose(1, 20)];
		const m = computeAdherenceMetrics(
			events,
			{ initialQty: null, dailyRate: 0 },
			{
				...WINDOW,
				onTimeWindowMinutes: 10,
			},
		);
		expect(m.window.onTimeWindowMinutes).toBe(10);
		expect(m.doseRates.late).toBe(1);
		expect(m.mpr.value).toBeNull();
	});
});
