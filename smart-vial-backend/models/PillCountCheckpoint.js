const mongoose = require("mongoose");

// ============================================
// GTM-521 — Pill-count checkpoint (ground-truth label source)
// ============================================
// A PillCountCheckpoint is a periodic, manual reconciliation: the patient (or a
// caregiver) physically counts the pills remaining and we compare that to the
// count the device INFERRED from its detected dose events. The signed
// discrepancy is a coarse, longitudinal ground-truth signal that complements the
// per-dose EMA self-report: if the device says 12 remain but 14 are physically
// present, two "detected" doses were over-counted (false positives); the reverse
// implies missed detections.
//
// PHI-free: ids only (user_id / device_id, server-derived from the session-owned
// device). The payload is two integer counts + a timestamp — no medication, name,
// or condition.
//
// Idempotent: a unique sparse `idempotency_key` de-dupes a retried submission to
// one row, matching the other GTM-521 / dose-event ingest paths.

const PillCountCheckpointSchema = new mongoose.Schema(
  {
    // ----- Subject reference (ids only — never PHI) -----
    user_id: {
      type: String,
      required: true,
      index: true,
    },
    device_id: {
      type: String,
      required: true,
      index: true,
    },

    // ----- The reconciliation -----
    // Pills physically counted by hand (the ground truth).
    manual_count: {
      type: Number,
      required: true,
      min: 0,
    },
    // Pills the device INFERRED remained, from its detected dose events (the
    // prediction being validated).
    device_inferred_count: {
      type: Number,
      required: true,
      min: 0,
    },
    // Signed discrepancy = manual - device_inferred. Stored (server-computed) so a
    // query can band drift without recomputing. Positive ⇒ device over-counted
    // doses (more pills physically present than it thinks) ⇒ false-positive
    // detections; negative ⇒ device under-counted ⇒ missed detections.
    discrepancy: {
      type: Number,
      default: 0,
    },

    // ----- When the count was taken -----
    checked_at: {
      type: Date,
      default: Date.now,
      index: true,
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

// Server-compute the signed discrepancy from the two counts so it can never drift
// from the inputs, regardless of caller.
PillCountCheckpointSchema.pre("validate", function () {
  const manual = Number(this.manual_count);
  const inferred = Number(this.device_inferred_count);
  if (Number.isFinite(manual) && Number.isFinite(inferred)) {
    this.discrepancy = manual - inferred;
  }
});

// Query a subject's recent checkpoints for the metrics/drift window (ids only).
PillCountCheckpointSchema.index({ user_id: 1, checked_at: -1 });
PillCountCheckpointSchema.index({ device_id: 1, checked_at: -1 });

module.exports = mongoose.model("PillCountCheckpoint", PillCountCheckpointSchema);
