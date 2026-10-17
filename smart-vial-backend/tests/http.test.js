const test = require('node:test');
const assert = require('node:assert/strict');
const { createApp } = require('../Server');

test('HTTP boundaries reject anonymous user writes, fleet keys and unbounded bodies before storage', async t => {
  const server = createApp().listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  t.after(() => new Promise(resolve => server.close(resolve)));
  const base = 'http://127.0.0.1:' + server.address().port;
  const json = { 'content-type': 'application/json' };
  for (const path of ['/api/user/claim', '/api/user/devices/vial-1/observations', '/api/caregiver/claim-device']) {
    const result = await fetch(base + path, { method: 'POST', headers: json, body: '{}' });
    assert.equal(result.status, 401);
  }
  const fleet = await fetch(base + '/api/ingest/telemetry', { method: 'POST', headers: { ...json, 'x-api-key': 'our-device-api-key-change-this-in-production' }, body: JSON.stringify({ device_id: 'new-vial', battery: 0 }) });
  assert.equal(fleet.status, 401);
  const oversize = await fetch(base + '/api/ingest/event', { method: 'POST', headers: json, body: JSON.stringify({ payload: 'x'.repeat(20000) }) });
  assert.equal(oversize.status, 413);
  const bad = await fetch(base + '/api/ingest/event', { method: 'POST', headers: json, body: '{broken' });
  assert.equal(bad.status, 400);
});

test('operational probes separate liveness from dependency readiness and include provenance', async t => {
  const unavailable = createApp({ readinessProbe: async () => { throw new Error('database secret'); } }).listen(0, '127.0.0.1');
  await new Promise(resolve => unavailable.once('listening', resolve));
  t.after(() => new Promise(resolve => unavailable.close(resolve)));
  const base = 'http://127.0.0.1:' + unavailable.address().port;
  const health = await fetch(base + '/health');
  assert.equal(health.status, 200);
  assert.equal((await health.json()).service, 'smart-vial-api');
  const ready = await fetch(base + '/ready');
  assert.equal(ready.status, 503);
  assert.doesNotMatch(await ready.text(), /database secret/);

  const available = createApp({ readinessProbe: async () => true }).listen(0, '127.0.0.1');
  await new Promise(resolve => available.once('listening', resolve));
  t.after(() => new Promise(resolve => available.close(resolve)));
  assert.equal((await fetch('http://127.0.0.1:' + available.address().port + '/ready')).status, 200);
});
