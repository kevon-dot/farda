const mongoose = require('mongoose');

const DeviceSchema = new mongoose.Schema({
  device_id: { type: String, required: true, unique: true, trim: true },
  device_name: { type: String, default: 'Farda vial', trim: true, maxlength: 80 },
  user_id: { type: String, default: null, index: true },
  claimed: { type: Boolean, default: false },
  claimed_at: { type: Date, default: null },
  ownership_epoch: { type: String, default: null },
  // No public API writes credential or claim_grant. Trusted provisioning must follow
  // verified vendor possession + key delivery. Existing IDs alone are insufficient.
  credential: {
    id: { type: String, select: false },
    hash: { type: String, select: false },
    version: { type: Number, default: 0, select: false },
    revoked_at: { type: Date, default: null, select: false },
  },
  claim_grant: {
    method: { type: String, select: false },
    user_id: { type: String, select: false },
    token_hash: { type: String, select: false },
    expires_at: { type: Date, select: false },
    credential_version: { type: Number, select: false },
  },
  caregiver_id: { type: String, default: null },
  caregiver_invitation: {
    id: String, user_id: String, ownership_epoch: String, expires_at: Date,
  },
  caregiver_grant: {
    user_id: String, ownership_epoch: String, scope: String, accepted_at: Date,
  },
  battery_percent: { type: Number, min: 0, max: 100, default: null },
  firmware_version: { type: String, default: null },
  isActive: { type: Boolean, default: true },
  last_seen: { type: Date, default: null },
  ingestion_revision: { type: Number, default: 0, select: false },
}, { timestamps: true, autoIndex: false });

DeviceSchema.index({ user_id: 1, isActive: 1 });
DeviceSchema.index({ 'caregiver_grant.user_id': 1, claimed: 1 });
DeviceSchema.methods.isOnline = function() {
  return this.last_seen != null && this.last_seen >= new Date(Date.now() - 5 * 60 * 1000);
};

module.exports = mongoose.model('Device', DeviceSchema);
