// ============================================
// GTM-539 — OTA update resolution (PURE)
// ============================================
// Answers a single question for a device asking "is there an update for me?":
// given the device's current firmware version, its per-device pin/target (if
// any), and the set of FirmwareRelease records, which release (if any) should
// this device be told to install — and what signed-image ref does it fetch?
//
// COMPATIBILITY WITH THE FIRMWARE SIGNED-OTA STORY (B4):
//   The backend NEVER signs or ships the binary here. It only serves a
//   reference: an HTTPS image URL + the target version + an optional digest.
//   The device downloads over HTTPS and Secure Boot v2 verifies the image
//   signature on-device; the firmware's anti-rollback secure-version eFuse is
//   the hard downgrade gate. This module mirrors that intent in orchestration:
//     - it only ever offers a release whose version is NEWER than the device's
//       current version (never a downgrade) UNLESS an admin has explicitly
//       PINNED the device to a specific release (controlled rollback),
//     - it respects each release's `min_version` (a device too old to jump
//       straight to this release is not offered it),
//     - it respects staged/targeted rollout (a release only reaches devices in
//       its cohort / explicit device list, or all devices when fully rolled out).
//
// Everything here is PURE: callers pass plain objects (no Mongoose docs, no DB),
// which is what makes the resolution unit-testable without a live MongoDB.

const { compareSemver, isNewer, gte } = require("./semver");

// Rollout states a release can be in. Only ACTIVE/PARTIAL releases are eligible
// to be offered; DRAFT (not published) and PAUSED/COMPLETED/ROLLED_BACK are not
// auto-offered (a ROLLED_BACK release can still be offered via an explicit pin).
const ROLLOUT_STATE = Object.freeze({
  DRAFT: "draft", // authored, not yet serving
  PAUSED: "paused", // temporarily not serving
  STAGED: "staged", // serving only to its targeted cohort / device list
  ACTIVE: "active", // serving to all eligible devices
  COMPLETED: "completed", // finished; superseded
  ROLLED_BACK: "rolled_back", // withdrawn; only reachable via explicit pin
});

// States from which a release is eligible to be auto-offered to a device.
const SERVABLE_STATES = new Set([ROLLOUT_STATE.STAGED, ROLLOUT_STATE.ACTIVE]);

/**
 * Decide whether a single release targets a given device.
 *
 * - ACTIVE releases target every device (subject to version/min checks).
 * - STAGED releases target only devices in `target_device_ids` OR whose
 *   `cohort` is listed in the release's `target_cohorts`.
 *
 * @param {object} release
 * @param {object} device  { device_id, cohort }
 * @returns {boolean}
 */
function releaseTargetsDevice(release, device) {
  if (!release || !device) return false;
  if (release.rollout_state === ROLLOUT_STATE.ACTIVE) return true;
  if (release.rollout_state !== ROLLOUT_STATE.STAGED) return false;

  const ids = Array.isArray(release.target_device_ids) ? release.target_device_ids : [];
  if (ids.includes(device.device_id)) return true;

  const cohorts = Array.isArray(release.target_cohorts) ? release.target_cohorts : [];
  if (device.cohort && cohorts.includes(device.cohort)) return true;

  return false;
}

/**
 * Shape the public, device-facing response for an offered release. This is the
 * exact reference the device fetches + verifies on its own.
 *
 * @param {object} release
 * @returns {object}
 */
function toUpdateOffer(release) {
  return {
    update_available: true,
    version: release.version,
    // The signed image the device downloads over HTTPS and verifies via Secure
    // Boot v2. We serve the REFERENCE only; we never sign/host the bytes here.
    image_url: release.image_url,
    image_ref: release.image_ref || null,
    // Optional content digest the device MAY cross-check before/after download.
    image_sha256: release.image_sha256 || null,
    min_version: release.min_version || null,
    notes: release.notes || null,
    // True when this offer is an admin-directed downgrade (rollback pin), so the
    // device/operator can tell a rollback from a normal forward update.
    is_rollback: Boolean(release.__isRollback),
  };
}

/**
 * Resolve the update (if any) for a device.
 *
 * Resolution order:
 *   1. PIN — if the device is pinned to a specific release version, that wins
 *      outright (this is how staged targeting to a single unit AND rollback are
 *      expressed). A pin may point to an older version (controlled rollback);
 *      we still only offer it if the device isn't already on it. A pin to a
 *      version the device already runs ⇒ no update.
 *   2. Otherwise pick the HIGHEST-version servable (active/staged-and-targeted)
 *      release that is:
 *        - strictly NEWER than the device's current version, and
 *        - reachable from the device's current version (current >= min_version).
 *
 * @param {object} args
 * @param {object} args.device   { device_id, firmware_version, cohort, pinned_release_version }
 * @param {object[]} args.releases  array of release records (plain objects)
 * @returns {{ update_available: boolean, version?, image_url?, ... }}
 */
function resolveUpdateForDevice({ device, releases }) {
  const current = device && device.firmware_version;
  const all = Array.isArray(releases) ? releases : [];

  // ---- 1. Explicit pin (targeted single-device rollout OR rollback) ----------
  const pinnedVersion = device && device.pinned_release_version;
  if (pinnedVersion) {
    const pinned = all.find((r) => compareSemver(r.version, pinnedVersion) === 0);
    if (!pinned) {
      // Pinned to a version we have no release record for → nothing to serve.
      return { update_available: false, reason: "pinned_release_not_found" };
    }
    // Already running exactly the pinned version → nothing to do.
    if (compareSemver(current, pinned.version) === 0) {
      return { update_available: false, reason: "already_on_pinned" };
    }
    const isRollback = isNewer(current, pinned.version); // current > pinned ⇒ downgrade
    return toUpdateOffer({ ...pinned, __isRollback: isRollback });
  }

  // ---- 2. Best forward update across servable releases -----------------------
  const eligible = all
    .filter((r) => r && SERVABLE_STATES.has(r.rollout_state))
    .filter((r) => releaseTargetsDevice(r, device))
    // Only forward updates: strictly newer than what the device runs.
    .filter((r) => isNewer(r.version, current))
    // Anti-rollback / reachability: the device must already be at or above the
    // release's declared minimum to jump straight to it.
    .filter((r) => !r.min_version || gte(current, r.min_version));

  if (eligible.length === 0) {
    return { update_available: false, reason: "up_to_date" };
  }

  // Highest version wins; tie-break deterministically on most-recently-created.
  eligible.sort((a, b) => {
    const c = compareSemver(b.version, a.version);
    if (c !== 0) return c;
    const at = a.created_at ? new Date(a.created_at).getTime() : 0;
    const bt = b.created_at ? new Date(b.created_at).getTime() : 0;
    return bt - at;
  });

  return toUpdateOffer(eligible[0]);
}

module.exports = {
  ROLLOUT_STATE,
  SERVABLE_STATES,
  releaseTargetsDevice,
  resolveUpdateForDevice,
  toUpdateOffer,
};
