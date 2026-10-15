const Device = require('../models/Device');
const { safeDigestMatch, identifier } = require('../lib/validation');

function createDeviceAuth({ devices = Device } = {}) {
  return async (req, res, next) => {
    try {
      const deviceId = req.headers['x-device-id'];
      const credentialId = req.headers['x-credential-id'];
      const secret = req.headers['x-api-key'];
      try {
        identifier(deviceId, 'device_id');
        identifier(credentialId, 'credential_id');
      } catch { return res.status(401).json({ error: 'Device authentication required', code: 'invalid_device_credentials' }); }
      if (req.body?.device_id !== deviceId) return res.status(401).json({ error: 'Device authentication required', code: 'invalid_device_credentials' });
      const device = await devices.findOne({ device_id: deviceId, isActive: true, 'credential.id': credentialId, 'credential.revoked_at': null })
        .select('+credential.id +credential.hash +credential.version +credential.revoked_at');
      if (!device || !Number.isSafeInteger(device.credential?.version) || device.credential.version < 1 || !safeDigestMatch(secret, device.credential.hash)) {
        return res.status(401).json({ error: 'Device authentication required', code: 'invalid_device_credentials' });
      }
      req.device_auth = { device_id: device.device_id, credential_id: credentialId, credential_version: device.credential.version };
      return next();
    } catch {
      return res.status(503).json({ error: 'Device authentication temporarily unavailable', code: 'service_unavailable' });
    }
  };
}

module.exports = createDeviceAuth();
module.exports.createDeviceAuth = createDeviceAuth;
