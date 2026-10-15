const Device = require('../models/Device');
const { telemetry } = require('../lib/validation');
const { handler, ApiError } = require('../lib/errors');
const { persistObservation, deviceCredentialFilter } = require('../services/observationService');

const updateTelemetry = handler(async (req, res) => {
  const update = telemetry(req.body);
  const filter = deviceCredentialFilter(req.device_auth);
  if (filter.device_id !== req.body.device_id) throw new ApiError(403, 'device_mismatch', 'Device authorization does not match');
  const device = await Device.findOneAndUpdate(filter, { $set: { ...update, last_seen: new Date() } }, { new: true });
  if (!device) throw new ApiError(401, 'invalid_device_credentials', 'Device authentication required');
  return res.json({ status: 'updated' });
});

const ingestEvent = handler(async (req, res) => {
  const result = await persistObservation({ body: req.body, deviceId: req.body?.device_id, deviceAuth: req.device_auth });
  return res.json(result);
});

const ingestPhoneObservation = handler(async (req, res) => {
  const result = await persistObservation({ body: req.body, deviceId: req.params.device_id, userId: req.user_id });
  return res.json(result);
});

module.exports = { updateTelemetry, ingestEvent, ingestPhoneObservation };
