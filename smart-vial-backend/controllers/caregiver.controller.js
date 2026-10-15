const { randomUUID } = require('node:crypto');
const Device = require('../models/Device');
const Event = require('../models/Event');
const { canonicalUserExists } = require('../middleware/verifyUserToken');
const { identifier, bodyFields, dateRange } = require('../lib/validation');
const { handler, ApiError } = require('../lib/errors');
const { publicDevice, ownerId } = require('./app.api.controller');

function accessFilter(userId) {
  return {
    claimed: true, isActive: true, 'caregiver_grant.user_id': userId,
    'caregiver_grant.scope': 'observations:read', 'caregiver_grant.accepted_at': { $type: 'date' },
    ownership_epoch: { $type: 'string' },
    $expr: { $eq: ['$caregiver_grant.ownership_epoch', '$ownership_epoch'] },
  };
}
function eventScope(device) {
  return { device_id: device.device_id, ownership_epoch: device.ownership_epoch, owner_id: device.user_id };
}
function createCaregiverController({ devices = Device, events = Event, users = { exists: canonicalUserExists }, now = () => new Date(), uuid = randomUUID } = {}) {
  const claimDeviceForCaregiver = handler(async (req, res) => {
    const user_id = ownerId(req);
    bodyFields(req.body, ['device_id', 'caregiver_id']);
    const device_id = identifier(req.body.device_id, 'device_id');
    const caregiver_id = identifier(req.body.caregiver_id, 'caregiver_id');
    if (caregiver_id === user_id) throw new ApiError(400, 'invalid_recipient', 'Choose a different registered recipient');
    const device = await devices.findOne({ device_id, user_id, claimed: true, isActive: true, ownership_epoch: { $type: 'string' } });
    if (!device) throw new ApiError(404, 'device_unavailable', 'Device not found');
    if (!await users.exists({ user_id: caregiver_id })) throw new ApiError(400, 'invalid_recipient', 'A registered recipient is required');
    const invitation = { id: uuid(), user_id: caregiver_id, ownership_epoch: device.ownership_epoch, expires_at: new Date(+now() + 7 * 86400000) };
    const updated = await devices.findOneAndUpdate({ device_id, user_id, claimed: true, ownership_epoch: device.ownership_epoch }, {
      $set: { caregiver_invitation: invitation, caregiver_id: null }, $unset: { caregiver_grant: 1 },
    }, { new: true, writeConcern: { w: 'majority' } });
    if (!updated) throw new ApiError(409, 'ownership_changed', 'Device ownership changed');
    return res.status(202).json({ status: 'awaiting_acceptance', invitation: { id: invitation.id, expires_at: invitation.expires_at, scope: 'observations:read' } });
  });
  const acceptInvitation = handler(async (req, res) => {
    const user_id = ownerId(req);
    const invitation_id = identifier(req.params.invitation_id, 'invitation_id');
    const device = await devices.findOne({ claimed: true, isActive: true, 'caregiver_invitation.id': invitation_id, 'caregiver_invitation.user_id': user_id, 'caregiver_invitation.expires_at': { $gt: now() }, $expr: { $eq: ['$caregiver_invitation.ownership_epoch', '$ownership_epoch'] } });
    if (!device) throw new ApiError(404, 'invitation_unavailable', 'Invitation expired or unavailable');
    const result = await devices.findOneAndUpdate({ device_id: device.device_id, claimed: true, isActive: true, ownership_epoch: device.ownership_epoch, 'caregiver_invitation.id': invitation_id, 'caregiver_invitation.user_id': user_id, 'caregiver_invitation.expires_at': { $gt: now() } }, {
      $set: { caregiver_id: user_id, caregiver_grant: { user_id, ownership_epoch: device.ownership_epoch, scope: 'observations:read', accepted_at: now() } },
      $unset: { caregiver_invitation: 1 },
    }, { new: true, writeConcern: { w: 'majority' } });
    if (!result) throw new ApiError(409, 'invitation_changed', 'Invitation changed. Ask the owner to invite you again.');
    return res.json({ status: 'accepted', scope: 'observations:read', device_id: result.device_id });
  });
  async function authorizedDevice(req, deviceId) {
    const device = await devices.findOne({ ...accessFilter(ownerId(req)), device_id: identifier(deviceId, 'device_id') });
    if (!device) throw new ApiError(404, 'device_unavailable', 'Device not found or access unavailable');
    return device;
  }
  async function summary(device, limit) {
    const scope = eventScope(device);
    const recent_events = await events.find(scope).sort({ server_timestamp: -1 }).limit(limit);
    const total_events = await events.countDocuments(scope);
    return { device: publicDevice(device), recent_events, total_events };
  }
  const getCaregiver_A_device_summery = handler(async (req, res) => {
    const device = await authorizedDevice(req, req.params.device_id);
    return res.json(await summary(device, 50));
  });
  const getAllCaregiverDevices = handler(async (req, res) => {
    const result = await devices.find(accessFilter(ownerId(req))).limit(100);
    const summaries = await Promise.all(result.map(device => summary(device, 10)));
    return res.json({ devices: summaries, total_devices: result.length });
  });
  const searchDeviceById = handler(async (req, res) => {
    const device = await authorizedDevice(req, req.query.device_id);
    const result = await summary(device, 100);
    return res.json({ device: result.device, events: result.recent_events, total_events: result.total_events });
  });
  const filterEventsByDateRange = handler(async (req, res) => {
    const range = dateRange(req.query.start_date, req.query.end_date);
    const device = await authorizedDevice(req, req.query.device_id);
    const result = await events.find({ ...eventScope(device), server_timestamp: range }).sort({ server_timestamp: -1 }).limit(500);
    return res.json({ device_id: device.device_id, events: result, total_events: result.length, limit: 500 });
  });
  return { claimDeviceForCaregiver, acceptInvitation, getCaregiver_A_device_summery, getAllCaregiverDevices, searchDeviceById, filterEventsByDateRange };
}

module.exports = { ...createCaregiverController(), createCaregiverController, accessFilter, eventScope };
