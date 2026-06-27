const mongoose = require('mongoose');
const { GRANT_STATUS } = require('../utils/caregiverAuthorization');

// ============================================
// GTM-507 / two-sided consent — Patient↔caregiver relationship + consent record
// ============================================
// An explicit, two-sided consent link governing whether a caregiver may access
// a specific device's data. The device OWNER (patient) INVITES a caregiver,
// which creates a `pending` grant that authorizes NOTHING. The invited CAREGIVER
// must explicitly ACCEPT before any access is granted (`pending → accepted`);
// at that point `device.caregiver_id` is mirrored from this record. Either the
// owner or the caregiver may REVOKE (`* → revoked`, terminal).
//
// This record is the server-authoritative source of the relationship and its
// consent lifecycle; authorization for caregiver-scoped reads is decided from
// an ACCEPTED grant only, never from a client-supplied role. The actor/timestamp
// fields below are a lightweight consent audit (who did what, when) — they hold
// only opaque user ids, never PHI.
const CaregiverGrantSchema = new mongoose.Schema(
  {
    // The device the grant is scoped to.
    deviceId: {
      type: String,
      required: true,
      index: true,
    },
    // The patient / device owner who extended the invite (trusted server id).
    patientUserId: {
      type: String,
      required: true,
      index: true,
    },
    // The caregiver who was invited / granted access.
    caregiverUserId: {
      type: String,
      required: true,
      index: true,
    },
    status: {
      type: String,
      enum: Object.values(GRANT_STATUS),
      // Two-sided consent: a new relationship starts as a pending invite that
      // grants nothing until the caregiver accepts.
      default: GRANT_STATUS.PENDING,
      index: true,
    },
    // ------------------------------------------------------------------
    // Consent audit — who did what, and when. Opaque user ids only; no PHI.
    // ------------------------------------------------------------------
    // When the owner extended the invite (the `pending` grant was created).
    invitedAt: {
      type: Date,
      default: Date.now,
    },
    // Who extended the invite (the owner/patient id).
    invitedBy: {
      type: String,
      default: null,
    },
    // When the caregiver accepted (pending → accepted). Null while pending.
    acceptedAt: {
      type: Date,
      default: null,
    },
    // Who accepted (the caregiver id who consented).
    acceptedBy: {
      type: String,
      default: null,
    },
    // Legacy/compat: set to the accept time so existing readers keep working.
    grantedAt: {
      type: Date,
      default: null,
    },
    // When access was revoked (* → revoked). Null until revoked.
    revokedAt: {
      type: Date,
      default: null,
    },
    // Who revoked (owner or caregiver id).
    revokedBy: {
      type: String,
      default: null,
    },
  },
  { timestamps: true }
);

// One active grant per (device, caregiver) pair.
CaregiverGrantSchema.index(
  { deviceId: 1, caregiverUserId: 1 },
  { unique: true }
);

module.exports = mongoose.model('CaregiverGrant', CaregiverGrantSchema);
