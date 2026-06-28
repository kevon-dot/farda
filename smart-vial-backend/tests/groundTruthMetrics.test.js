const test = require("node:test");
const assert = require("node:assert");

// ============================================
// GTM-521 — Ground-truth metrics unit tests
// ============================================
// Pure unit tests for the sensitivity/specificity engine. The module is a pure
// function of resolved confusion samples (or counts), so no DB is needed. We
// assert EXACT sens/spec/PPV/NPV for perfect, all-miss, and mixed matrices, plus
// the empty/degenerate (undefined-rate) behaviour and the sub-sample decision.

const {
  GROUND_TRUTH,
  normalizeSelfReport,
  computeConfusion,
  computeGroundTruthMetrics,
  shouldSampleForEma,
} = require("../utils/groundTruthMetrics");

// ---- normalizeSelfReport ---------------------------------------------------

test("normalizeSelfReport maps enum/yes/no/booleans, returns null for junk", () => {
  assert.strictEqual(normalizeSelfReport("taken"), GROUND_TRUTH.TAKEN);
  assert.strictEqual(normalizeSelfReport("YES"), GROUND_TRUTH.TAKEN);
  assert.strictEqual(normalizeSelfReport(true), GROUND_TRUTH.TAKEN);
  assert.strictEqual(normalizeSelfReport("not_taken"), GROUND_TRUTH.NOT_TAKEN);
  assert.strictEqual(normalizeSelfReport("no"), GROUND_TRUTH.NOT_TAKEN);
  assert.strictEqual(normalizeSelfReport(false), GROUND_TRUTH.NOT_TAKEN);
  assert.strictEqual(normalizeSelfReport("unsure"), GROUND_TRUTH.UNSURE);
  assert.strictEqual(normalizeSelfReport("banana"), null);
  assert.strictEqual(normalizeSelfReport(undefined), null);
});

// ---- Perfect detection: sens = spec = 1 ------------------------------------

test("perfect detection ⇒ sensitivity = specificity = PPV = NPV = accuracy = 1", () => {
  const samples = [
    { detected: true, ground_truth: "taken" }, // TP
    { detected: true, ground_truth: "taken" }, // TP
    { detected: false, ground_truth: "not_taken" }, // TN
    { detected: false, ground_truth: "not_taken" }, // TN
  ];
  const m = computeGroundTruthMetrics(samples);
  assert.strictEqual(m.sensitivity, 1);
  assert.strictEqual(m.specificity, 1);
  assert.strictEqual(m.ppv, 1);
  assert.strictEqual(m.npv, 1);
  assert.strictEqual(m.accuracy, 1);
  assert.deepStrictEqual(m.counts, { tp: 2, fp: 0, fn: 0, tn: 2 });
  assert.strictEqual(m.sampleSize, 4);
});

// ---- All-miss: detector never agrees ---------------------------------------

test("all-miss ⇒ sensitivity = 0 and specificity = 0", () => {
  const samples = [
    { detected: false, ground_truth: "taken" }, // FN
    { detected: false, ground_truth: "taken" }, // FN
    { detected: true, ground_truth: "not_taken" }, // FP
    { detected: true, ground_truth: "not_taken" }, // FP
  ];
  const m = computeGroundTruthMetrics(samples);
  assert.strictEqual(m.sensitivity, 0); // TP/(TP+FN) = 0/2
  assert.strictEqual(m.specificity, 0); // TN/(TN+FP) = 0/2
  assert.strictEqual(m.ppv, 0); // TP/(TP+FP) = 0/2
  assert.strictEqual(m.npv, 0); // TN/(TN+FN) = 0/2
  assert.strictEqual(m.accuracy, 0);
  assert.deepStrictEqual(m.counts, { tp: 0, fp: 2, fn: 2, tn: 0 });
});

// ---- Mixed TP/FP/FN/TN with EXACT asserted rates ---------------------------

test("mixed matrix ⇒ exact sens/spec/PPV/NPV", () => {
  // Construct TP=8, FN=2, TN=6, FP=4.
  //   sensitivity = 8/(8+2) = 0.8
  //   specificity = 6/(6+4) = 0.6
  //   ppv         = 8/(8+4) = 0.6667 (rounded 4dp)
  //   npv         = 6/(6+2) = 0.75
  //   accuracy    = (8+6)/20 = 0.7
  const samples = [];
  for (let i = 0; i < 8; i++) samples.push({ detected: true, ground_truth: "taken" }); // TP
  for (let i = 0; i < 2; i++) samples.push({ detected: false, ground_truth: "taken" }); // FN
  for (let i = 0; i < 6; i++) samples.push({ detected: false, ground_truth: "not_taken" }); // TN
  for (let i = 0; i < 4; i++) samples.push({ detected: true, ground_truth: "not_taken" }); // FP

  const m = computeGroundTruthMetrics(samples);
  assert.strictEqual(m.sensitivity, 0.8);
  assert.strictEqual(m.specificity, 0.6);
  assert.strictEqual(m.ppv, 0.6667);
  assert.strictEqual(m.npv, 0.75);
  assert.strictEqual(m.accuracy, 0.7);
  assert.deepStrictEqual(m.counts, { tp: 8, fp: 4, fn: 2, tn: 6 });
  assert.strictEqual(m.sampleSize, 20);
});

// ---- Confusion-count object input is equivalent to sample-list input -------

test("accepts a pre-tallied confusion-count object", () => {
  const m = computeGroundTruthMetrics({ tp: 8, fn: 2, tn: 6, fp: 4 });
  assert.strictEqual(m.sensitivity, 0.8);
  assert.strictEqual(m.specificity, 0.6);
  assert.strictEqual(m.sampleSize, 20);
});

// ---- "unsure" is excluded from the matrix (not guessed) --------------------

test("EMA 'unsure' answers are unusable, excluded from the confusion matrix", () => {
  const samples = [
    { detected: true, ground_truth: "taken" }, // TP
    { detected: false, ground_truth: "not_taken" }, // TN
    { detected: true, ground_truth: "unsure" }, // unusable
    { detected: false, ground_truth: "unsure" }, // unusable
    { detected: true, ground_truth: "banana" }, // unusable (junk)
  ];
  const m = computeGroundTruthMetrics(samples);
  assert.strictEqual(m.sensitivity, 1);
  assert.strictEqual(m.specificity, 1);
  assert.strictEqual(m.sampleSize, 2);
  assert.strictEqual(m.unusable, 3);
  assert.deepStrictEqual(m.counts, { tp: 1, fp: 0, fn: 0, tn: 1 });
});

// ---- Empty / degenerate ⇒ undefined (null) rates, never NaN ----------------

test("empty input ⇒ all rates null (undefined), sampleSize 0, no NaN", () => {
  const m = computeGroundTruthMetrics([]);
  assert.strictEqual(m.sensitivity, null);
  assert.strictEqual(m.specificity, null);
  assert.strictEqual(m.ppv, null);
  assert.strictEqual(m.npv, null);
  assert.strictEqual(m.accuracy, null);
  assert.strictEqual(m.sampleSize, 0);
  assert.deepStrictEqual(m.counts, { tp: 0, fp: 0, fn: 0, tn: 0 });
});

test("degenerate: only positives ⇒ specificity undefined (null), sensitivity defined", () => {
  // No actual negatives at all ⇒ TN+FP = 0 ⇒ specificity is UNDEFINED, not 0.
  const m = computeGroundTruthMetrics([
    { detected: true, ground_truth: "taken" }, // TP
    { detected: false, ground_truth: "taken" }, // FN
  ]);
  assert.strictEqual(m.sensitivity, 0.5);
  assert.strictEqual(m.specificity, null); // TN+FP = 0 ⇒ undefined
  assert.strictEqual(m.ppv, 1); // TP/(TP+FP) = 1/1
  assert.strictEqual(m.npv, 0); // TN/(TN+FN) = 0/1 (FN=1) ⇒ defined 0
});

test("non-array / nullish input is handled (all null)", () => {
  for (const bad of [null, undefined, 42, "x"]) {
    const m = computeGroundTruthMetrics(bad);
    assert.strictEqual(m.sensitivity, null);
    assert.strictEqual(m.sampleSize, 0);
  }
});

// ---- computeConfusion direct ----------------------------------------------

test("computeConfusion tallies the 2x2 matrix + unusable", () => {
  const c = computeConfusion([
    { detected: true, ground_truth: "yes" }, // TP
    { detected: true, ground_truth: "no" }, // FP
    { detected: false, ground_truth: "yes" }, // FN
    { detected: false, ground_truth: "no" }, // TN
    { detected: true, ground_truth: "unsure" }, // unusable
  ]);
  assert.deepStrictEqual(c, { tp: 1, fp: 1, fn: 1, tn: 1, unusable: 1 });
});

// ---- shouldSampleForEma (sub-sample decision) ------------------------------

test("shouldSampleForEma: rate 0 ⇒ never, rate 1 ⇒ always", () => {
  assert.strictEqual(shouldSampleForEma(0, "seed"), false);
  assert.strictEqual(shouldSampleForEma(1, "seed"), true);
  assert.strictEqual(shouldSampleForEma(-5, "seed"), false); // clamped
  assert.strictEqual(shouldSampleForEma(99, "seed"), true); // clamped
});

test("shouldSampleForEma is deterministic for a given seed", () => {
  const a = shouldSampleForEma(0.5, "dose-abc");
  const b = shouldSampleForEma(0.5, "dose-abc");
  assert.strictEqual(a, b);
});

test("shouldSampleForEma sub-samples roughly to the target rate over many seeds", () => {
  let hits = 0;
  const n = 2000;
  for (let i = 0; i < n; i++) {
    if (shouldSampleForEma(0.2, `dose-${i}`)) hits++;
  }
  const frac = hits / n;
  // Hash-bucketed, so it should land near 0.2 (generous band).
  assert.ok(frac > 0.1 && frac < 0.3, `expected ~0.2, got ${frac}`);
});
