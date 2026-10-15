const { randomUUID } = require('node:crypto');
const Device = require('../models/Device');
const Event = require('../models/Event');
const User = require('../models/User');
const { identifier, bodyFields, digest, safeDigestMatch, dateRange } = require('../lib/validation');
const { handler, ApiError } = require('../lib/errors');

function ownerId(req) {
  if (typeof req.user_id !== 'string' || !req.user_id) throw new ApiError(401, 'unauthorized', 'A valid session is required');
  return req.user_id;
}
function publicDevice(device) {
  return {
    device_id: device.device_id, device_name: device.device_name, user_id: device.user_id,
    claimed: device.claimed, claimed_at: device.claimed_at, ownership_epoch: device.ownership_epoch,
    battery_percent: device.battery_percent ?? null, firmware_version: device.firmware_version ?? null,
    isActive: device.isActive, last_seen: device.last_seen ?? null,
    is_online: device.last_seen != null && +new Date(device.last_seen) >= Date.now() - 300000,
    caregiver_id: device.caregiver_grant?.user_id ?? null,
  };
}
function claimResponse(res, device, alreadyOwned) {
  return res.json({ status: 'success', ownership_verified: true, already_owned: alreadyOwned, device: publicDevice(device) });
}

function createAppController({ devices = Device, events = Event, users = User, now = () => new Date(), uuid = randomUUID } = {}) {
  const saveUser = handler(async (req, res) => {
    const user_id = ownerId(req);
    const user = await users.findOneAndUpdate({ user_id }, {
      $set: { lastLogin: now() },
      $setOnInsert: { user_roles: ['user'], createdAt: now() },
    }, { upsert: true, new: true });
    return res.json({ status: 'success', user: { user_id: user.user_id, createdAt: user.createdAt, lastLogin: user.lastLogin } });
  });

  const claimDevice = handler(async (req, res) => {
    const user_id = ownerId(req);
    bodyFields(req.body, ['device_id', 'claim_token']);
    const device_id = identifier(req.body.device_id, 'device_id');
    const selection = '+claim_grant.method +claim_grant.user_id +claim_grant.token_hash +claim_grant.expires_at +claim_grant.credential_version +credential.id +credential.hash +credential.version +credential.revoked_at';
    const device = await devices.findOne({ device_id, isActive: true }).select(selection);
    if (!device) throw new ApiError(404, 'device_unavailable', 'Device is unavailable for enrollment');
    if (device.claimed || device.user_id) {
      if (device.user_id === user_id && device.claimed && device.ownership_epoch) return claimResponse(res, device, true);
      if (device.user_id === user_id) throw new ApiError(503, 'ownership_verification_required', 'This device needs verified ownership migration');
      throw new ApiError(409, 'device_already_claimed', 'Device is already claimed');
    }
    const grant = device.claim_grant;
    if (grant?.method !== 'vendor-possession-v1' || !grant.token_hash || !device.credential?.hash || !device.credential?.id || !Number.isSafeInteger(device.credential.version) || device.credential.version < 1 || device.credential.revoked_at) {
      throw new ApiError(503, 'claim_verification_unavailable', 'Verified hardware enrollment is not available for this device yet');
    }
    const when = now();
    if (grant.user_id !== user_id || !Number.isFinite(+new Date(grant.expires_at)) || +new Date(grant.expires_at) <= +when || grant.credential_version !== device.credential.version || !safeDigestMatch(req.body.claim_token, grant.token_hash)) {
      throw new ApiError(403, 'invalid_claim_proof', 'A current possession verification is required');
    }
    // Consume the user-bound proof and establish ownership in one conditional write.
    // Device is the authority; legacy User.claim_device_ids is not an access list.
    const claimed = await devices.findOneAndUpdate({
      device_id, isActive: true, claimed: false, user_id: null,
      'claim_grant.method': 'vendor-possession-v1', 'claim_grant.user_id': user_id,
      'claim_grant.token_hash': digest(req.body.claim_token), 'claim_grant.expires_at': { $gt: when },
      'claim_grant.credential_version': device.credential.version,
      'credential.version': device.credential.version, 'credential.id': device.credential.id,
      'credential.revoked_at': null,
    }, {
      $set: { user_id, claimed: true, claimed_at: when, ownership_epoch: uuid(), caregiver_id: null },
      $unset: { claim_grant: 1, caregiver_grant: 1, caregiver_invitation: 1 },
      $inc: { ingestion_revision: 1 },
    }, { new: true, writeConcern: { w: 'majority' } });
    if (claimed) return claimResponse(res, claimed, false);
    const winner = await devices.findOne({ device_id, isActive: true });
    if (winner?.claimed && winner.user_id === user_id && winner.ownership_epoch) return claimResponse(res, winner, true);
    throw new ApiError(409, 'claim_changed', 'Device ownership or verification changed. Start enrollment again.');
  });

  const getUserDevices = handler(async (req, res) => {
    const result = await devices.find({ user_id: ownerId(req), claimed: true, isActive: true }).limit(100);
    return res.json(result.map(publicDevice));
  });
  const getADeviceEvents = handler(async (req, res) => {
    const device_id = identifier(req.params.device_id, 'device_id');
    // Observation-time owner survives transfer; the new owner cannot read old epochs.
    const result = await events.find({ device_id, owner_id: ownerId(req) }).sort({ server_timestamp: -1 }).limit(100);
    return res.json(result);
  });
  const getAllDevicesEvents = handler(async (req, res) => {
    const result = await events.find({ owner_id: ownerId(req) }).sort({ server_timestamp: -1 }).limit(500);
    return res.json(result);
  });
  const searchDeviceEventsByTimeRange = handler(async (req, res) => {
    const device_id = identifier(req.params.device_id, 'device_id');
    const range = dateRange(req.query.start_time, req.query.end_time);
    const result = await events.find({ device_id, owner_id: ownerId(req), server_timestamp: range }).sort({ server_timestamp: -1 }).limit(500);
    return res.json(result);
  });
  const removeClaimedDevice = handler(async (req, res) => {
    const device_id = identifier(req.params.device_id, 'device_id');
    const device = await devices.findOneAndUpdate({ device_id, user_id: ownerId(req), claimed: true }, {
      $set: { user_id: null, claimed: false, claimed_at: null, ownership_epoch: uuid(), caregiver_id: null, 'credential.revoked_at': now() },
      $unset: { caregiver_grant: 1, caregiver_invitation: 1, claim_grant: 1, 'credential.hash': 1 },
      $inc: { 'credential.version': 1, ingestion_revision: 1 },
    }, { new: true, writeConcern: { w: 'majority' } });
    if (!device) throw new ApiError(404, 'device_unavailable', 'Device not found');
    return res.json({ status: 'success', message: 'Device released. New enrollment requires verified provisioning.', credentials_revoked: true });
  });
  const deleteDeviceEvents = handler(async (req, res) => {
    ownerId(req);
    identifier(req.params.device_id, 'device_id');
    throw new ApiError(405, 'append_only_observations', 'Observation deletion is not supported by this route. Use the reviewed account-data process.');
  });
  const deleteCaregiverAccessToDevice = handler(async (req, res) => {
    const device_id = identifier(req.params.device_id, 'device_id');
    const device = await devices.findOneAndUpdate({ device_id, user_id: ownerId(req), claimed: true }, {
      $set: { caregiver_id: null }, $unset: { caregiver_grant: 1, caregiver_invitation: 1 },
    }, { new: true, writeConcern: { w: 'majority' } });
    if (!device) throw new ApiError(404, 'device_unavailable', 'Device not found');
    return res.json({ status: 'success', message: 'Caregiver access and pending invitation removed' });
  });
  return { saveUser, claimDevice, getUserDevices, getADeviceEvents, getAllDevicesEvents, searchDeviceEventsByTimeRange, removeClaimedDevice, deleteDeviceEvents, deleteCaregiverAccessToDevice };
}

module.exports = { ...createAppController(), createAppController, publicDevice, ownerId };
