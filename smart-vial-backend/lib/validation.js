const { createHash, timingSafeEqual } = require('node:crypto');
const { ApiError } = require('./errors');

const EVENT_TYPES = Object.freeze([
  'OPEN', 'CLOSE', 'PILL_CHANGE', 'MANY_PILLS_CHANGE', 'OUTSIDE_WINDOW_CHANGE',
  'BLE_LOCK_CMD', 'BLE_UNLOCK_CMD', 'EMERGENCY_UNLOCK', 'SAFETY_TIMEOUT',
  'VIAL_RESTARTED', 'LOW_BATTERY_5', 'LOW_BATTERY_2',
]);

function invalid(message) { throw new ApiError(400, 'invalid_request', message); }
function identifier(value, name) {
  if (typeof value !== 'string' || !/^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/.test(value)) invalid(name + ' must be a bounded identifier');
  return value;
}
function bodyFields(body, allowed) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) invalid('A JSON object is required');
  if (Object.keys(body).some(key => !allowed.includes(key))) invalid('Unsupported request field');
}
function digest(value) { return createHash('sha256').update(value).digest('hex'); }
function safeDigestMatch(secret, expected) {
  if (typeof secret !== 'string' || secret.length < 32 || secret.length > 512 || typeof expected !== 'string' || !/^[a-f0-9]{64}$/.test(expected)) return false;
  return timingSafeEqual(Buffer.from(digest(secret), 'hex'), Buffer.from(expected, 'hex'));
}
function canonical(value) {
  if (Array.isArray(value)) return '[' + value.map(canonical).join(',') + ']';
  if (value && typeof value === 'object') return '{' + Object.keys(value).sort().map(key => JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}';
  return JSON.stringify(value);
}
function validatePayload(value, depth = 0) {
  if (depth > 4) invalid('Payload nesting exceeds the supported limit');
  if (value === null || typeof value === 'boolean') return;
  if (typeof value === 'string' && value.length <= 512) return;
  if (typeof value === 'number' && Number.isFinite(value)) return;
  if (Array.isArray(value)) {
    if (value.length > 32) invalid('Payload array exceeds the supported limit');
    value.forEach(item => validatePayload(item, depth + 1));
    return;
  }
  if (value && typeof value === 'object') {
    if (Object.keys(value).length > 32) invalid('Payload exceeds the supported limit');
    for (const [key, item] of Object.entries(value)) {
      if (!/^[a-zA-Z][a-zA-Z0-9_]{0,63}$/.test(key) || /(?:auth|token|secret|password|api_?key|credential)/i.test(key)) invalid('Unsupported payload key');
      validatePayload(item, depth + 1);
    }
    return;
  }
  invalid('Unsupported payload value');
}
function observation(body, deviceId, now = Date.now()) {
  bodyFields(body, ['device_id', 'event_id', 'ownership_epoch', 'boot_id', 'sequence', 'event', 'timestamp', 'payload']);
  identifier(deviceId, 'device_id');
  if (body.device_id !== undefined && body.device_id !== deviceId) invalid('device_id does not match the authorized device');
  const event_id = identifier(body.event_id, 'event_id');
  const ownership_epoch = identifier(body.ownership_epoch, 'ownership_epoch');
  const boot_id = identifier(body.boot_id, 'boot_id');
  if (!Number.isSafeInteger(body.sequence) || body.sequence < 0) invalid('sequence must be a nonnegative safe integer');
  if (!EVENT_TYPES.includes(body.event)) invalid('Unsupported event type');
  if (!Number.isSafeInteger(body.timestamp) || body.timestamp < 946684800 || body.timestamp > Math.floor(now / 1000) + 300) invalid('timestamp must be Unix seconds from a valid device clock');
  const payload = body.payload === undefined ? {} : body.payload;
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) invalid('payload must be an object');
  if (Buffer.byteLength(JSON.stringify(payload)) > 4096) invalid('Payload exceeds 4096 bytes');
  validatePayload(payload);
  const result = { device_id: deviceId, event_id, ownership_epoch, boot_id, sequence: body.sequence, event_type: body.event, device_timestamp: new Date(body.timestamp * 1000), payload };
  result.content_hash = digest(canonical({ ...result, device_timestamp: body.timestamp }));
  return result;
}
function telemetry(body) {
  bodyFields(body, ['device_id', 'battery', 'firmware_version']);
  identifier(body.device_id, 'device_id');
  if (body.battery === undefined && body.firmware_version === undefined) invalid('A telemetry value is required');
  const update = {};
  if (body.battery !== undefined) {
    if (!Number.isInteger(body.battery) || body.battery < 0 || body.battery > 100) invalid('battery must be an integer from 0 to 100');
    update.battery_percent = body.battery;
  }
  if (body.firmware_version !== undefined) {
    if (typeof body.firmware_version !== 'string' || !/^[A-Za-z0-9][A-Za-z0-9._+-]{0,63}$/.test(body.firmware_version)) invalid('Invalid firmware_version');
    update.firmware_version = body.firmware_version;
  }
  return update;
}
function dateRange(start, end) {
  if (typeof start !== 'string' || typeof end !== 'string' || start.length > 40 || end.length > 40) invalid('A start and end time are required');
  const from = new Date(start), to = new Date(end);
  if (!Number.isFinite(+from) || !Number.isFinite(+to) || from > to || to - from > 366 * 86400000) invalid('Invalid date range; use an ordered range of at most 366 days');
  return { $gte: from, $lte: to };
}

module.exports = { EVENT_TYPES, identifier, bodyFields, digest, safeDigestMatch, canonical, observation, telemetry, dateRange, invalid };
