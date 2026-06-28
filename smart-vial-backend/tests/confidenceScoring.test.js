const test = require("node:test");
const assert = require("node:assert");

// ============================================
// GTM-520 — Dose confidence-scoring engine unit tests
// ============================================
// Pure scorer tests (no DB, no models). Prove the engine turns a normalized
// microstructure into a calibrated confidence in [0,1] with a transparent factor
// breakdown: a perfect dose bands HIGH, a weight mismatch bands LOW, a too-short
// cap-open is penalized, implausible/missing timing is penalized, banding
// thresholds hold, the score is deterministic, and the breakdown is asserted.

const {
  SCORING_VERSION,
  DEFAULT_CONFIG,
  scoreDoseEventConfidence,
  bandFor,
  _factors,
} = require("../utils/confidenceScoring");
const { DOSE_STAGE } = require("../utils/doseEventValidation");

// Build a normalized DoseEvent (validator-output shape): ordered stages with
// { type, order, device_timestamp, payload }. Defaults model a clean single-pill
// removal whose removed mass exactly matches the default expected pill mass.
function normalizedStages(overrides = {}) {
  // Use `in` checks (not `??`) so an explicit `null` override is honored — `null`
  // means "omit this payload field", which is distinct from "use the default".
  const has = (k) => Object.prototype.hasOwnProperty.call(overrides, k);
  const expected = DEFAULT_CONFIG.expected_pill_mass_mg; // 250
  const weighBefore = has("weighBefore") ? overrides.weighBefore : 5000;
  const weighAfter = has("weighAfter") ? overrides.weighAfter : weighBefore - expected;
  const deltaMg = has("deltaMg") ? overrides.deltaMg : weighAfter - weighBefore; // -250
  const capOpenMs = has("capOpenMs") ? overrides.capOpenMs : 1200;
  const capCloseMs = has("capCloseMs") ? overrides.capCloseMs : 800;
  const weighBeforeTs = has("weighBeforeTs") ? overrides.weighBeforeTs : 1012;
  const weighAfterTs = has("weighAfterTs") ? overrides.weighAfterTs : 1013;

  const raw = [
    { type: DOSE_STAGE.REMINDER_FIRED, device_timestamp: 1000, payload: { reminder_index: 0, channel: "PUSH" } },
    { type: DOSE_STAGE.UNLOCK, device_timestamp: 1010, payload: {} },
    { type: DOSE_STAGE.CAP_OPEN, device_timestamp: 1011, payload: capOpenMs === null ? {} : { duration_ms: capOpenMs } },
    { type: DOSE_STAGE.WEIGH_BEFORE, device_timestamp: weighBeforeTs, payload: { weight_mg: weighBefore } },
    { type: DOSE_STAGE.WEIGH_AFTER, device_timestamp: weighAfterTs, payload: { weight_mg: weighAfter } },
    { type: DOSE_STAGE.WEIGHT_DELTA, device_timestamp: 1014, payload: deltaMg === null ? {} : { delta_mg: deltaMg } },
    { type: DOSE_STAGE.CAP_CLOSE, device_timestamp: 1015, payload: capCloseMs === null ? {} : { duration_ms: capCloseMs } },
    { type: DOSE_STAGE.SYNC, device_timestamp: 1020, payload: { transport: "BLE" } },
  ];
  return raw.map((s, order) => ({ ...s, order, token: `${s.type}@${order}` }));
}

function doseEvent(overrides = {}) {
  return { stages: normalizedStages(overrides) };
}

// ----------------------------------------------------------------------------
// Perfect dose ⇒ HIGH
// ----------------------------------------------------------------------------

test("perfect dose (weight-delta ≈ expected, clean sequence, plausible timing) bands HIGH", () => {
  const r = scoreDoseEventConfidence(doseEvent());
  assert.strictEqual(r.scoringVersion, SCORING_VERSION);
  assert.ok(r.confidence >= DEFAULT_CONFIG.band_high, `expected high, got ${r.confidence}`);
  assert.strictEqual(r.confidenceLevel, "high");
  // A perfect dose maxes every factor.
  assert.strictEqual(r.factors.weightDelta.score, 1);
  assert.strictEqual(r.factors.capOpenDuration.score, 1);
  assert.strictEqual(r.factors.sequenceCompleteness.score, 1);
  assert.strictEqual(r.factors.timingPlausibility.score, 1);
  // Confidence is in range.
  assert.ok(r.confidence >= 0 && r.confidence <= 1);
});

test("perfect dose using the weigh pair (no WEIGHT_DELTA stage) still scores the weight factor", () => {
  const r = scoreDoseEventConfidence(doseEvent({ deltaMg: null }));
  assert.strictEqual(r.factors.weightDelta.detail.source, "WEIGH_BEFORE-WEIGH_AFTER");
  assert.strictEqual(r.factors.weightDelta.score, 1);
  assert.strictEqual(r.confidenceLevel, "high");
});

// ----------------------------------------------------------------------------
// Weight mismatch ⇒ LOW (strongest factor)
// ----------------------------------------------------------------------------

test("weight mismatch (zero removed mass = phantom) bands LOW", () => {
  // 0 mg removed but expected 250 mg ⇒ error == tolerance ⇒ weight score 0.
  const r = scoreDoseEventConfidence(doseEvent({ deltaMg: 0, weighAfter: 5000 }));
  assert.strictEqual(r.factors.weightDelta.score, 0);
  assert.ok(r.penalizing.includes("weightDelta"));
  assert.strictEqual(r.confidenceLevel, "low");
  assert.ok(r.confidence < DEFAULT_CONFIG.band_medium, `expected low, got ${r.confidence}`);
});

test("weight mismatch (far too heavy) also drives weight factor to 0", () => {
  // 600 mg removed vs 250 expected ⇒ error 350 > tolerance 250 ⇒ clamps to 0.
  const r = scoreDoseEventConfidence(doseEvent({ deltaMg: -600, weighAfter: 4400 }));
  assert.strictEqual(r.factors.weightDelta.score, 0);
  assert.strictEqual(r.factors.weightDelta.detail.error_mg, 350);
  assert.ok(r.penalizing.includes("weightDelta"));
});

test("weight factor decays linearly within tolerance", () => {
  // 125 mg removed vs 250 expected ⇒ error 125 == tol/2 ⇒ score 0.5.
  const r = _factors.scoreWeightDelta(
    new Map([
      [DOSE_STAGE.WEIGHT_DELTA, { payload: { delta_mg: -125 } }],
    ]),
    DEFAULT_CONFIG
  );
  assert.strictEqual(r.score, 0.5);
});

// ----------------------------------------------------------------------------
// Cap-open duration penalty
// ----------------------------------------------------------------------------

test("too-short cap-open is penalized (below min ⇒ factor 0)", () => {
  const r = scoreDoseEventConfidence(doseEvent({ capOpenMs: 100 }));
  assert.strictEqual(r.factors.capOpenDuration.score, 0);
  assert.ok(r.penalizing.includes("capOpenDuration"));
  // Weight factor is still perfect, so it doesn't crash to low — it's just lower
  // than a perfect dose.
  const perfect = scoreDoseEventConfidence(doseEvent());
  assert.ok(r.confidence < perfect.confidence);
});

test("missing cap-open duration is neutral (0.5), not a hard penalty", () => {
  const r = scoreDoseEventConfidence(doseEvent({ capOpenMs: null }));
  assert.strictEqual(r.factors.capOpenDuration.score, 0.5);
  assert.strictEqual(r.factors.capOpenDuration.detail.duration_ms, null);
});

test("cap-open duration ramps linearly between min and ideal", () => {
  const cfg = DEFAULT_CONFIG; // min 300, ideal 1000
  const mid = (300 + 1000) / 2; // 650 ⇒ 0.5
  const r = _factors.scoreCapOpenDuration(
    new Map([[DOSE_STAGE.CAP_OPEN, { payload: { duration_ms: mid } }]]),
    cfg
  );
  assert.strictEqual(r.score, 0.5);
});

// ----------------------------------------------------------------------------
// Timing plausibility penalty
// ----------------------------------------------------------------------------

test("implausible timing (weigh-before after weigh-after) is detected and lowers the factor", () => {
  const clean = scoreDoseEventConfidence(doseEvent());
  const r = scoreDoseEventConfidence(doseEvent({ weighBeforeTs: 1013, weighAfterTs: 1012 }));
  assert.strictEqual(r.factors.timingPlausibility.detail.plausible, false);
  assert.match(r.factors.timingPlausibility.detail.issues[0], /weigh-before/);
  // A single anomaly halves the timing sub-score, dragging confidence down.
  assert.ok(r.factors.timingPlausibility.score < clean.factors.timingPlausibility.score);
  assert.ok(r.confidence < clean.confidence);
});

test("two timing anomalies push timing into the penalizing list (score < 0.5)", () => {
  const r = scoreDoseEventConfidence(
    doseEvent({ weighBeforeTs: 1013, weighAfterTs: 1012, capCloseMs: -50 })
  );
  assert.ok(r.factors.timingPlausibility.score < 0.5);
  assert.ok(r.penalizing.includes("timingPlausibility"));
});

test("negative reported duration is an implausible-timing penalty", () => {
  const r = scoreDoseEventConfidence(doseEvent({ capCloseMs: -50 }));
  assert.ok(r.factors.timingPlausibility.detail.issues.some((i) => /negative/.test(i)));
  assert.ok(r.factors.timingPlausibility.score < 1);
});

test("stacked timing anomalies compound the penalty", () => {
  const one = scoreDoseEventConfidence(doseEvent({ capCloseMs: -50 }));
  const two = scoreDoseEventConfidence(
    doseEvent({ capCloseMs: -50, weighBeforeTs: 1013, weighAfterTs: 1012 })
  );
  assert.ok(two.factors.timingPlausibility.score < one.factors.timingPlausibility.score);
});

// ----------------------------------------------------------------------------
// Sequence completeness
// ----------------------------------------------------------------------------

test("missing a required backbone stage drops the sequence factor and lists it", () => {
  const stages = normalizedStages().filter((s) => s.type !== DOSE_STAGE.SYNC);
  const r = scoreDoseEventConfidence({ stages });
  assert.strictEqual(r.factors.sequenceCompleteness.detail.complete, false);
  assert.deepStrictEqual(r.factors.sequenceCompleteness.detail.missing_stages, [DOSE_STAGE.SYNC]);
  assert.ok(r.penalizing.includes("sequenceCompleteness"));
});

test("complete-but-out-of-order stages score the sequence factor at 0.5", () => {
  // Reassign orders so ordinals walk backwards (CAP_OPEN before UNLOCK).
  const stages = normalizedStages();
  const unlock = stages.find((s) => s.type === DOSE_STAGE.UNLOCK);
  const capOpen = stages.find((s) => s.type === DOSE_STAGE.CAP_OPEN);
  const tmp = unlock.order;
  unlock.order = capOpen.order;
  capOpen.order = tmp;
  const r = _factors.scoreSequenceCompleteness(stages, new Map(stages.map((s) => [s.type, s])));
  assert.strictEqual(r.detail.complete, true);
  assert.strictEqual(r.detail.ordered, false);
  assert.strictEqual(r.score, 0.5);
});

// ----------------------------------------------------------------------------
// Banding thresholds
// ----------------------------------------------------------------------------

test("banding thresholds: bandFor honors the inclusive lower bounds", () => {
  assert.strictEqual(bandFor(0.8, DEFAULT_CONFIG), "high");
  assert.strictEqual(bandFor(0.7999, DEFAULT_CONFIG), "medium");
  assert.strictEqual(bandFor(0.5, DEFAULT_CONFIG), "medium");
  assert.strictEqual(bandFor(0.4999, DEFAULT_CONFIG), "low");
  assert.strictEqual(bandFor(0, DEFAULT_CONFIG), "low");
});

test("config is overridable (custom expected pill mass changes the weight factor)", () => {
  // With a 500 mg expected pill, a 250 mg removal is now a 250 mg error == tol ⇒ 0.
  const r = scoreDoseEventConfidence(doseEvent(), { expected_pill_mass_mg: 500 });
  assert.strictEqual(r.factors.weightDelta.score, 0);
  assert.strictEqual(r.factors.weightDelta.detail.expected_mass_mg, 500);
});

test("config overridable: dispensed_pill_count scales expected mass", () => {
  // 2 pills × 250 = 500 expected; a 500 mg removal is a perfect match.
  const r = scoreDoseEventConfidence(
    doseEvent({ deltaMg: -500, weighAfter: 4500 }),
    { dispensed_pill_count: 2 }
  );
  assert.strictEqual(r.factors.weightDelta.detail.expected_mass_mg, 500);
  assert.strictEqual(r.factors.weightDelta.score, 1);
});

// ----------------------------------------------------------------------------
// Determinism + breakdown shape
// ----------------------------------------------------------------------------

test("deterministic: same input yields an identical score + breakdown", () => {
  const a = scoreDoseEventConfidence(doseEvent({ capOpenMs: 700, deltaMg: -180, weighAfter: 4820 }));
  const b = scoreDoseEventConfidence(doseEvent({ capOpenMs: 700, deltaMg: -180, weighAfter: 4820 }));
  assert.deepStrictEqual(a, b);
});

test("factor breakdown is fully asserted: every factor has score/weight/detail", () => {
  const r = scoreDoseEventConfidence(doseEvent());
  const expectedFactors = ["weightDelta", "capOpenDuration", "sequenceCompleteness", "timingPlausibility"];
  assert.deepStrictEqual(Object.keys(r.factors).sort(), expectedFactors.slice().sort());
  for (const name of expectedFactors) {
    const f = r.factors[name];
    assert.ok(typeof f.score === "number" && f.score >= 0 && f.score <= 1, `${name}.score`);
    assert.strictEqual(f.weight, DEFAULT_CONFIG.weights[name]);
    assert.ok(f.detail && typeof f.detail === "object", `${name}.detail`);
  }
  assert.ok(Array.isArray(r.contributing));
  assert.ok(Array.isArray(r.penalizing));
});

test("final score is the weight-normalized mean of the sub-scores", () => {
  const r = scoreDoseEventConfidence(doseEvent({ capOpenMs: 100 })); // capOpen ⇒ 0
  const w = DEFAULT_CONFIG.weights;
  const expected =
    (1 * w.weightDelta + 0 * w.capOpenDuration + 1 * w.sequenceCompleteness + 1 * w.timingPlausibility) /
    (w.weightDelta + w.capOpenDuration + w.sequenceCompleteness + w.timingPlausibility);
  assert.ok(Math.abs(r.confidence - expected) < 1e-9, `${r.confidence} vs ${expected}`);
});

test("no weight signal at all ⇒ weight factor 0 with explanatory reason", () => {
  const stages = normalizedStages()
    .filter((s) => s.type !== DOSE_STAGE.WEIGHT_DELTA && s.type !== DOSE_STAGE.WEIGH_BEFORE && s.type !== DOSE_STAGE.WEIGH_AFTER);
  const r = scoreDoseEventConfidence({ stages });
  assert.strictEqual(r.factors.weightDelta.score, 0);
  assert.match(r.factors.weightDelta.detail.reason, /no weight signal/);
});

test("empty / missing stages produce a low score without throwing", () => {
  const r = scoreDoseEventConfidence({ stages: [] });
  assert.strictEqual(r.confidenceLevel, "low");
  assert.ok(r.confidence >= 0 && r.confidence <= 1);
  const r2 = scoreDoseEventConfidence({});
  assert.ok(r2.confidence >= 0 && r2.confidence <= 1);
});
