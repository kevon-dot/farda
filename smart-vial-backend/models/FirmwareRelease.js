const mongoose = require("mongoose");
const { isValidSemver } = require("../utils/semver");
const { ROLLOUT_STATE } = require("../utils/otaResolution");

// ============================================
// GTM-539 — FirmwareRelease (OTA orchestration)
// ============================================
// A published (or draft) firmware build the fleet can be told to install.
//
// The backend ORCHESTRATES OTA but never signs or hosts the image bytes itself:
// it stores a REFERENCE (`image_url` — an HTTPS URL — plus an optional opaque
// `image_ref` and `image_sha256` digest). The device downloads over HTTPS and
// Secure Boot v2 verifies the image signature on-device (see firmware B4 /
// PROVISIONING.md). `min_version` is the orchestration-side anti-rollback gate
// that complements the firmware's secure-version eFuse.
//
// Staged/targeted rollout is expressed by `rollout_state` plus
// `target_device_ids` / `target_cohorts`; rollback is performed by pinning
// devices to a prior release (see Device.pinned_release_version) and/or moving
// a bad release to `rolled_back`.

const ROLLOUT_STATES = Object.values(ROLLOUT_STATE);

const FirmwareReleaseSchema = new mongoose.Schema(
  {
    // Human/semver version string, e.g. "1.4.2". Unique per release.
    version: {
      type: String,
      required: true,
      unique: true,
      trim: true,
      index: true,
      validate: {
        validator: isValidSemver,
        message: (props) => `${props.value} is not a valid MAJOR.MINOR.PATCH version`,
      },
    },

    // ---- Signed image reference (served to the device; verified on-device) ----
    // HTTPS URL the device fetches. Required and must be https:// to match the
    // firmware's refusal of non-HTTPS OTA (ESP_HTTPS_OTA_ALLOW_HTTP=n).
    image_url: {
      type: String,
      required: true,
      validate: {
        validator: (v) => typeof v === "string" && /^https:\/\//i.test(v),
        message: "image_url must be an https:// URL (firmware refuses non-HTTPS OTA)",
      },
    },
    // Optional opaque storage ref (e.g. S3 key / artifact id) for operators.
    image_ref: { type: String, default: null },
    // Optional content digest the device MAY cross-check.
    image_sha256: {
      type: String,
      default: null,
      validate: {
        validator: (v) => v == null || /^[0-9a-fA-F]{64}$/.test(v),
        message: "image_sha256 must be a 64-char hex digest",
      },
    },

    // ---- Anti-rollback / reachability -----------------------------------------
    // A device must already be at or above this version to be offered this
    // release directly (orchestration-side complement to the secure-version eFuse).
    min_version: {
      type: String,
      default: null,
      validate: {
        validator: (v) => v == null || isValidSemver(v),
        message: (props) => `${props.value} is not a valid MAJOR.MINOR.PATCH min_version`,
      },
    },

    // ---- Rollout control ------------------------------------------------------
    rollout_state: {
      type: String,
      enum: ROLLOUT_STATES,
      default: ROLLOUT_STATE.DRAFT,
      index: true,
    },
    // Targeted/staged rollout: explicit device ids and/or named cohorts. Only
    // consulted while rollout_state === 'staged'; 'active' reaches all devices.
    target_device_ids: { type: [String], default: [] },
    target_cohorts: { type: [String], default: [] },

    notes: { type: String, default: null },

    // Audit: which admin published/changed it last.
    created_by: { type: String, default: null },
    updated_by: { type: String, default: null },
  },
  { timestamps: true }
);

// PHI-free public serialization for admin API responses.
FirmwareReleaseSchema.methods.toPublic = function () {
  return {
    id: String(this._id),
    version: this.version,
    image_url: this.image_url,
    image_ref: this.image_ref || null,
    image_sha256: this.image_sha256 || null,
    min_version: this.min_version || null,
    rollout_state: this.rollout_state,
    target_device_ids: this.target_device_ids || [],
    target_cohorts: this.target_cohorts || [],
    notes: this.notes || null,
    created_by: this.created_by || null,
    updated_by: this.updated_by || null,
    created_at: this.createdAt,
    updated_at: this.updatedAt,
  };
};

module.exports = mongoose.model("FirmwareRelease", FirmwareReleaseSchema);
