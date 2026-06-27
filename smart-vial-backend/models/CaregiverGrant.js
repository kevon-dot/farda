const mongoose = require('mongoose');
const { GRANT_STATUS } = require('../utils/caregiverAuthorization');

// ============================================
// GTM-507 — Patient↔caregiver relationship / consent record
// ============================================
// An explicit, owner-granted link authorizing a caregiver to access a specific
// device's data. The device OWNER (patient) is the only party that can create
// or revoke a grant (enforced in the controller via isDeviceOwner). This record
// is the server-authoritative source of the caregiver relationship and is kept
// in sync with `device.caregiver_id`; authorization for caregiver-scoped reads
// is decided from this trusted relationship, never from a client-supplied role.
const CaregiverGrantSchema = new mongoose.Schema(
  {
    // The device the grant is scoped to.
    deviceId: {
      type: String,
      required: true,
      index: true,
    },
    // The patient / device owner who granted access (trusted server-side id).
    patientUserId: {
      type: String,
      required: true,
      index: true,
    },
    // The caregiver who was granted access.
    caregiverUserId: {
      type: String,
      required: true,
      index: true,
    },
    status: {
      type: String,
      enum: Object.values(GRANT_STATUS),
      default: GRANT_STATUS.ACCEPTED,
      index: true,
    },
    grantedAt: {
      type: Date,
      default: Date.now,
    },
    revokedAt: {
      type: Date,
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
