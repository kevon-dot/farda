// ============================================
// GTM-539 — Fleet-health classification (PURE, no MongoDB)
// ============================================

const test = require("node:test");
const assert = require("node:assert");

const { classifyDeviceHealth, classifyFleet, HEALTH_FLAG } = require("../utils/fleetHealth");

const THRESHOLDS = {
  offlineAfterSeconds: 15 * 60, // 15 min
  staleSyncAfterSeconds: 24 * 60 * 60, // 24 h
  lowBatteryPercent: 20,
};

const NOW = Date.parse("2026-06-27T12:00:00Z");
const secondsAgo = (s) => new Date(NOW - s * 1000);

test("a recently-seen, recently-synced, well-charged device is healthy", () => {
  const h = classifyDeviceHealth(
    { battery_percent: 80, last_seen: secondsAgo(60), last_sync_at: secondsAgo(120) },
    THRESHOLDS,
    NOW
  );
  assert.strictEqual(h.healthy, true);
  assert.deepStrictEqual(h.flags, []);
});

test("offline: last_seen older than the offline window", () => {
  const h = classifyDeviceHealth(
    { battery_percent: 90, last_seen: secondsAgo(20 * 60), last_sync_at: secondsAgo(60) },
    THRESHOLDS,
    NOW
  );
  assert.strictEqual(h.offline, true);
  assert.ok(h.flags.includes(HEALTH_FLAG.OFFLINE));
  assert.strictEqual(h.healthy, false);
});

test("stale_sync: last_sync_at older than the stale window (still 'online')", () => {
  const h = classifyDeviceHealth(
    { battery_percent: 90, last_seen: secondsAgo(60), last_sync_at: secondsAgo(48 * 60 * 60) },
    THRESHOLDS,
    NOW
  );
  assert.strictEqual(h.offline, false);
  assert.strictEqual(h.stale_sync, true);
  assert.ok(h.flags.includes(HEALTH_FLAG.STALE_SYNC));
});

test("low_battery: at or below the threshold", () => {
  const at = classifyDeviceHealth(
    { battery_percent: 20, last_seen: secondsAgo(30), last_sync_at: secondsAgo(30) },
    THRESHOLDS,
    NOW
  );
  assert.strictEqual(at.low_battery, true);

  const above = classifyDeviceHealth(
    { battery_percent: 21, last_seen: secondsAgo(30), last_sync_at: secondsAgo(30) },
    THRESHOLDS,
    NOW
  );
  assert.strictEqual(above.low_battery, false);
});

test("a never-seen device is treated as offline AND stale", () => {
  const h = classifyDeviceHealth(
    { battery_percent: 100, last_seen: null, last_sync_at: null },
    THRESHOLDS,
    NOW
  );
  assert.strictEqual(h.offline, true);
  assert.strictEqual(h.stale_sync, true);
});

test("last_sync_at falls back to last_seen when never synced", () => {
  // No explicit last_sync_at, but last_seen is fresh ⇒ not stale.
  const h = classifyDeviceHealth(
    { battery_percent: 100, last_seen: secondsAgo(60) },
    THRESHOLDS,
    NOW
  );
  assert.strictEqual(h.stale_sync, false);
});

test("classifyFleet returns only unhealthy devices + a summary roll-up", () => {
  const devices = [
    { device_id: "OK", battery_percent: 90, last_seen: secondsAgo(60), last_sync_at: secondsAgo(60) },
    { device_id: "OFFLINE", battery_percent: 90, last_seen: secondsAgo(60 * 60), last_sync_at: secondsAgo(60 * 60) },
    { device_id: "LOWBAT", battery_percent: 5, last_seen: secondsAgo(60), last_sync_at: secondsAgo(60) },
    { device_id: "STALE", battery_percent: 90, last_seen: secondsAgo(60), last_sync_at: secondsAgo(30 * 60 * 60) },
  ];
  const report = classifyFleet(devices, THRESHOLDS, NOW);
  assert.strictEqual(report.total, 4);
  assert.strictEqual(report.summary.unhealthy, 3);
  assert.strictEqual(report.summary.low_battery, 1);
  // OFFLINE device's last_sync (1h ago) is within the 24h stale window, so only
  // the STALE device (30h) is stale.
  assert.strictEqual(report.summary.stale_sync, 1);
  assert.strictEqual(report.summary.offline, 1);
  const ids = report.unhealthy.map((d) => d.device_id).sort();
  assert.deepStrictEqual(ids, ["LOWBAT", "OFFLINE", "STALE"]);
});
