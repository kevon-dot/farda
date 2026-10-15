const test = require('node:test');
const assert = require('node:assert/strict');
const { readConfig, validateConfig } = require('../config/config');
const { observation, telemetry, digest, dateRange, safeDigestMatch } = require('../lib/validation');
const { createDeviceAuth } = require('../middleware/authDevice');
const { createVerifyToken, SESSION_QUERY } = require('../middleware/verifyUserToken');
const { createAppController } = require('../controllers/app.api.controller');
const { createCaregiverController } = require('../controllers/caregiver.controller');
const { createObservationService } = require('../services/observationService');
const { requestLimit } = require('../middleware/requestLimit');
const { response, query, fakeDevices, matches } = require('./helpers');

const when = new Date('2026-10-15T12:00:00Z');
const token = 'a'.repeat(48);
const input = { event_id: 'event-1', ownership_epoch: 'epoch-1', boot_id: 'boot-1', sequence: 0, event: 'PILL_CHANGE', timestamp: +when / 1000, payload: { chng: 1, cnt: 9 } };
const owned = (overrides = {}) => ({ device_id: 'vial-1', claimed: true, user_id: 'owner-1', ownership_epoch: 'epoch-1', claimed_at: new Date(+when - 60000), isActive: true, credential: { id: 'key-1', version: 1, hash: digest(token), revoked_at: null }, ...overrides });
const provisioned = (overrides = {}) => owned({ user_id: null, claimed: false, claimed_at: null, ownership_epoch: null, claim_grant: { method: 'vendor-possession-v1', user_id: 'owner-1', token_hash: digest(token), expires_at: new Date(+when + 60000), credential_version: 1 }, ...overrides });

test('missing config fails closed and old shared keys do not create a credential', () => {
  const config = readConfig({ DEVICE_API_KEY: 'old-fleet-key', JWT_SECRET: 'old-jwt' });
  assert.throws(() => validateConfig(config), /Missing required/);
  assert.equal(config.device, undefined);
  assert.equal(config.jwt, undefined);
  assert.doesNotThrow(() => validateConfig(readConfig({ MONGO_URI: 'mongodb://localhost/farda_test_unit', DATABASE_URL: 'postgres://localhost/test' })));
});
test('battery zero is retained and absent fields do not overwrite known values', () => {
  assert.deepEqual(telemetry({ device_id: 'vial-1', battery: 0 }), { battery_percent: 0 });
  assert.deepEqual(telemetry({ device_id: 'vial-1', firmware_version: '2.1.0' }), { firmware_version: '2.1.0' });
  for (const battery of [null, '', '0', -1, 101, 1.5, NaN]) assert.throws(() => telemetry({ device_id: 'vial-1', battery }));
});
test('event contract requires enum, full replay identity, valid clock and bounded payload', () => {
  assert.equal(observation(input, 'vial-1', +when).sequence, 0);
  for (const patch of [{ event_id: null }, { event_id: '' }, { ownership_epoch: undefined }, { boot_id: undefined }, { sequence: -1 }, { sequence: Number.MAX_SAFE_INTEGER + 1 }, { event: 'taken' }, { event: 'pill_change' }, { timestamp: null }, { timestamp: +when }, { timestamp: +when / 1000 + 301 }, { payload: { authKey: 'secret' } }, { payload: { big: 'x'.repeat(4097) } }, { owner_id: 'attacker' }]) {
    assert.throws(() => observation({ ...input, ...patch }, 'vial-1', +when), JSON.stringify(patch));
  }
  assert.throws(() => observation({ ...input, device_id: 'other' }, 'vial-1', +when));
});
test('canonical replay digest ignores object key order but preserves content', () => {
  assert.equal(observation(input, 'vial-1', +when).content_hash, observation({ ...input, payload: { cnt: 9, chng: 1 } }, 'vial-1', +when).content_hash);
  assert.notEqual(observation(input, 'vial-1', +when).content_hash, observation({ ...input, payload: { cnt: 8, chng: 1 } }, 'vial-1', +when).content_hash);
});
test('date queries reject reversed, invalid and unbounded ranges', () => {
  for (const dates of [['bad', 'bad'], ['2026-10-16', '2026-10-15'], ['2000-01-01', '2026-01-01']]) assert.throws(() => dateRange(...dates));
  assert.equal(+dateRange('2026-10-14', '2026-10-15').$lte, +new Date('2026-10-15'));
});
test('device auth binds the key to a provisioned identity and credential version', async () => {
  const devices = fakeDevices([owned()]);
  const auth = createDeviceAuth({ devices });
  const request = { headers: { 'x-device-id': 'vial-1', 'x-credential-id': 'key-1', 'x-api-key': token }, body: { device_id: 'vial-1' } };
  let next = 0;
  await auth(request, response(), () => next++);
  assert.equal(next, 1);
  assert.deepEqual(request.device_auth, { device_id: 'vial-1', credential_id: 'key-1', credential_version: 1 });
  for (const req of [{ ...request, body: { device_id: 'vial-2' } }, { ...request, headers: { ...request.headers, 'x-api-key': 'old-fleet-key' } }, { ...request, headers: { 'x-api-key': token } }]) {
    const res = response(); await auth(req, res, () => next++); assert.equal(res.code, 401);
  }
  devices.rows[0].credential.revoked_at = when;
  const revoked = response(); await auth(request, revoked, () => next++); assert.equal(revoked.code, 401);
  assert.equal(next, 1);
  assert.equal(safeDigestMatch(token, 'not-a-digest'), false);
});
test('mobile Bearer auth checks the shared session on every request, including expiry and revocation', async () => {
  let row = { user_id: 'owner-1', session_id: 'session-1', expires_at: new Date(+when + 1000) };
  const seen = [];
  const auth = createVerifyToken({ query: async value => { seen.push(value); return { rows: row ? [row] : [] }; }, now: () => when });
  let next = 0;
  const req = { headers: { authorization: 'Bearer ' + token } };
  await auth(req, response(), () => next++);
  assert.equal(req.user_id, 'owner-1'); assert.equal(req.user_role, 'user');
  row.expires_at = when;
  const expired = response(); await auth(req, expired, () => next++); assert.equal(expired.code, 401);
  row = null;
  const revoked = response(); await auth(req, revoked, () => next++); assert.equal(revoked.code, 401);
  const cookie = response(); await auth({ headers: { cookie: 'session=' + token } }, cookie, () => next++); assert.equal(cookie.code, 401);
  assert.equal(next, 1); assert.equal(seen.length, 3);
  assert.match(SESSION_QUERY, /s\.token = \$1/); assert.match(SESSION_QUERY, /FROM "Session"/);
});
test('auth DB failures never echo secrets or database errors', async () => {
  const auth = createVerifyToken({ query: async () => { throw new Error('postgres://sensitive-password'); } });
  const res = response(); await auth({ headers: { authorization: 'Bearer ' + token } }, res, () => assert.fail());
  assert.equal(res.code, 503); assert.doesNotMatch(JSON.stringify(res.body), /password|postgres|aaaa/);
});

test('ID-only enrollment is unavailable without trusted vendor possession proof', async () => {
  const controller = createAppController({ devices: fakeDevices([provisioned({ claim_grant: undefined })]), now: () => when });
  const res = response(); await controller.claimDevice({ user_id: 'owner-1', body: { device_id: 'vial-1' } }, res);
  assert.equal(res.code, 503); assert.equal(res.body.code, 'claim_verification_unavailable');
});
test('same owner is a verified idempotent success; a foreign owner remains 409', async () => {
  const controller = createAppController({ devices: fakeDevices([owned()]), now: () => when });
  const own = response(); await controller.claimDevice({ user_id: 'owner-1', body: { device_id: 'vial-1' } }, own);
  assert.equal(own.code, 200); assert.equal(own.body.ownership_verified, true); assert.equal(own.body.already_owned, true);
  assert.equal(own.body.device.credential, undefined);
  const foreign = response(); await controller.claimDevice({ user_id: 'owner-2', body: { device_id: 'vial-1' } }, foreign);
  assert.equal(foreign.code, 409); assert.doesNotMatch(JSON.stringify(foreign.body), /owner-1/);
});
test('claim grant is user-bound, expiring, credential-bound and consumed atomically', async () => {
  const devices = fakeDevices([provisioned()]);
  const controller = createAppController({ devices, now: () => when, uuid: () => 'new-epoch' });
  const foreign = response(); await controller.claimDevice({ user_id: 'owner-2', body: { device_id: 'vial-1', claim_token: token } }, foreign);
  assert.equal(foreign.code, 403);
  const wrong = response(); await controller.claimDevice({ user_id: 'owner-1', body: { device_id: 'vial-1', claim_token: 'b'.repeat(48) } }, wrong);
  assert.equal(wrong.code, 403);
  const results = [response(), response()];
  await Promise.all(results.map(res => controller.claimDevice({ user_id: 'owner-1', body: { device_id: 'vial-1', claim_token: token } }, res)));
  assert.ok(results.every(res => res.code === 200));
  assert.equal(devices.rows[0].ownership_epoch, 'new-epoch'); assert.equal(devices.rows[0].claim_grant, undefined);
  assert.equal(devices.updates[0].filter.claimed, false);
  for (const patch of [{ expires_at: when }, { credential_version: 2 }]) {
    const fixture = provisioned(); Object.assign(fixture.claim_grant, patch);
    const res = response(); await createAppController({ devices: fakeDevices([fixture]), now: () => when }).claimDevice({ user_id: 'owner-1', body: { device_id: 'vial-1', claim_token: token } }, res);
    assert.equal(res.code, 403);
  }
});
test('release atomically revokes old credentials, grants and pending invitations', async () => {
  const devices = fakeDevices([owned({ caregiver_id: 'carer', caregiver_grant: { user_id: 'carer' }, caregiver_invitation: { id: 'invite' }, claim_grant: { token_hash: digest(token) } })]);
  const controller = createAppController({ devices, now: () => when, uuid: () => 'released-epoch' });
  const res = response(); await controller.removeClaimedDevice({ user_id: 'owner-1', params: { device_id: 'vial-1' } }, res);
  const row = devices.rows[0];
  assert.equal(res.code, 200); assert.equal(row.user_id, null); assert.equal(row.claimed, false); assert.equal(row.caregiver_id, null);
  assert.equal(row.caregiver_grant, undefined); assert.equal(row.caregiver_invitation, undefined); assert.equal(row.claim_grant, undefined);
  assert.equal(row.credential.hash, undefined); assert.equal(row.credential.version, 2); assert.deepEqual(row.credential.revoked_at, when);
  assert.equal(row.ownership_epoch, 'released-epoch');
});
test('owner history is observation-time scoped and does not require current ownership', async () => {
  const filters = [];
  const controller = createAppController({ devices: fakeDevices([]), events: { find(filter) { filters.push(filter); return query([]); } } });
  await controller.getADeviceEvents({ user_id: 'former-owner', params: { device_id: 'resold-vial' } }, response());
  await controller.getAllDevicesEvents({ user_id: 'new-owner' }, response());
  assert.deepEqual(filters, [{ device_id: 'resold-vial', owner_id: 'former-owner' }, { owner_id: 'new-owner' }]);
  const res = response(); await controller.deleteDeviceEvents({ user_id: 'new-owner', params: { device_id: 'resold-vial' } }, res);
  assert.equal(res.code, 405);
});
test('legacy caregiver_id without recipient acceptance grants no event access', async () => {
  const controller = createCaregiverController({ devices: fakeDevices([owned({ caregiver_id: 'carer' })]), events: { find: () => assert.fail('must not read events') } });
  const res = response(); await controller.getCaregiver_A_device_summery({ user_id: 'carer', params: { device_id: 'vial-1' } }, res);
  assert.equal(res.code, 404);
});
test('caregiver invitation requires acceptance and a matching ownership epoch', async () => {
  const devices = fakeDevices([owned()]);
  const controller = createCaregiverController({ devices, users: { exists: async () => true }, now: () => when, uuid: () => 'invite-1' });
  const invite = response(); await controller.claimDeviceForCaregiver({ user_id: 'owner-1', body: { device_id: 'vial-1', caregiver_id: 'carer' } }, invite);
  assert.equal(invite.code, 202); assert.equal(devices.rows[0].caregiver_grant, undefined);
  const foreign = response(); await controller.acceptInvitation({ user_id: 'other', params: { invitation_id: 'invite-1' } }, foreign); assert.equal(foreign.code, 404);
  const accept = response(); await controller.acceptInvitation({ user_id: 'carer', params: { invitation_id: 'invite-1' } }, accept); assert.equal(accept.code, 200);
  assert.equal(devices.rows[0].caregiver_grant.ownership_epoch, 'epoch-1'); assert.equal(devices.rows[0].caregiver_grant.scope, 'observations:read');
});

function observationFixture() {
  const devices = fakeDevices([owned(), owned({ device_id: 'vial-2' })]);
  const rows = [];
  const events = { findOne(filter) { return query(rows.find(row => matches(row, filter)) || null); }, async create(values) { rows.push(...structuredClone(values)); } };
  let queue = Promise.resolve();
  const connection = { transaction(fn) { const result = queue.then(() => fn({})); queue = result.catch(() => {}); return result; } };
  const persist = createObservationService({ devices, events, connection, now: () => when });
  return { persist, devices, events, connection, rows };
}
test('simultaneous identical observations produce one immutable row and scoped receipts', async () => {
  const fixture = observationFixture();
  const results = await Promise.all(Array.from({ length: 6 }, () => fixture.persist({ body: input, deviceId: 'vial-1', userId: 'owner-1' })));
  assert.equal(fixture.rows.length, 1); assert.equal(results.filter(result => result.status === 'stored').length, 1);
  assert.deepEqual(results[0].receipt, { event_id: 'event-1', device_id: 'vial-1', ownership_epoch: 'epoch-1', boot_id: 'boot-1', sequence: 0, committed: true });
  assert.equal(fixture.rows[0].source, 'phone_ble'); assert.equal(fixture.rows[0].evidence_type, 'vial_observation');
  assert.equal(fixture.rows[0].takenAt, undefined);
  await fixture.persist({ body: input, deviceId: 'vial-2', userId: 'owner-1' }); assert.equal(fixture.rows.length, 2);
});
test('changed event content or a reused sequence cannot masquerade as a duplicate', async () => {
  const { persist, rows } = observationFixture();
  await persist({ body: input, deviceId: 'vial-1', userId: 'owner-1' });
  for (const patch of [{ payload: { chng: 2 } }, { event_id: 'another-id' }]) {
    await assert.rejects(persist({ body: { ...input, ...patch }, deviceId: 'vial-1', userId: 'owner-1' }), error => error.code === 'event_identity_conflict');
  }
  assert.equal(rows.length, 1);
});
test('foreign owner, stale epoch and revoked credentials cannot upload or replay receipts', async () => {
  const { persist, devices, rows } = observationFixture();
  for (const request of [{ userId: 'other' }, { userId: 'owner-1', body: { ...input, ownership_epoch: 'old-epoch' } }, { deviceAuth: { device_id: 'vial-1', credential_id: 'key-1', credential_version: 2 } }]) {
    await assert.rejects(persist({ body: input, deviceId: 'vial-1', ...request }), error => error.code === 'ownership_changed');
  }
  devices.rows[0].claimed_at = new Date(+when + 1000);
  await assert.rejects(persist({ body: input, deviceId: 'vial-1', userId: 'owner-1' }), error => error.code === 'timestamp_before_ownership');
  assert.equal(rows.length, 0);
});
test('a failed durable commit never returns a committed receipt', async () => {
  const fixture = observationFixture();
  const persist = createObservationService({ devices: fixture.devices, events: fixture.events, connection: { transaction: async fn => { await fn({}); throw new Error('commit failed'); } }, now: () => when });
  await assert.rejects(persist({ body: input, deviceId: 'vial-1', userId: 'owner-1' }), /commit failed/);
});
test('process-local limiter bounds request bursts and key memory', () => {
  let time = 0, passed = 0;
  const limit = requestLimit({ max: 2, windowMs: 1000, maxKeys: 1, now: () => time });
  limit({ ip: 'a' }, response(), () => passed++); limit({ ip: 'a' }, response(), () => passed++);
  const busy = response(); limit({ ip: 'a' }, busy, () => passed++); assert.equal(busy.code, 429);
  const overflow = response(); limit({ ip: 'b' }, overflow, () => passed++); assert.equal(overflow.code, 503);
  time = 1001; limit({ ip: 'b' }, response(), () => passed++); assert.equal(passed, 3);
});

test('append-only model guards reject update and delete without issuing a database write', async () => {
  const Event = require('../models/Event');
  await assert.rejects(Event.updateOne({ event_id: 'event-1' }, { $set: { event_type: 'OPEN' } }), /append-only/);
  await assert.rejects(Event.deleteMany({ event_id: 'event-1' }), /append-only/);
});
