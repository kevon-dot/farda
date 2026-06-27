// ============================================
// #50 — Telemetry battery field mapping (no MongoDB required)
// ============================================
// Clients/devices send `battery_percent`, but the original updateTelemetry
// handler read `battery`, so the reading was silently dropped. These tests pin
// the field mapping both at the pure-helper level and end-to-end through the
// controller (with the Device/Event Mongoose models mocked so no DB is needed).

const test = require("node:test");
const assert = require("node:assert");
const path = require("node:path");
const Module = require("node:module");

// ---------------------------------------------------------------------------
// Load the controller with the Mongoose models replaced by lightweight fakes,
// so we can exercise the async handler without a live MongoDB.
// ---------------------------------------------------------------------------
const DEVICE_PATH = path.resolve(__dirname, "../models/Device.js");
const EVENT_PATH = path.resolve(__dirname, "../models/Event.js");

let savedDevice = null; // the most recent device instance that had .save() called

class FakeDevice {
  constructor(props = {}) {
    Object.assign(this, props);
  }
  async save() {
    savedDevice = this;
    return this;
  }
}
// findOne is overridden per-test (default: device does not exist).
FakeDevice.findOne = async () => null;

class FakeEvent {
  constructor(props = {}) {
    Object.assign(this, props);
  }
  async save() {
    return this;
  }
}
FakeEvent.findOne = async () => null;

// Inject the fakes into the require cache BEFORE the controller is required.
function loadController() {
  delete require.cache[require.resolve("../controllers/ingestion.controller")];
  require.cache[DEVICE_PATH] = new Module(DEVICE_PATH);
  require.cache[DEVICE_PATH].exports = FakeDevice;
  require.cache[DEVICE_PATH].loaded = true;
  require.cache[EVENT_PATH] = new Module(EVENT_PATH);
  require.cache[EVENT_PATH].exports = FakeEvent;
  require.cache[EVENT_PATH].loaded = true;
  return require("../controllers/ingestion.controller");
}

const controller = loadController();
const { resolveBatteryPercent, updateTelemetry } = controller;

// Minimal Express res double.
function makeRes() {
  return {
    statusCode: null,
    body: null,
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(payload) {
      this.body = payload;
      return this;
    },
  };
}

async function runTelemetry(body, { existingDevice = null } = {}) {
  savedDevice = null;
  FakeDevice.findOne = async () => existingDevice;
  const res = makeRes();
  await updateTelemetry({ body }, res);
  return { res, savedDevice };
}

// ===========================================================================
// Pure helper: resolveBatteryPercent
// ===========================================================================

test("resolveBatteryPercent reads battery_percent (the wire field clients send)", () => {
  assert.strictEqual(resolveBatteryPercent({ battery_percent: 73 }), 73);
});

test("resolveBatteryPercent falls back to legacy battery", () => {
  assert.strictEqual(resolveBatteryPercent({ battery: 42 }), 42);
});

test("resolveBatteryPercent prefers battery_percent when both are present", () => {
  assert.strictEqual(resolveBatteryPercent({ battery_percent: 80, battery: 10 }), 80);
});

test("resolveBatteryPercent preserves a genuine 0 reading (not coerced away)", () => {
  assert.strictEqual(resolveBatteryPercent({ battery_percent: 0 }), 0);
  assert.strictEqual(resolveBatteryPercent({ battery: 0 }), 0);
});

test("resolveBatteryPercent returns undefined when neither field is sent", () => {
  assert.strictEqual(resolveBatteryPercent({ firmware_version: "1.2.3" }), undefined);
  assert.strictEqual(resolveBatteryPercent({}), undefined);
  assert.strictEqual(resolveBatteryPercent(null), undefined);
});

// ===========================================================================
// End-to-end through updateTelemetry (mocked models)
// ===========================================================================

test("battery_percent payload is stored on the new device's battery_percent field", async () => {
  const { res, savedDevice: dev } = await runTelemetry({
    device_id: "DEVICE001",
    battery_percent: 64,
    firmware_version: "2.0.0",
  });
  assert.strictEqual(res.statusCode, 200);
  assert.ok(dev, "device should have been saved");
  assert.strictEqual(dev.battery_percent, 64);
  assert.strictEqual(dev.firmware_version, "2.0.0");
});

test("legacy battery payload still maps to battery_percent (back-compat)", async () => {
  const { res, savedDevice: dev } = await runTelemetry({
    device_id: "DEVICE001",
    battery: 33,
  });
  assert.strictEqual(res.statusCode, 200);
  assert.strictEqual(dev.battery_percent, 33);
});

test("battery_percent updates an existing device", async () => {
  const existing = new FakeDevice({
    device_id: "DEVICE001",
    battery_percent: 90,
    firmware_version: "1.0.0",
  });
  const { res, savedDevice: dev } = await runTelemetry(
    { device_id: "DEVICE001", battery_percent: 55 },
    { existingDevice: existing }
  );
  assert.strictEqual(res.statusCode, 200);
  assert.strictEqual(dev.battery_percent, 55);
});

test("a battery_percent of 0 is recorded (not replaced by the default/previous)", async () => {
  // New device: 0 must NOT become the 100 default.
  const { savedDevice: created } = await runTelemetry({
    device_id: "DEVICE001",
    battery_percent: 0,
  });
  assert.strictEqual(created.battery_percent, 0);

  // Existing device: 0 must NOT be ignored in favour of the prior value.
  const existing = new FakeDevice({ device_id: "DEVICE001", battery_percent: 88 });
  const { savedDevice: updated } = await runTelemetry(
    { device_id: "DEVICE001", battery_percent: 0 },
    { existingDevice: existing }
  );
  assert.strictEqual(updated.battery_percent, 0);
});

test("missing battery defaults to 100 on a new device and preserves prior on existing", async () => {
  const { savedDevice: created } = await runTelemetry({ device_id: "DEVICE001" });
  assert.strictEqual(created.battery_percent, 100);

  const existing = new FakeDevice({ device_id: "DEVICE001", battery_percent: 47 });
  const { savedDevice: updated } = await runTelemetry(
    { device_id: "DEVICE001", firmware_version: "9.9.9" },
    { existingDevice: existing }
  );
  assert.strictEqual(updated.battery_percent, 47);
});

test("invalid device_id is rejected with 400 before touching the model", async () => {
  const { res } = await runTelemetry({ device_id: { $ne: null }, battery_percent: 50 });
  assert.strictEqual(res.statusCode, 400);
});
