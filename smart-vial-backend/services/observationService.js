const mongoose = require('mongoose');
const Device = require('../models/Device');
const Event = require('../models/Event');
const { observation } = require('../lib/validation');
const { ApiError } = require('../lib/errors');

const TRANSACTION_OPTIONS = { readConcern: { level: 'snapshot' }, writeConcern: { w: 'majority' }, readPreference: 'primary' };

function deviceCredentialFilter(auth) {
  if (!auth?.device_id || !auth.credential_id || !Number.isSafeInteger(auth.credential_version)) throw new ApiError(401, 'invalid_device_credentials', 'Device authentication required');
  return {
    device_id: auth.device_id, isActive: true,
    'credential.id': auth.credential_id, 'credential.version': auth.credential_version,
    'credential.revoked_at': null,
  };
}

function createObservationService({ devices = Device, events = Event, connection = mongoose.connection, now = () => new Date() } = {}) {
  return async function persistObservation({ body, deviceId, userId, deviceAuth }) {
    const received = now();
    const input = observation(body, deviceId, +received);
    if (!userId && !deviceAuth) throw new ApiError(401, 'unauthorized', 'Authentication required');
    const authFilter = deviceAuth ? deviceCredentialFilter(deviceAuth) : { device_id: deviceId, user_id: userId, isActive: true };
    if (authFilter.device_id !== deviceId) throw new ApiError(403, 'device_mismatch', 'Device authorization does not match');

    // A unique-index race aborts a transaction. Retry it in a new transaction so
    // that we can compare the winning record before reporting a durable duplicate.
    for (let attempt = 0; attempt < 3; attempt++) {
      try {
        return await connection.transaction(async session => {
          // This write serializes ingestion with unclaim/revoke on the SAME device.
          // A check followed only by an Event insert would allow a transfer race.
          const device = await devices.findOneAndUpdate({ ...authFilter, claimed: true, ownership_epoch: input.ownership_epoch },
            { $set: { last_seen: received }, $inc: { ingestion_revision: 1 } },
            { new: true, session });
          if (!device?.user_id || !device.claimed_at) throw new ApiError(409, 'ownership_changed', 'Current verified device ownership is required');
          if (input.device_timestamp < new Date(Math.floor(+new Date(device.claimed_at) / 1000) * 1000)) {
            throw new ApiError(400, 'timestamp_before_ownership', 'Observation predates this ownership period');
          }

          const scope = { device_id: deviceId, ownership_epoch: input.ownership_epoch, owner_id: device.user_id };
          const existing = await events.findOne({ ...scope, $or: [
            { event_id: input.event_id }, { boot_id: input.boot_id, sequence: input.sequence },
          ] }).select('+content_hash').session(session);
          if (existing && existing.content_hash !== input.content_hash) throw new ApiError(409, 'event_identity_conflict', 'This event identity was already used for different content');
          if (!existing) {
            await events.create([{
              ...input, owner_id: device.user_id, source: deviceAuth ? 'device_credential' : 'phone_ble',
              evidence_type: 'vial_observation', server_timestamp: received,
              time_drift_seconds: Math.floor((+received - +input.device_timestamp) / 1000),
            }], { session });
          }
          return {
            status: existing ? 'duplicate' : 'stored', evidence_type: 'vial_observation',
            receipt: {
              event_id: input.event_id, device_id: deviceId, ownership_epoch: input.ownership_epoch,
              boot_id: input.boot_id, sequence: input.sequence, committed: true,
            },
          };
        }, TRANSACTION_OPTIONS);
      } catch (error) {
        if (error.code !== 11000 || attempt === 2) throw error;
      }
    }
  };
}

module.exports = { persistObservation: createObservationService(), createObservationService, deviceCredentialFilter, TRANSACTION_OPTIONS };
