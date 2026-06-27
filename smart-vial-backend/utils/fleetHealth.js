// ============================================
// GTM-539 — Fleet-health classification (PURE)
// ============================================
// Derives a device's operational health from its timestamps + battery against
// configurable thresholds. No DB / Express here so it is unit-testable; the
// controller passes plain values + a `now` and the thresholds from config.
//
// Health dimensions (a device can have several flags at once):
//   - OFFLINE     : not seen within `offlineAfterSeconds` (last_seen).
//   - STALE_SYNC  : no successful sync within `staleSyncAfterSeconds`
//                   (last_sync_at; falls back to last_seen if never synced).
//   - LOW_BATTERY : battery_percent <= lowBatteryPercent.
//
// A device is "healthy" iff none of the flags are set.

const HEALTH_FLAG = Object.freeze({
  OFFLINE: "offline",
  STALE_SYNC: "stale_sync",
  LOW_BATTERY: "low_battery",
});

/**
 * Coerce a Date | ISO string | epoch-ms number to epoch ms, or null.
 * @param {*} v
 * @returns {number|null}
 */
function toMillis(v) {
  if (v == null) return null;
  if (v instanceof Date) {
    const t = v.getTime();
    return Number.isNaN(t) ? null : t;
  }
  if (typeof v === "number") return Number.isFinite(v) ? v : null;
  if (typeof v === "string") {
    const t = new Date(v).getTime();
    return Number.isNaN(t) ? null : t;
  }
  return null;
}

/**
 * Classify a single device's health.
 *
 * @param {object} device   { battery_percent, last_seen, last_sync_at }
 * @param {object} thresholds  { offlineAfterSeconds, staleSyncAfterSeconds, lowBatteryPercent }
 * @param {number} [nowMs]   current time (epoch ms); defaults to Date.now()
 * @returns {{ healthy: boolean, flags: string[], offline: boolean, stale_sync: boolean, low_battery: boolean,
 *            last_seen_age_seconds: number|null, last_sync_age_seconds: number|null }}
 */
function classifyDeviceHealth(device, thresholds, nowMs = Date.now()) {
  const t = thresholds || {};
  const offlineAfter = Number(t.offlineAfterSeconds);
  const staleAfter = Number(t.staleSyncAfterSeconds);
  const lowBattery = Number(t.lowBatteryPercent);

  const lastSeenMs = toMillis(device && device.last_seen);
  // Prefer an explicit sync timestamp; fall back to last_seen so a device that
  // only ever reported telemetry still gets a sensible staleness reading.
  const lastSyncMs =
    toMillis(device && device.last_sync_at) != null
      ? toMillis(device.last_sync_at)
      : lastSeenMs;

  const lastSeenAgeS = lastSeenMs == null ? null : Math.max(0, Math.floor((nowMs - lastSeenMs) / 1000));
  const lastSyncAgeS = lastSyncMs == null ? null : Math.max(0, Math.floor((nowMs - lastSyncMs) / 1000));

  // A never-seen device is treated as OFFLINE (no evidence it is reachable).
  const offline =
    Number.isFinite(offlineAfter) && (lastSeenAgeS == null || lastSeenAgeS > offlineAfter);

  const stale =
    Number.isFinite(staleAfter) && (lastSyncAgeS == null || lastSyncAgeS > staleAfter);

  const battery = device && typeof device.battery_percent === "number" ? device.battery_percent : null;
  const low = Number.isFinite(lowBattery) && battery != null && battery <= lowBattery;

  const flags = [];
  if (offline) flags.push(HEALTH_FLAG.OFFLINE);
  if (stale) flags.push(HEALTH_FLAG.STALE_SYNC);
  if (low) flags.push(HEALTH_FLAG.LOW_BATTERY);

  return {
    healthy: flags.length === 0,
    flags,
    offline,
    stale_sync: stale,
    low_battery: low,
    battery_percent: battery,
    last_seen_age_seconds: lastSeenAgeS,
    last_sync_age_seconds: lastSyncAgeS,
  };
}

/**
 * Classify a list of devices and return only the UNHEALTHY ones with their
 * flags + a roll-up summary count by flag.
 *
 * @param {object[]} devices
 * @param {object} thresholds
 * @param {number} [nowMs]
 * @returns {{ total: number, unhealthy: object[], summary: object }}
 */
function classifyFleet(devices, thresholds, nowMs = Date.now()) {
  const list = Array.isArray(devices) ? devices : [];
  const summary = { offline: 0, stale_sync: 0, low_battery: 0, unhealthy: 0 };
  const unhealthy = [];

  for (const device of list) {
    const health = classifyDeviceHealth(device, thresholds, nowMs);
    if (health.offline) summary.offline += 1;
    if (health.stale_sync) summary.stale_sync += 1;
    if (health.low_battery) summary.low_battery += 1;
    if (!health.healthy) {
      summary.unhealthy += 1;
      unhealthy.push({ device_id: device.device_id, ...health });
    }
  }

  return { total: list.length, unhealthy, summary };
}

module.exports = {
  HEALTH_FLAG,
  classifyDeviceHealth,
  classifyFleet,
};
