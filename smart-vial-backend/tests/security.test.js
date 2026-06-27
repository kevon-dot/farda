const test = require("node:test");
const assert = require("node:assert");

const { deepSanitize, isDangerousKey } = require("../middleware/sanitize");
const {
  validateIngestionEvent,
  validateDeviceId,
  ALLOWED_EVENT_TYPES,
} = require("../utils/eventValidation");

// Self-contained: no MongoDB / Postgres / network required.

// ============================================
// #37 — NoSQL operator-injection sanitization
// ============================================

test("isDangerousKey flags $-prefixed and dotted keys", () => {
  assert.strictEqual(isDangerousKey("$ne"), true);
  assert.strictEqual(isDangerousKey("$where"), true);
  assert.strictEqual(isDangerousKey("a.b"), true);
  assert.strictEqual(isDangerousKey("device_id"), false);
  assert.strictEqual(isDangerousKey("event"), false);
});

test("deepSanitize strips $-prefixed and dotted keys from a sample object", () => {
  const input = {
    device_id: "DEVICE001",
    $where: "while(true){}",
    nested: {
      $ne: null,
      "a.b": 1,
      keep: "yes",
    },
    list: [{ $gt: 5, ok: 1 }],
  };

  const out = deepSanitize(input);

  assert.deepStrictEqual(out, {
    device_id: "DEVICE001",
    nested: { keep: "yes" },
    list: [{ ok: 1 }],
  });
});

test("deepSanitize does not mutate its input", () => {
  const input = { $ne: 1, keep: 2 };
  const out = deepSanitize(input);
  assert.ok("$ne" in input, "original should be untouched");
  assert.ok(!("$ne" in out));
});

test("deepSanitize leaves Date instances intact", () => {
  const d = new Date("2026-01-01T00:00:00Z");
  const out = deepSanitize({ when: d });
  assert.strictEqual(out.when, d);
});

// ============================================
// #37 — device_id scalar validation
// ============================================

test("validateDeviceId rejects non-string (e.g. { $ne: null })", () => {
  assert.strictEqual(validateDeviceId({ $ne: null }).ok, false);
  assert.strictEqual(validateDeviceId(123).ok, false);
  assert.strictEqual(validateDeviceId(["a"]).ok, false);
  assert.strictEqual(validateDeviceId("").ok, false);
  assert.strictEqual(validateDeviceId(undefined).ok, false);
});

test("validateDeviceId accepts a non-empty string", () => {
  const r = validateDeviceId("DEVICE001");
  assert.strictEqual(r.ok, true);
  assert.strictEqual(r.value, "DEVICE001");
});

// ============================================
// #38 — Event payload validation
// ============================================

test("validateIngestionEvent accepts a well-formed OPEN event", () => {
  const r = validateIngestionEvent({
    device_id: "DEVICE001",
    event: "OPEN",
    event_id: "evt_123",
    timestamp: 1738483200,
    payload: { duration: 5.2, sensor_value: 123 },
  });
  assert.strictEqual(r.ok, true);
  assert.strictEqual(r.value.device_id, "DEVICE001");
  assert.strictEqual(r.value.event, "OPEN");
  assert.deepStrictEqual(r.value.payload, { duration: 5.2, sensor_value: 123 });
});

test("validateIngestionEvent normalizes event casing to uppercase", () => {
  const r = validateIngestionEvent({ device_id: "D1", event: "open" });
  assert.strictEqual(r.ok, true);
  assert.strictEqual(r.value.event, "OPEN");
});

test("validateIngestionEvent accepts a well-formed event for every allowed type", () => {
  for (const type of ALLOWED_EVENT_TYPES) {
    const r = validateIngestionEvent({ device_id: "D1", event: type, payload: {} });
    assert.strictEqual(r.ok, true, `expected ${type} to validate`);
  }
});

test("validateIngestionEvent rejects unknown event types", () => {
  const r = validateIngestionEvent({ device_id: "D1", event: "DROP_TABLE" });
  assert.strictEqual(r.ok, false);
  assert.match(r.error, /Unknown event_type/);
});

test("validateIngestionEvent rejects missing device_id", () => {
  const r = validateIngestionEvent({ event: "OPEN" });
  assert.strictEqual(r.ok, false);
});

test("validateIngestionEvent rejects injection device_id { $ne: null }", () => {
  const r = validateIngestionEvent({ device_id: { $ne: null }, event: "OPEN" });
  assert.strictEqual(r.ok, false);
});

test("validateIngestionEvent rejects wrong-typed payload fields", () => {
  const r = validateIngestionEvent({
    device_id: "D1",
    event: "OPEN",
    payload: { duration: "not-a-number" },
  });
  assert.strictEqual(r.ok, false);
  assert.match(r.error, /Invalid payload/);
});

test("validateIngestionEvent rejects non-numeric timestamp", () => {
  const r = validateIngestionEvent({
    device_id: "D1",
    event: "OPEN",
    timestamp: "yesterday",
  });
  assert.strictEqual(r.ok, false);
});

test("validateIngestionEvent defaults a missing payload to {}", () => {
  const r = validateIngestionEvent({ device_id: "D1", event: "CLOSE" });
  assert.strictEqual(r.ok, true);
  assert.deepStrictEqual(r.value.payload, {});
});
