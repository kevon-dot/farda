const mongoose = require("mongoose");
const {
  SCHEMA_VERSION,
  DOSE_STAGE_TYPES,
  validateDoseEventMicrostructure,
} = require("../utils/doseEventValidation");

// ============================================
// GTM-519 — Dose-event microstructure (server-authoritative)
// ============================================
// One DoseEvent document is the canonical, ORDERED, tokenization-ready record of
// a single dose interaction's full lifecycle: reminder microbehaviors → unlock →
// cap open → weigh-before / weigh-after / weight-delta → cap close → sync.
//
// Server-authoritative: the controller stamps `recordedAt` and the per-stage
// `order` is assigned by the validator from device timestamps — the client never
// dictates ordering. `device_id` is derived from the session-owned device, not
// asserted by the client body, so a record can never be written against a device
// the caller doesn't own.
//
// PHI-free: subjects are referenced by id only. There is no medication, name, or
// condition field anywhere in this schema; stage payloads are numbers/codes,
// enforced strict + scanned by the no-PHI guard before persistence.
//
// Tokenization-ready + versioned: each stage carries a stable `token` (TYPE@order)
// and the document stores the flat ordered `token_sequence`. `schema_version`
// pins the structure so a future tokenizer can migrate older records.

const DoseEventStageSchema = new mongoose.Schema(
  {
    type: {
      type: String,
      required: true,
      enum: DOSE_STAGE_TYPES,
    },
    // Server-assigned contiguous ordinal (0..N-1). NOT client-controlled.
    order: {
      type: Number,
      required: true,
    },
    // Device-reported unix seconds for this stage. Used only to derive ordering;
    // the canonical record time is the document's server-set `recordedAt`.
    device_timestamp: {
      type: Number,
      default: null,
    },
    // Numbers / enum codes only (PHI-free, validated upstream).
    payload: {
      type: mongoose.Schema.Types.Mixed,
      default: {},
    },
    // Stable per-stage token for downstream tokenization (TYPE@order).
    token: {
      type: String,
      required: true,
    },
  },
  { _id: false }
);

const DoseEventSchema = new mongoose.Schema(
  {
    // ============================================
    // Subject reference (by id only — never PHI)
    // ============================================
    // The device this dose interaction happened on. Bound from the session-owned
    // device by the controller; the client cannot assert it.
    device_id: {
      type: String,
      required: true,
      index: true,
    },
    // The owning user (session id, server-derived). Lets a record be scoped /
    // purged per subject without ever storing a name.
    user_id: {
      type: String,
      required: true,
      index: true,
    },
    // Opaque app-local correlation id for this dose (not PHI).
    client_dose_id: {
      type: String,
      required: true,
    },

    // ============================================
    // Idempotency
    // ============================================
    idempotency_key: {
      type: String,
      unique: true,
      sparse: true,
      index: true,
    },

    // ============================================
    // Tokenization-ready, versioned structure
    // ============================================
    schema_version: {
      type: Number,
      required: true,
      default: SCHEMA_VERSION,
    },
    stages: {
      type: [DoseEventStageSchema],
      required: true,
    },
    // Flat ordered token list a downstream model consumes directly.
    token_sequence: {
      type: [String],
      default: [],
    },

    // ============================================
    // Server-authoritative timestamp
    // ============================================
    // Canonical record time, stamped by the server on ingest. The device
    // timestamps live per-stage and are advisory (used only for ordering).
    recordedAt: {
      type: Date,
      default: Date.now,
      index: true,
    },
  },
  { timestamps: { createdAt: "createdAt", updatedAt: false } }
);

// Defense-in-depth: re-run the full microstructure validation at the model layer
// so no code path can persist an out-of-order / incomplete / PHI-bearing record,
// even if a caller bypasses the controller validator. We reconstruct the wire
// shape from the stored stages and re-validate.
DoseEventSchema.pre("validate", function () {
  if (!Array.isArray(this.stages) || this.stages.length === 0) {
    throw new Error("DoseEvent requires a non-empty ordered stages array");
  }
  const result = validateDoseEventMicrostructure({
    client_dose_id: this.client_dose_id,
    idempotency_key: this.idempotency_key,
    stages: this.stages.map((s) => ({
      type: s.type,
      timestamp: s.device_timestamp,
      payload: s.payload,
    })),
  });
  if (!result.ok) {
    throw new Error(`Invalid dose-event microstructure: ${result.error}`);
  }
  // Persist the server-normalized order/tokens (authoritative over any input).
  this.schema_version = result.value.schema_version;
  this.stages = result.value.stages;
  this.token_sequence = result.value.token_sequence;
});

// Query a subject's recent dose-event microstructures (PHI-free; ids only).
DoseEventSchema.index({ device_id: 1, recordedAt: -1 });
DoseEventSchema.index({ user_id: 1, recordedAt: -1 });

module.exports = mongoose.model("DoseEvent", DoseEventSchema);
