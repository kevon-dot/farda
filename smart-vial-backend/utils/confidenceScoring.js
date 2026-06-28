// ============================================
// GTM-520 — Dose confidence-scoring engine
// ============================================
// Turns the GTM-519 dose-event MICROSTRUCTURE ("we think they took it") into a
// MEASURED INTEGRITY signal: a calibrated, per-dose-event confidence in [0, 1]
// plus a transparent factor breakdown. The score answers "how sure are we the
// taken/missed signal this dose event implies is REAL?" — not whether a dose was
// taken, but whether the captured microstructure is internally consistent enough
// to trust.
//
// Pure + deterministic: this module is a pure function of one normalized
// DoseEvent microstructure (the validator's output shape — ordered stages with
// numeric payloads). No DB, no clock, no randomness. The same input always yields
// the same score, so it is fully unit-testable and the ingest path can compute it
// inline.
//
// PHI-free: like the microstructure it scores, this engine reads only
// numbers/codes (weights in mg, durations in ms, stage order). It never reads or
// emits a medication, name, or condition.
//
// Versioned: SCORING_VERSION pins the factor set + weights + banding so a persisted
// `confidence` can always be traced back to the algorithm that produced it. Bump
// it on ANY change to factors, weights, config defaults, or banding thresholds.
//
// CROSS-SERVICE SEAM → GTM-540 (Main API adherence-metrics engine):
//   Events live in the Vial API (here); confidence-weighted adherence metrics live
//   in the Main API (farda-app-backend AdherenceMetricsService). That engine reads
//   an OPTIONAL per-event `confidence` in [0, 1] and DEFAULTS it to 1.0 when absent
//   (see `confidenceOf` there). This engine produces exactly that scalar and the
//   ingest path persists it on the DoseEvent; the existing device-event relay then
//   forwards it to the Main API. We do NOT call the Main API here — we only ensure
//   the Vial DoseEvent now carries a real `confidence` the relay can forward.

const {
  DOSE_STAGE,
  REQUIRED_STAGES,
  STAGE_ORDINAL,
} = require("./doseEventValidation");

// ---------------------------------------------------------------------------
// Scoring version. Bump on ANY change to factors, weights, config defaults, or
// banding thresholds so a persisted `confidence` is always traceable.
// ---------------------------------------------------------------------------
const SCORING_VERSION = 1;

// ---------------------------------------------------------------------------
// Calibration config — overridable named constants.
//
// HARDWARE-CALIBRATION SEAM: `expected_pill_mass_mg` is a PLACEHOLDER. Real
// per-pill mass (and its tolerance) is a property of the dispensed medication and
// arrives with hardware calibration — at which point a caller will pass a
// per-device / per-regimen value through `config.expected_pill_mass_mg` (and
// `pill_mass_tolerance_mg`) instead of this default. Until then we score against a
// single nominal pill mass with a generous tolerance so a plausible single-pill
// removal still bands HIGH. Everything below is overridable per call.
// ---------------------------------------------------------------------------
const DEFAULT_CONFIG = Object.freeze({
  // Expected mass removed per dispensed pill (mg). HARDWARE-CALIBRATION SEAM.
  expected_pill_mass_mg: 250,
  // Default dispensed pill count when the microstructure does not carry one.
  // (The GTM-519 microstructure has no pill-count field today; a future stage
  // payload may supply it — pass `config.dispensed_pill_count` to override.)
  dispensed_pill_count: 1,
  // Half-width (mg) of the weight-delta tolerance band around expected mass at
  // which the weight factor decays to ~0. A |error| of this many mg ⇒ sub-score 0;
  // |error| of 0 ⇒ sub-score 1; linear in between. HARDWARE-CALIBRATION SEAM.
  pill_mass_tolerance_mg: 250,

  // Cap-open duration plausibility window (ms). Below `min` the open was too brief
  // to physically remove a pill (phantom open) ⇒ penalized. At/above `ideal` the
  // open is comfortably long enough ⇒ full sub-score. Linear ramp between.
  cap_open_min_ms: 300,
  cap_open_ideal_ms: 1000,

  // Factor weights (need not sum to 1; the final score is the weighted MEAN, so
  // weights are relative). Weight-delta is the strongest evidence of an actual
  // dose, so it dominates.
  weights: Object.freeze({
    weightDelta: 0.5,
    capOpenDuration: 0.2,
    sequenceCompleteness: 0.15,
    timingPlausibility: 0.15,
  }),

  // Confidence banding thresholds (inclusive lower bounds).
  band_high: 0.8,
  band_medium: 0.5,

  // Weight-delta GATE. The measured removed mass is the strongest evidence a dose
  // physically happened: if it's absent (phantom / near-zero delta), the dose
  // cannot be HIGH/MEDIUM confidence no matter how clean the rest of the
  // microstructure is. The final confidence is capped at
  //   weight_gate_floor + weightDeltaScore · (1 - weight_gate_floor)
  // so a weight sub-score of 0 caps confidence at `weight_gate_floor` (LOW band)
  // while a perfect weight sub-score lifts the cap to 1.0 (no effect). This makes
  // "large mass mismatch ⇒ low confidence" a hard guarantee, not just a heavy
  // weighting.
  weight_gate_floor: 0.4,
});

// ---------------------------------------------------------------------------
// Small helpers.
// ---------------------------------------------------------------------------
function clamp01(x) {
  if (!Number.isFinite(x)) return 0;
  if (x < 0) return 0;
  if (x > 1) return 1;
  return x;
}

function round(x, places = 4) {
  const f = 10 ** places;
  return Math.round(x * f) / f;
}

// Index stages by type for O(1) factor lookups. The validator guarantees each
// required backbone stage appears exactly once, so first-match is safe.
function indexStages(stages) {
  const byType = new Map();
  for (const s of stages || []) {
    if (!byType.has(s.type)) byType.set(s.type, s);
  }
  return byType;
}

// ---------------------------------------------------------------------------
// FACTOR 1 — weight-delta vs expected pill mass (the strongest factor).
//
// Closeness of the measured removed mass to the expected mass for the dispensed
// pill count. We prefer the explicit WEIGHT_DELTA stage's `delta_mg`; if missing
// we derive it from WEIGH_BEFORE - WEIGH_AFTER. A removal is a mass DECREASE, so
// the removed mass is `max(0, -delta)`. Sub-score is 1 when the removed mass hits
// the expected mass exactly and decays linearly to 0 at `pill_mass_tolerance_mg`
// of absolute error (in either direction). A near-zero delta (phantom / no pill
// removed) therefore scores low; a removal far heavier than expected also scores
// low (wrong pill count / spill / sensor fault).
// ---------------------------------------------------------------------------
function scoreWeightDelta(byType, cfg) {
  const expected = cfg.expected_pill_mass_mg * cfg.dispensed_pill_count;
  const tol = cfg.pill_mass_tolerance_mg > 0 ? cfg.pill_mass_tolerance_mg : 1;

  const deltaStage = byType.get(DOSE_STAGE.WEIGHT_DELTA);
  const before = byType.get(DOSE_STAGE.WEIGH_BEFORE);
  const after = byType.get(DOSE_STAGE.WEIGH_AFTER);

  let removedMass = null;
  let source = null;
  if (deltaStage && typeof deltaStage.payload?.delta_mg === "number") {
    // delta_mg is signed; a dose REMOVES mass (negative). Removed mass is the
    // magnitude of a decrease; a positive delta (mass gained) means no removal.
    removedMass = Math.max(0, -deltaStage.payload.delta_mg);
    source = "WEIGHT_DELTA";
  } else if (
    before &&
    after &&
    typeof before.payload?.weight_mg === "number" &&
    typeof after.payload?.weight_mg === "number"
  ) {
    removedMass = Math.max(0, before.payload.weight_mg - after.payload.weight_mg);
    source = "WEIGH_BEFORE-WEIGH_AFTER";
  }

  if (removedMass === null) {
    return {
      score: 0,
      detail: {
        source: null,
        expected_mass_mg: expected,
        removed_mass_mg: null,
        error_mg: null,
        reason: "no weight signal (WEIGHT_DELTA / weigh pair) available",
      },
    };
  }

  const errorMg = Math.abs(removedMass - expected);
  const score = clamp01(1 - errorMg / tol);
  return {
    score,
    detail: {
      source,
      expected_mass_mg: expected,
      removed_mass_mg: round(removedMass, 2),
      error_mg: round(errorMg, 2),
      tolerance_mg: tol,
    },
  };
}

// ---------------------------------------------------------------------------
// FACTOR 2 — cap-open duration plausibility.
//
// A real pill removal needs the cap open long enough to reach in and take a pill.
// A vanishingly short open is a phantom (knock / brush) and should depress
// confidence. Below `cap_open_min_ms` ⇒ 0; at/above `cap_open_ideal_ms` ⇒ 1;
// linear ramp between. A missing duration is treated as UNKNOWN (neutral 0.5) so
// firmware that doesn't report duration_ms isn't unfairly penalized — it just
// doesn't get the positive evidence either.
// ---------------------------------------------------------------------------
function scoreCapOpenDuration(byType, cfg) {
  const capOpen = byType.get(DOSE_STAGE.CAP_OPEN);
  const durRaw = capOpen?.payload?.duration_ms;
  if (typeof durRaw !== "number") {
    return {
      score: 0.5,
      detail: { duration_ms: null, reason: "cap-open duration not reported (neutral)" },
    };
  }
  const { cap_open_min_ms: min, cap_open_ideal_ms: ideal } = cfg;
  let score;
  if (durRaw <= min) score = 0;
  else if (durRaw >= ideal) score = 1;
  else score = (durRaw - min) / (ideal - min);
  return {
    score: clamp01(score),
    detail: { duration_ms: durRaw, min_ms: min, ideal_ms: ideal },
  };
}

// ---------------------------------------------------------------------------
// FACTOR 3 — sequence completeness / ordering.
//
// GTM-519 already guarantees a persisted microstructure is complete + ordered, so
// for a stored DoseEvent this factor is a confirming 1.0. We re-check defensively
// (this engine is pure and may be handed a partial structure in a test or a future
// streaming context): every required backbone stage present exactly once AND the
// assigned `order` is a non-decreasing walk through the canonical ordinals.
// ---------------------------------------------------------------------------
function scoreSequenceCompleteness(stages, byType) {
  const missing = [];
  for (const req of REQUIRED_STAGES) {
    if (!byType.has(req)) missing.push(req);
  }

  // Ordering: walk stages in their assigned `order` and assert ordinals are
  // non-decreasing (matches the validator's invariant).
  const ordered = [...(stages || [])].sort(
    (a, b) => (a.order ?? 0) - (b.order ?? 0)
  );
  let ordinalViolations = 0;
  let prev = -1;
  for (const s of ordered) {
    const ord = STAGE_ORDINAL[s.type];
    if (ord === undefined) continue;
    if (ord < prev) ordinalViolations += 1;
    prev = ord;
  }

  const complete = missing.length === 0;
  const ordered_ok = ordinalViolations === 0;
  const score = complete && ordered_ok ? 1 : complete ? 0.5 : 0;
  return {
    score,
    detail: {
      complete,
      ordered: ordered_ok,
      missing_stages: missing,
      ordinal_violations: ordinalViolations,
    },
  };
}

// ---------------------------------------------------------------------------
// FACTOR 4 — timing plausibility.
//
// Even when the type ORDER is valid, the device-reported timestamps must be
// physically sane: weigh-before must not be timestamped AFTER weigh-after, and the
// reported cap durations must be non-negative. Implausible / missing timing
// (e.g. weigh-after stamped before weigh-before, or a negative duration) penalizes
// confidence. Stages with null device_timestamps are treated as "no evidence"
// rather than a violation (the canonical record time is server-set anyway).
// ---------------------------------------------------------------------------
function scoreTimingPlausibility(byType) {
  const issues = [];

  const before = byType.get(DOSE_STAGE.WEIGH_BEFORE);
  const after = byType.get(DOSE_STAGE.WEIGH_AFTER);
  if (
    before &&
    after &&
    typeof before.device_timestamp === "number" &&
    typeof after.device_timestamp === "number" &&
    before.device_timestamp > after.device_timestamp
  ) {
    issues.push("weigh-before timestamp is after weigh-after");
  }

  for (const t of [DOSE_STAGE.CAP_OPEN, DOSE_STAGE.CAP_CLOSE]) {
    const stage = byType.get(t);
    const dur = stage?.payload?.duration_ms;
    if (typeof dur === "number" && dur < 0) {
      issues.push(`${t} reports a negative duration_ms`);
    }
  }

  // Each distinct issue halves the timing sub-score (1 → 0.5 → 0.25 ...), so a
  // single anomaly is a meaningful but not total penalty, and stacking anomalies
  // drives it toward 0.
  const score = clamp01(1 / 2 ** issues.length);
  return { score, detail: { plausible: issues.length === 0, issues } };
}

// ---------------------------------------------------------------------------
// Banding.
// ---------------------------------------------------------------------------
function bandFor(confidence, cfg) {
  if (confidence >= cfg.band_high) return "high";
  if (confidence >= cfg.band_medium) return "medium";
  return "low";
}

// ---------------------------------------------------------------------------
// scoreDoseEventConfidence
//
// Compute the calibrated confidence + factor breakdown for ONE normalized
// dose-event microstructure (the validator's output shape, or a persisted
// DoseEvent: an object with an ordered `stages` array of { type, order,
// device_timestamp, payload }).
//
// @param {{stages: Array}} doseEvent normalized microstructure
// @param {object} [config] overrides merged over DEFAULT_CONFIG (e.g. real
//        per-pill mass / dispensed count from hardware calibration)
// @returns {{
//   confidence: number,              // calibrated score in [0,1]
//   confidenceLevel: "high"|"medium"|"low",
//   scoringVersion: number,
//   factors: { [name]: { score, weight, detail } },
//   contributing: string[],          // factors that raised confidence (score ≥ 0.75)
//   penalizing: string[],            // factors that lowered it (score < 0.5)
// }}
// ---------------------------------------------------------------------------
function scoreDoseEventConfidence(doseEvent, config = {}) {
  const cfg = {
    ...DEFAULT_CONFIG,
    ...config,
    weights: { ...DEFAULT_CONFIG.weights, ...(config.weights || {}) },
  };

  const stages = Array.isArray(doseEvent?.stages) ? doseEvent.stages : [];
  const byType = indexStages(stages);

  const factorResults = {
    weightDelta: scoreWeightDelta(byType, cfg),
    capOpenDuration: scoreCapOpenDuration(byType, cfg),
    sequenceCompleteness: scoreSequenceCompleteness(stages, byType),
    timingPlausibility: scoreTimingPlausibility(byType),
  };

  // Weighted MEAN of the sub-scores (weights are relative; normalized by their
  // sum so the final score stays in [0,1] regardless of the weight magnitudes).
  let weightedSum = 0;
  let weightTotal = 0;
  const factors = {};
  const contributing = [];
  const penalizing = [];

  for (const [name, result] of Object.entries(factorResults)) {
    const weight = cfg.weights[name] ?? 0;
    const score = clamp01(result.score);
    weightedSum += score * weight;
    weightTotal += weight;
    factors[name] = { score: round(score), weight, detail: result.detail };
    if (score >= 0.75) contributing.push(name);
    if (score < 0.5) penalizing.push(name);
  }

  const weightedMean = weightTotal > 0 ? weightedSum / weightTotal : 0;

  // Weight-delta GATE: cap the final confidence by the strongest factor so a
  // missing/implausible removed-mass signal can never band HIGH/MEDIUM (see
  // `weight_gate_floor`). The cap rises linearly from the floor (weight score 0)
  // to 1.0 (weight score 1), so a clean dose is unaffected.
  const weightScore = factors.weightDelta.score;
  const gateCap = cfg.weight_gate_floor + weightScore * (1 - cfg.weight_gate_floor);
  const confidence = round(Math.min(weightedMean, gateCap));
  const confidenceLevel = bandFor(confidence, cfg);

  return {
    confidence,
    confidenceLevel,
    scoringVersion: SCORING_VERSION,
    factors,
    contributing,
    penalizing,
  };
}

module.exports = {
  SCORING_VERSION,
  DEFAULT_CONFIG,
  scoreDoseEventConfidence,
  bandFor,
  // Exported for focused unit testing of individual factors.
  _factors: {
    scoreWeightDelta,
    scoreCapOpenDuration,
    scoreSequenceCompleteness,
    scoreTimingPlausibility,
  },
};
