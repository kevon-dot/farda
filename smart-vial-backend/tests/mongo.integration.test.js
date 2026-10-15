const test = require('node:test');
const assert = require('node:assert/strict');
const mongoose = require('mongoose');
const { randomUUID } = require('node:crypto');
const Device = require('../models/Device');
const Event = require('../models/Event');
const User = require('../models/User');
const { digest } = require('../lib/validation');
const { createObservationService } = require('../services/observationService');
const { createAppController } = require('../controllers/app.api.controller');
const { createCaregiverController } = require('../controllers/caregiver.controller');
const { response } = require('./helpers');

const uri = process.env.VIAL_TEST_MONGODB_URI;

test('MongoDB replica-set integration: commits, replay indexes, ownership and transfer races', { skip: !uri }, async t => {
  const parsed = new URL(uri);
  assert.ok(['localhost', '127.0.0.1', '[::1]'].includes(parsed.hostname), 'Integration tests only accept a disposable local database');
  assert.match(parsed.pathname, /^\/farda_test_[A-Za-z0-9_-]+$/, 'Dedicated farda_test_ database required; tests drop it');
  await mongoose.connect(uri, { autoIndex: false, serverSelectionTimeoutMS: 5000 });
  t.after(async () => { await mongoose.connection.dropDatabase(); await mongoose.disconnect(); });
  const hello = await mongoose.connection.db.admin().command({ hello: 1 });
  assert.ok(hello.setName || hello.msg === 'isdbgrid', 'A real replica set is required');
  await Device.createIndexes(); await Event.createIndexes(); await User.createIndexes();
  const now = new Date(Math.floor(Date.now() / 1000) * 1000);
  const key = 'integration-secret-'.repeat(4);
  const credential = { id: 'key-1', version: 1, hash: digest(key), revoked_at: null };
  const base = { claimed: true, user_id: 'owner-1', ownership_epoch: 'epoch-1', claimed_at: new Date(+now - 60000), isActive: true, credential };
  const event = { event_id: 'event-1', ownership_epoch: 'epoch-1', boot_id: 'boot-1', sequence: 0, event: 'PILL_CHANGE', timestamp: +now / 1000, payload: { chng: 1, cnt: 9 } };
  const persist = createObservationService();
  const controller = createAppController();

  await t.test('real unique indexes retain one event under concurrent retries and allow cross-device IDs', async () => {
    await Device.create([{ ...base, device_id: 'vial-1' }, { ...base, device_id: 'vial-2' }]);
    // Legacy global sparse key can remain: new records never write null into it.
    await Event.collection.createIndex({ idempotency_key: 1 }, { unique: true, sparse: true });
    await Event.collection.insertOne({ device_id: 'legacy', idempotency_key: null, event_type: 'PILL_CHANGE' });
    const results = await Promise.all(Array.from({ length: 8 }, () => persist({ body: event, deviceId: 'vial-1', userId: 'owner-1' })));
    assert.equal(results.filter(result => result.status === 'stored').length, 1);
    assert.ok(results.every(result => result.receipt.committed));
    assert.equal(await Event.countDocuments({ device_id: 'vial-1' }), 1);
    await persist({ body: event, deviceId: 'vial-2', userId: 'owner-1' });
    assert.equal(await Event.countDocuments({ owner_id: 'owner-1' }), 2);
    for (const patch of [{ payload: { cnt: 2 } }, { event_id: 'another-id' }]) {
      await assert.rejects(persist({ body: { ...event, ...patch }, deviceId: 'vial-1', userId: 'owner-1' }), error => error.code === 'event_identity_conflict');
    }
    const indexes = await Event.collection.indexes();
    assert.ok(indexes.some(index => index.name === 'observation_event_identity' && index.unique));
    assert.ok(indexes.some(index => index.name === 'observation_sequence_identity' && index.unique));
    const row = await Event.findOne({ device_id: 'vial-1' }).lean();
    assert.equal(row.source, 'phone_ble'); assert.equal(row.evidence_type, 'vial_observation'); assert.equal(row.takenAt, undefined);
  });

  await t.test('grant consumption permits one verified owner under simultaneous claims', async () => {
    await Device.create({ device_id: 'new-vial', claimed: false, user_id: null, credential, claim_grant: { method: 'vendor-possession-v1', user_id: 'owner-1', token_hash: digest(key), expires_at: new Date(Date.now() + 60000), credential_version: 1 } });
    const callers = ['owner-1', 'owner-1', 'owner-2', 'owner-2'];
    const responses = await Promise.all(callers.map(async user_id => {
      const res = response(); await controller.claimDevice({ user_id, body: { device_id: 'new-vial', claim_token: key } }, res); return res;
    }));
    assert.ok(responses.slice(0, 2).every(res => res.code === 200));
    assert.ok(responses.slice(2).every(res => [403, 409].includes(res.code)));
    const device = await Device.findOne({ device_id: 'new-vial' }).select('+claim_grant.token_hash');
    assert.equal(device.user_id, 'owner-1'); assert.ok(device.ownership_epoch); assert.equal(device.claim_grant?.token_hash, undefined);
  });

  await t.test('transaction rollback leaves no receipt or partial event', async () => {
    const failing = createObservationService({ events: { findOne: (...args) => Event.findOne(...args), create: async (values, options) => { await Event.create(values, options); throw new Error('test-abort'); } } });
    await assert.rejects(failing({ body: { ...event, event_id: 'aborted', sequence: 88 }, deviceId: 'vial-1', userId: 'owner-1' }), /test-abort/);
    assert.equal(await Event.countDocuments({ device_id: 'vial-1', event_id: 'aborted' }), 0);
  });

  await t.test('unclaim races cannot move evidence or old sharing into a new ownership epoch', async () => {
    const device_id = 'transfer-vial';
    await Device.create({ ...base, device_id, caregiver_id: 'carer', caregiver_grant: { user_id: 'carer', ownership_epoch: 'epoch-1', scope: 'observations:read', accepted_at: now } });
    await persist({ body: event, deviceId: device_id, userId: 'owner-1' });
    const release = response();
    const race = await Promise.allSettled([
      persist({ body: { ...event, event_id: 'racing', sequence: 1 }, deviceId: device_id, userId: 'owner-1' }),
      controller.removeClaimedDevice({ user_id: 'owner-1', params: { device_id } }, release),
    ]);
    assert.equal(release.code, 200);
    if (race[0].status === 'rejected') assert.equal(race[0].reason.code, 'ownership_changed');
    const released = await Device.findOne({ device_id }).select('+credential.hash +credential.version +credential.revoked_at');
    assert.equal(released.user_id, null); assert.equal(released.caregiver_grant?.user_id, undefined);
    assert.equal(released.credential.hash, undefined); assert.ok(released.credential.revoked_at);
    await assert.rejects(persist({ body: event, deviceId: device_id, deviceAuth: { device_id, credential_id: 'key-1', credential_version: 1 } }), error => error.code === 'ownership_changed');
    // Test-only trusted provisioning. No public endpoint can manufacture this proof.
    await Device.updateOne({ device_id }, { $set: { credential: { ...credential, id: 'key-2', version: 3 }, claim_grant: { method: 'vendor-possession-v1', user_id: 'owner-2', token_hash: digest(key), expires_at: new Date(Date.now() + 60000), credential_version: 3 } } });
    const claim = response(); await controller.claimDevice({ user_id: 'owner-2', body: { device_id, claim_token: key } }, claim);
    assert.equal(claim.code, 200);
    const nextEvent = { ...event, ownership_epoch: claim.body.device.ownership_epoch, timestamp: Math.floor(Date.now() / 1000) };
    await persist({ body: nextEvent, deviceId: device_id, userId: 'owner-2' });
    const oldHistory = response(), newHistory = response();
    await controller.getADeviceEvents({ user_id: 'owner-1', params: { device_id } }, oldHistory);
    await controller.getADeviceEvents({ user_id: 'owner-2', params: { device_id } }, newHistory);
    assert.ok(oldHistory.body.length >= 1); assert.ok(oldHistory.body.every(row => row.owner_id === 'owner-1' && row.ownership_epoch === 'epoch-1'));
    assert.equal(newHistory.body.length, 1); assert.equal(newHistory.body[0].owner_id, 'owner-2');
    const carer = response(); await createCaregiverController().getCaregiver_A_device_summery({ user_id: 'carer', params: { device_id } }, carer);
    assert.equal(carer.code, 404);
  });

  await t.test('observation model rejects mutation and public deletion', async () => {
    await assert.rejects(Event.updateOne({ device_id: 'vial-1' }, { $set: { event_type: 'OPEN' } }), /append-only/);
    await assert.rejects(Event.deleteMany({ device_id: 'vial-1' }), /append-only/);
    const res = response(); await controller.deleteDeviceEvents({ user_id: 'owner-1', params: { device_id: 'vial-1' } }, res);
    assert.equal(res.code, 405); assert.equal(await Event.countDocuments({ device_id: 'vial-1' }), 1);
  });
});
