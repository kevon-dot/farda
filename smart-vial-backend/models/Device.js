const mongoose = require('mongoose');
const {
    generateDeviceSecret,
    encryptSecret,
    decryptSecret,
} = require('../utils/deviceCredentials');

// ============================================
// A3 — Per-device credential (encrypted-at-rest)
// ============================================
// Stores the AES-256-GCM ciphertext of the device's symmetric HMAC secret. The
// plaintext secret never lives in the database; see utils/deviceCredentials.js.
const DeviceCredentialSchema = new mongoose.Schema(
    {
        ciphertext: { type: String, required: true },
        iv: { type: String, required: true },
        tag: { type: String, required: true },
        // Version increments on every rotation (audit / debugging aid).
        version: { type: Number, default: 1 },
        issued_at: { type: Date, default: Date.now },
    },
    { _id: false }
);

// ============================================
// GTM-539 — Calibration record (registry metadata)
// ============================================
// Latest calibration applied to the device. `version` bumps each time a new
// calibration is recorded; `data` is an opaque, operator-supplied blob (e.g.
// sensor offsets) — deliberately Mixed so it isn't coupled to a sensor schema.
const CalibrationSchema = new mongoose.Schema(
    {
        version: { type: Number, default: 1 },
        data: { type: mongoose.Schema.Types.Mixed, default: {} },
        calibrated_at: { type: Date, default: Date.now },
        calibrated_by: { type: String, default: null },
    },
    { _id: false }
);

const DeviceSchema = new mongoose.Schema({
    // ============================================
    // Device Identification
    // ============================================
    device_id: {
        type: String,
        required: true,
        unique: true,
        trim: true,
        index: true
    },
    device_name: {
        type: String,
        default: 'Smart Vial Device',
        trim: true,
        required: true
    },
    // ============================================
    // Owner Information
    // ============================================
    user_id: {
        type: String,
        required: false,
        default: null
    },
    claimed: {
        type: Boolean,
        default: false,
        index: true
    },
    claimed_at: {
        type: Date,
        default: null
    },

    caregiver_id: {
        type: String,
        required: false,
        default: null
    },

    // ============================================
    // Device Status & Telemetry
    // ============================================
    battery_percent: {
        type: Number,
        min: 0,
        max: 100,
        default: 0
    },
    firmware_version: {
        type: String,
        default: '1.0.0'
    },
    // Last time this device's battery_percent / firmware_version was updated
    // from telemetry (#50). Distinct from last_seen (any contact) — this tracks
    // a successful telemetry sync and drives fleet-health staleness.
    battery_updated_at: {
        type: Date,
        default: null,
    },
    // Last time the device completed a successful data sync (telemetry OR event
    // ingestion). Fleet-health derives stale-sync from this. Updated on the
    // authenticated ingestion path.
    last_sync_at: {
        type: Date,
        default: null,
        index: true,
    },
    isActive: {
        type: Boolean,
        default: true,
        index: true
    },

    // ============================================
    // GTM-539 — Registry / OTA orchestration metadata
    // ============================================
    // Optional cohort label for staged rollouts (e.g. "beta", "us-east").
    cohort: {
        type: String,
        default: null,
        index: true,
    },
    // Explicit per-device OTA pin: when set, OTA resolution serves exactly this
    // release version (used for single-device staged rollout AND rollback to a
    // prior version). Null ⇒ device follows normal active/staged rollout.
    pinned_release_version: {
        type: String,
        default: null,
    },
    // Latest calibration record + version (registry metadata).
    calibration: {
        type: CalibrationSchema,
        default: null,
    },

    // ============================================
    // A3 — Per-device authentication credential + replay state
    // ============================================
    // Encrypted symmetric secret. `select: false` so the ciphertext is never
    // returned by default queries; the ingestion path must explicitly select it.
    credential: {
        type: DeviceCredentialSchema,
        default: null,
        select: false,
    },
    // Revoked devices are rejected at ingestion even though the record remains
    // (so we keep history). Revoke clears the credential and sets this true.
    revoked: {
        type: Boolean,
        default: false,
        index: true,
    },
    revoked_at: {
        type: Date,
        default: null,
    },
    // Highest accepted per-device nonce/counter. Strictly monotonic: an event
    // is rejected unless its x-nonce is greater than this. Starts at -1 so the
    // very first event (nonce 0) is accepted.
    last_nonce: {
        type: Number,
        default: -1,
    },

    // ============================================
    // Timestamps
    // ============================================
    last_seen: {
        type: Date,
        default: Date.now,
        index: true
    },

}, { timestamps: true });

// ============================================
// Indexes
// ============================================
// Compound index for querying user's active devices
DeviceSchema.index({ user_id: 1, isActive: 1 });

// ============================================
// Instance Methods
// ============================================
// Check if device is online (seen in last 5 minutes)
DeviceSchema.methods.isOnline = function() {
    const fiveMinutesAgo = new Date(Date.now() - 5 * 60 * 1000);
    return this.last_seen >= fiveMinutesAgo;
};

// ============================================
// GTM-539 — Registry serialization (admin-facing, PHI-safe)
// ============================================
// Returns the full device registry record for admin endpoints. Deliberately
// exposes only the device↔user BINDING ids (user_id / caregiver_id) and device
// operational state — NEVER the encrypted credential, and no patient PHI beyond
// those binding ids. The `credential` field is `select:false` so it isn't even
// present here unless explicitly selected; we never include it regardless.
DeviceSchema.methods.toRegistry = function() {
    return {
        device_id: this.device_id,
        device_name: this.device_name,
        // Binding ids only (no patient PHI).
        user_id: this.user_id || null,
        caregiver_id: this.caregiver_id || null,
        claimed: this.claimed === true,
        claimed_at: this.claimed_at || null,
        isActive: this.isActive !== false,
        revoked: this.revoked === true,
        revoked_at: this.revoked_at || null,
        // Credential metadata only — never the secret/ciphertext.
        credential_version:
            this.credential && this.credential.version ? this.credential.version : null,
        credential_issued_at:
            this.credential && this.credential.issued_at ? this.credential.issued_at : null,
        battery_percent: this.battery_percent,
        battery_updated_at: this.battery_updated_at || null,
        firmware_version: this.firmware_version,
        cohort: this.cohort || null,
        pinned_release_version: this.pinned_release_version || null,
        calibration: this.calibration
            ? {
                  version: this.calibration.version,
                  data: this.calibration.data,
                  calibrated_at: this.calibration.calibrated_at,
                  calibrated_by: this.calibration.calibrated_by || null,
              }
            : null,
        last_seen: this.last_seen || null,
        last_sync_at: this.last_sync_at || null,
        is_online: this.isOnline(),
        created_at: this.createdAt,
        updated_at: this.updatedAt,
    };
};

// ============================================
// A3 — Credential lifecycle (issue / rotate / revoke)
// ============================================

/**
 * Issue a brand-new secret for this device (provisioning OR rotation) and
 * persist only its ciphertext. Returns the PLAINTEXT secret so it can be handed
 * to the device exactly once — it is never recoverable in plaintext afterwards
 * except by decrypting with the server master key during verification.
 *
 * Clears `revoked` and resets `last_nonce` (a fresh secret means the device's
 * counter restarts; the old nonce history no longer applies).
 *
 * Does NOT call save(); the caller persists.
 *
 * @returns {string} the plaintext hex secret to deliver to the device
 */
DeviceSchema.methods.issueCredential = function() {
    const secret = generateDeviceSecret();
    const enc = encryptSecret(secret);
    const previousVersion = this.credential && this.credential.version ? this.credential.version : 0;
    this.credential = {
        ciphertext: enc.ciphertext,
        iv: enc.iv,
        tag: enc.tag,
        version: previousVersion + 1,
        issued_at: new Date(),
    };
    this.revoked = false;
    this.revoked_at = null;
    this.last_nonce = -1;
    return secret;
};

// Rotate is just a re-issue with clearer intent at call sites.
DeviceSchema.methods.rotateCredential = function() {
    return this.issueCredential();
};

/**
 * Revoke this device's credential. The device can no longer authenticate until
 * a new credential is issued. Does NOT call save(); the caller persists.
 */
DeviceSchema.methods.revokeCredential = function() {
    this.credential = null;
    this.revoked = true;
    this.revoked_at = new Date();
};

/**
 * Decrypt and return the plaintext secret for signature verification. Requires
 * the document to have been queried WITH the credential selected
 * (`.select('+credential')`). Returns null if the device has no credential.
 *
 * @returns {string|null}
 */
DeviceSchema.methods.getSecret = function() {
    if (!this.credential || !this.credential.ciphertext) return null;
    return decryptSecret(this.credential);
};

module.exports = mongoose.model('Device', DeviceSchema);