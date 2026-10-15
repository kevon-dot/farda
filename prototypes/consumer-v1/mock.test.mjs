import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import vm from 'node:vm';
const root = path.dirname(fileURLToPath(import.meta.url));
const html = readFileSync(path.join(root, 'index.html'), 'utf8');
const code = html.match(/<script>([\s\S]*?)<\/script>/)[1];
function demo() {
  const nodes = new Map();
  const node = (id) => {
    if (!nodes.has(id)) nodes.set(id, { innerHTML: '', textContent: '', hidden: true, focus() {}, addEventListener() {}, querySelectorAll: () => [] });
    return nodes.get(id);
  };
  const context = { window: {}, document: { getElementById: node, addEventListener() {}, activeElement: null }, clearTimeout() {}, setTimeout() {} };
  vm.runInNewContext(code, context);
  return { api: context.window.fardaDemo, text: () => node('screen').innerHTML, modal: () => node('modal').innerHTML };
}
test('all five screens render in all five hardware scenarios', () => {
  const d = demo();
  for (const scenario of ['ready', 'waiting', 'offline', 'uncertain', 'low']) {
    d.api.scenario(scenario);
    for (const view of ['today', 'routine', 'history', 'vial', 'circle']) {
      d.api.go(view);
      assert.match(d.text(), /<h1/);
      assert.doesNotMatch(d.text(), /undefined|NaN/);
    }
  }
});
test('logging requires a separate confirmation action, and undo works', () => {
  const d = demo(); d.api.act('confirm');
  assert.equal(d.api.getState().taken, false);
  assert.match(d.modal(), /not proof of ingestion/);
  d.api.act('confirm-save');
  assert.equal(d.api.getState().taken, true);
  assert.match(d.text(), /You confirmed/);
  d.api.act('undo'); assert.equal(d.api.getState().taken, false);
});
test('unknown offline status is not silently changed to missed', () => {
  const d = demo(); d.api.scenario('offline');
  assert.match(d.text(), /can’t verify recent activity/);
  d.api.act('sync'); assert.equal(d.api.getState().scenario, 'offline');
  assert.equal(d.api.getState().taken, false);
});
test('a pill signal does not become a taken dose automatically', () => {
  const d = demo(); d.api.scenario('uncertain');
  assert.equal(d.api.getState().taken, false);
  assert.match(d.text(), /does not tell us whether you took it/);
});
test('no-hardware mode supports a manual dose log', () => {
  const d = demo(); d.api.scenario('waiting'); d.api.act('confirm-save');
  assert.equal(d.api.getState().taken, true);
  assert.equal(d.api.getState().scenario, 'waiting');
});
test('all setup steps are explicitly simulated', () => {
  const d = demo(); d.api.scenario('waiting'); d.api.go('vial');
  for (let i = 0; i < 3; i++) d.api.act('setup-next');
  assert.match(d.text(), /Final sequence awaits hardware validation/);
  d.api.act('setup-next'); assert.equal(d.api.getState().scenario, 'ready');
});
test('routine edits are saved and displayed safely', () => {
  const d = demo();
  assert.equal(d.api.saveRoutine('Demo <script>', '07:30'), true);
  assert.match(d.text(), /Demo &lt;script&gt;/);
  assert.match(d.text(), /7:30 AM/);
  assert.equal(d.api.saveRoutine('', '07:30'), false);
  assert.equal(d.api.saveRoutine('Demo', '32:99'), false);
});
test('unreadable scan cannot activate a new medication plan', () => {
  const d = demo(); d.api.act('scan');
  assert.match(d.modal(), /cannot activate a new medication plan/);
  assert.doesNotMatch(d.modal(), /type="submit"/);
});
test('sharing can be simulated and revoked without a request', () => {
  const d = demo(); d.api.go('circle'); d.api.act('invite-save');
  assert.equal(d.api.getState().shared, true);
  d.api.act('revoke-save'); assert.equal(d.api.getState().shared, false);
  assert.doesNotMatch(code, /\bfetch\s*\(|XMLHttpRequest|navigator\.bluetooth/);
});
test('all referenced local assets exist', () => {
  for (const asset of [...html.matchAll(/\.\.\/\.\.\/farda-app\/assets\/[\w/.\-]+/g)].map(x => x[0])) {
    assert.equal(existsSync(path.resolve(root, asset)), true, asset);
  }
});
test('standalone build has no remaining external or repo asset dependency', () => {
  const built = readFileSync(path.join(root, 'farda-consumer-mock.html'), 'utf8');
  assert.doesNotMatch(built, /\.\.\/\.\.\/farda-app/);
  assert.match(built, /data:image\/png;base64,/);
  assert.match(built, /data:font\/ttf;base64,/);
});
