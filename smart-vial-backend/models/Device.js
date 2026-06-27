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
    isActive: {
        type: Boolean,
        default: true,
        index: true
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