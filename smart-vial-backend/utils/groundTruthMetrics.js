// ============================================
// GTM-521 — Ground-truth validation metrics (sensitivity / specificity)
// ============================================
// Turns a supervised LABEL SOURCE (EMA self-report and/or manual pill-count) into
// the buyer-facing accuracy of our dose DETECTION: how often the device's
// "we think a dose was taken" signal agrees with what actually happened.
//
// The label is the ground TRUTH; the device-detected dose event is the
// PREDICTION. Crossing them gives the standard binary-classifier confusion
// matrix and its derived rates:
//
//                         GROUND TRUTH (EMA / pill-count)
//                         taken ("yes")        not taken ("no")
//   DETECTED   yes        TP                   FP
//   (device)   no         FN                   TN
//
//   sensitivity (recall, TPR) = TP / (TP + FN)   — of real doses, how many we caught
//   specificity (TNR)         = TN / (TN + FP)   — of non-doses, how many we ruled out
//   PPV (precision)           = TP / (TP + FP)   — of our "taken" calls, how many were right
//   NPV                       = TN / (TN + FN)   — of our "not taken" calls, how many were right
//
// Pure + deterministic: this module is a pure function of a list of already-
// resolved confusion samples (or a confusion-count object). No DB, no clock, no
// randomness, so it is fully unit-testable and a read endpoint can call it inline.
//
// PHI-free: it reads only the two booleans per sample (detected? / self-reported
// taken?) plus an opaque correlation id for traceability. It never reads or emits
// a medication, name, or condition.
//
// Degenerate inputs are handled explicitly: a rate whose denominator is 0 is
// reported as `null` (UNDEFINED), never NaN and never a silent 0 — "we have no
// positives to recall" is a different statement from "we recalled 0% of them".

// Self-report label values an EMA / pill-count resolves to. "unsure" is a real
// EMA answer but is NOT usable ground truth, so it is excluded from the matrix
// (counted separately as `unusable`) rather than guessed either way.
const GROUND_TRUTH = Object.freeze({
  TAKEN: "taken",
  NOT_TAKEN: "not_taken",
  UNSURE: "unsure",
});

// ---------------------------------------------------------------------------
// Normalize one raw self-report answer to a GROUND_TRUTH value (or null when it
// is not usable as a label). Accepts the EMA enum, common yes/no spellings, and
// booleans so the same helper serves the EMA endpoint and the metrics math.
// ---------------------------------------------------------------------------
function normalizeSelfReport(value) {
  if (value === true) return GROUND_TRUTH.TAKEN;
  if (value === false) return GROUND_TRUTH.NOT_TAKEN;
  if (typeof value !== "string") return null;
  const v = value.trim().toLowerCase();
  if (v === "taken" || v === "yes" || v === "y") return GROUND_TRUTH.TAKEN;
  if (v === "not_taken" || v === "no" || v === "n" || v === "not taken") {
    return GROUND_TRUTH.NOT_TAKEN;
  }
  if (v === "unsure" || v === "maybe" || v === "unknown") return GROUND_TRUTH.UNSURE;
  return null;
}

// Safe division: returns `null` (UNDEFINED) when the denominator is 0 instead of
// NaN/Infinity, so callers can distinguish "undefined rate" from "rate of 0".
function rate(numerator, denominator, places = 4) {
  if (!denominator || denominator <= 0) return null;
  const f = 10 ** places;
  return Math.round((numerator / denominator) * f) / f;
}

// ---------------------------------------------------------------------------
// computeConfusion
//
// Reduce a list of resolved samples into the 2x2 confusion counts. Each sample
// is `{ detected: boolean, ground_truth: <self-report value> }` (plus an optional
// opaque id, ignored here). A sample whose ground truth is UNSURE / unresolvable
// is NOT a label — it is tallied under `unusable` and left out of the matrix.
//
//   detected=true,  truth=taken     -> TP (real dose we caught)
//   detected=true,  truth=not_taken -> FP (we flagged a dose that didn't happen)
//   detected=false, truth=taken     -> FN (real dose we MISSED)
//   detected=false, truth=not_taken -> TN (correctly saw nothing)
// ---------------------------------------------------------------------------
function computeConfusion(samples) {
  const counts = { tp: 0, fp: 0, fn: 0, tn: 0, unusable: 0 };
  if (!Array.isArray(samples)) return counts;

  for (const s of samples) {
    const truth = normalizeSelfReport(s && s.ground_truth);
    if (truth !== GROUND_TRUTH.TAKEN && truth !== GROUND_TRUTH.NOT_TAKEN) {
      counts.unusable += 1;
      continue;
    }
    const detected = (s && s.detected) === true;
    if (detected && truth === GROUND_TRUTH.TAKEN) counts.tp += 1;
    else if (detected && truth === GROUND_TRUTH.NOT_TAKEN) counts.fp += 1;
    else if (!detected && truth === GROUND_TRUTH.TAKEN) counts.fn += 1;
    else counts.tn += 1; // !detected && not_taken
  }
  return counts;
}

// ---------------------------------------------------------------------------
// computeGroundTruthMetrics
//
// Compute the full validation summary from EITHER a list of resolved samples
// (`computeGroundTruthMetrics([{ detected, ground_truth }, ...])`) OR a
// pre-tallied confusion object (`computeGroundTruthMetrics({ tp, fp, fn, tn })`).
// Returns counts + the four rates (sens/spec/PPV/NPV, each `null` when its
// denominator is 0) + the labelled `sampleSize` and overall `accuracy`.
// ---------------------------------------------------------------------------
function computeGroundTruthMetrics(input) {
  let counts;
  if (Array.isArray(input)) {
    counts = computeConfusion(input);
  } else if (input && typeof input === "object") {
    counts = {
      tp: Number(input.tp) || 0,
      fp: Number(input.fp) || 0,
      fn: Number(input.fn) || 0,
      tn: Number(input.tn) || 0,
      unusable: Number(input.unusable) || 0,
    };
  } else {
    counts = { tp: 0, fp: 0, fn: 0, tn: 0, unusable: 0 };
  }

  const { tp, fp, fn, tn, unusable } = counts;
  const sampleSize = tp + fp + fn + tn; // labelled (usable) samples only

  return {
    // The four headline rates. `null` ⇒ UNDEFINED (denominator was 0), never NaN.
    sensitivity: rate(tp, tp + fn), // TP / (TP + FN)
    specificity: rate(tn, tn + fp), // TN / (TN + FP)
    ppv: rate(tp, tp + fp), // TP / (TP + FP) — precision
    npv: rate(tn, tn + fn), // TN / (TN + FN)
    accuracy: rate(tp + tn, sampleSize), // (TP + TN) / N
    counts: { tp, fp, fn, tn },
    // Samples seen but not usable as a label (EMA "unsure" / unresolved).
    unusable,
    // Number of LABELLED samples the rates are computed over.
    sampleSize,
  };
}

// ---------------------------------------------------------------------------
// shouldSampleForEma
//
// Server-side sub-sampling decision: only a fraction of dose events should
// trigger an EMA prompt (asking on EVERY dose causes survey fatigue and degrades
// the label quality we depend on). The client MAY pass a hint, but the server
// owns the rate so it can never be gamed up to 100% by a chatty client.
//
// Deterministic when a stable `seed` (e.g. the dose_event_id / idempotency_key)
// is supplied: the same dose event always yields the same decision, so a retried
// prompt is consistent and the choice is reproducible in tests. Falls back to
// Math.random only when no seed is given.
//
// @param {number} rate  target fraction in [0,1] (e.g. 0.2 ⇒ ~1 in 5)
// @param {string} [seed] stable key to make the decision deterministic
// @returns {boolean} whether to prompt for this dose event
// ---------------------------------------------------------------------------
const DEFAULT_EMA_SAMPLE_RATE = 0.2;

function shouldSampleForEma(rate = DEFAULT_EMA_SAMPLE_RATE, seed) {
  const r = Number.isFinite(rate) ? Math.min(1, Math.max(0, rate)) : 0;
  if (r <= 0) return false;
  if (r >= 1) return true;
  let unit;
  if (typeof seed === "string" && seed.length > 0) {
    // Cheap, stable hash → [0,1) so the same seed maps to the same bucket.
    let h = 2166136261;
    for (let i = 0; i < seed.length; i += 1) {
      h ^= seed.charCodeAt(i);
      h = Math.imul(h, 16777619);
    }
    unit = ((h >>> 0) % 100000) / 100000;
  } else {
    unit = Math.random();
  }
  return unit < r;
}

module.exports = {
  GROUND_TRUTH,
  DEFAULT_EMA_SAMPLE_RATE,
  normalizeSelfReport,
  computeConfusion,
  computeGroundTruthMetrics,
  shouldSampleForEma,
};
