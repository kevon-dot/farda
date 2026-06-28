const mongoose = require("mongoose");
const { GROUND_TRUTH } = require("../utils/groundTruthMetrics");

// ============================================
// GTM-521 — EMA self-report (ground-truth label source)
// ============================================
// An EmaResponse is one ecological-momentary-assessment self-report: the patient
// answering "Did you just take your dose?" (yes / no / unsure) close in time to a
// detected dose interaction. This is the SUPERVISED LABEL we validate the
// device's dose DETECTION against — crossing the self-report (ground truth) with
// the DoseEvent (prediction) yields dose-detection sensitivity/specificity
// (utils/groundTruthMetrics.js).
//
// PHI-free: subjects are referenced by id only (user_id / device_id, both
// server-derived from the session-owned device — never client-asserted). There is
// no medication, name, free text, or condition field anywhere here; the only
// payload is the constrained self-report enum + sampling metadata.
//
// Idempotent: a client-supplied `idempotency_key` (unique, sparse) lets a retried
// submission de-dupe to exactly one row, matching the dose-event ingest path.

const EmaResponseSchema = new mongoose.Schema(
  {
    // ----- Subject reference (ids only — never PHI) -----
    // The owning user (session id, server-derived). Lets a response be scoped /
    // purged per subject without ever storing a name.
    user_id: {
      type: String,
      required: true,
      index: true,
    },
    // The device the self-report concerns. Bound from the session-owned device by
    // the controller; the client cannot assert it.
    device_id: {
      type: String,
      required: true,
      index: true,
    },
    // Optional link to the specific detected DoseEvent this prompt followed. When
    // present, the metrics engine can pair this response to that exact detection;
    // when absent, it is matched by time window. Opaque id, not PHI.
    dose_event_id: {
      type: String,
      default: null,
      index: true,
    },

    // ----- The self-report (the ground-truth label) -----
    // Constrained enum — yes/no/unsure. "unsure" is a real answer but is NOT
    // usable ground truth (excluded from the confusion matrix by the metrics
    // engine), so we record it rather than forcing a guess.
    self_reported_taken: {
      type: String,
      required: true,
      enum: [GROUND_TRUTH.TAKEN, GROUND_TRUTH.NOT_TAKEN, GROUND_TRUTH.UNSURE],
    },

    // ----- Sampling metadata (PHI-free) -----
    // When the EMA prompt was shown and when it was answered. `prompted_at` is
    // set from sub-sampling; `responded_at` from the submission.
    prompted_at: {
      type: Date,
      default: null,
    },
    responded_at: {
      type: Date,
      default: Date.now,
      index: true,
    },
    // Opaque tag describing WHY this dose event was sampled for a prompt (e.g.
    // "subsample"), plus the sampling rate in effect. Numbers/codes only.
    sampling: {
      type: new mongoose.Schema(
        {
          reason: { type: String, default: null },
          rate: { type: Number, default: null },
        },
        { _id: false }
      ),
      default: () => ({}),
    },

    // ----- Idempotency -----
    idempotency_key: {
      type: String,
      unique: true,
      sparse: true,
      index: true,
    },
  },
  { timestamps: { createdAt: "createdAt", updatedAt: false } }
);

// Query a subject's recent EMA responses for the metrics window (ids only).
EmaResponseSchema.index({ user_id: 1, responded_at: -1 });
EmaResponseSchema.index({ device_id: 1, responded_at: -1 });

module.exports = mongoose.model("EmaResponse", EmaResponseSchema);
