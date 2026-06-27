// ============================================
// GTM-539 — Device registry + OTA orchestration + fleet health
// ============================================
// Admin-only (fleet-wide) registry/OTA/health handlers, plus the device-facing
// "is there an update for me?" handler that runs on the authenticated ingestion
// path. Authorization is enforced by the routes (verifyAdmin / verifyDeviceAuth);
// these handlers assume the caller is already authorized.
//
// PHI: admin responses expose only device↔user binding ids via
// Device.toRegistry() — never patient PHI or the device secret.

const Device = require("../models/Device");
const FirmwareRelease = require("../models/FirmwareRelease");
const config = require("../config/config");
const { validateDeviceId } = require("../utils/eventValidation");
const { isValidSemver } = require("../utils/semver");
const { resolveUpdateForDevice, ROLLOUT_STATE } = require("../utils/otaResolution");
const { classifyDeviceHealth, classifyFleet } = require("../utils/fleetHealth");

const ROLLOUT_STATES = Object.values(ROLLOUT_STATE);

// ---------------------------------------------------------------------------
// Registry — list / get / update
// ---------------------------------------------------------------------------

/**
 * GET /api/admin/devices
 * List devices with optional filters: state (active|inactive|revoked|claimed|
 * unclaimed), firmware (exact version), online (true|false). Paginated.
 */
const listDevices = async (req, res) => {
  try {
    const { state, firmware, online, cohort, limit, skip } = req.query || {};
    const query = {};

    switch (state) {
      case "active":
        query.isActive = true;
        break;
      case "inactive":
        query.isActive = false;
        break;
      case "revoked":
        query.revoked = true;
        break;
      case "claimed":
        query.claimed = true;
        break;
      case "unclaimed":
        query.claimed = false;
        break;
      case undefined:
      case "":
      case "all":
        break;
      default:
        return res.status(400).json({ error: `Unknown state filter '${state}'` });
    }

    if (firmware !== undefined && firmware !== "") {
      if (typeof firmware !== "string") {
        return res.status(400).json({ error: "firmware filter must be a string" });
      }
      query.firmware_version = firmware;
    }
    if (cohort !== undefined && cohort !== "") {
      if (typeof cohort !== "string") {
        return res.status(400).json({ error: "cohort filter must be a string" });
      }
      query.cohort = cohort;
    }

    const lim = Math.min(Math.max(parseInt(limit, 10) || 50, 1), 200);
    const off = Math.max(parseInt(skip, 10) || 0, 0);

    const devices = await Device.find(query)
      .sort({ last_seen: -1 })
      .skip(off)
      .limit(lim);

    let records = devices.map((d) => d.toRegistry());

    // `online` is a derived property, so filter it post-query.
    if (online === "true") {
      records = records.filter((r) => r.is_online === true);
    } else if (online === "false") {
      records = records.filter((r) => r.is_online === false);
    }

    return res.status(200).json({
      devices: records,
      count: records.length,
      limit: lim,
      skip: off,
    });
  } catch (err) {
    console.error("Error listing devices:", err.message);
    return res.status(500).json({ error: "Server error listing devices" });
  }
};

/**
 * GET /api/admin/devices/:device_id
 * Full registry record for one device.
 */
const getDevice = async (req, res) => {
  try {
    const idCheck = validateDeviceId(req.params.device_id);
    if (!idCheck.ok) {
      return res.status(400).json({ error: `Bad Request: ${idCheck.error}` });
    }
    const device = await Device.findOne({ device_id: idCheck.value });
    if (!device) {
      return res.status(404).json({ error: "Device not found" });
    }
    return res.status(200).json({ device: device.toRegistry() });
  } catch (err) {
    console.error("Error fetching device:", err.message);
    return res.status(500).json({ error: "Server error fetching device" });
  }
};

/**
 * PATCH /api/admin/devices/:device_id
 * Update registry metadata: device_name, cohort, isActive, and a calibration
 * record (which bumps calibration.version). Does NOT touch credentials, claim
 * state, or OTA pin (those have dedicated endpoints).
 */
const updateDevice = async (req, res) => {
  try {
    const idCheck = validateDeviceId(req.params.device_id);
    if (!idCheck.ok) {
      return res.status(400).json({ error: `Bad Request: ${idCheck.error}` });
    }
    const device = await Device.findOne({ device_id: idCheck.value });
    if (!device) {
      return res.status(404).json({ error: "Device not found" });
    }

    const { device_name, cohort, isActive, calibration } = req.body || {};

    if (device_name !== undefined) {
      if (typeof device_name !== "string" || device_name.trim() === "") {
        return res.status(400).json({ error: "device_name must be a non-empty string" });
      }
      device.device_name = device_name.trim();
    }
    if (cohort !== undefined) {
      if (cohort !== null && typeof cohort !== "string") {
        return res.status(400).json({ error: "cohort must be a string or null" });
      }
      device.cohort = cohort || null;
    }
    if (isActive !== undefined) {
      if (typeof isActive !== "boolean") {
        return res.status(400).json({ error: "isActive must be a boolean" });
      }
      device.isActive = isActive;
    }
    if (calibration !== undefined) {
      if (calibration === null || typeof calibration !== "object" || Array.isArray(calibration)) {
        return res.status(400).json({ error: "calibration must be an object" });
      }
      const prevVersion =
        device.calibration && device.calibration.version ? device.calibration.version : 0;
      device.calibration = {
        version: prevVersion + 1,
        data: calibration.data !== undefined ? calibration.data : calibration,
        calibrated_at: new Date(),
        calibrated_by: req.user_id || null,
      };
    }

    await device.save();
    return res.status(200).json({ device: device.toRegistry() });
  } catch (err) {
    console.error("Error updating device:", err.message);
    return res.status(500).json({ error: "Server error updating device" });
  }
};

// ---------------------------------------------------------------------------
// Per-device credential lifecycle (builds on A3's model methods — no crypto here)
// ---------------------------------------------------------------------------

/**
 * POST /api/admin/devices/:device_id/credential/issue
 * Issue a fresh credential for a device (provisioning). Returns the plaintext
 * secret EXACTLY ONCE. Idempotency note: issuing again rotates.
 */
const issueCredential = async (req, res) => {
  try {
    const idCheck = validateDeviceId(req.params.device_id);
    if (!idCheck.ok) {
      return res.status(400).json({ error: `Bad Request: ${idCheck.error}` });
    }
    // Select the credential so the model's issue path sees prior version.
    const device = await Device.findOne({ device_id: idCheck.value }).select("+credential");
    if (!device) {
      return res.status(404).json({ error: "Device not found" });
    }
    const secret = device.issueCredential(); // A3 model method (does the crypto)
    await device.save();
    return res.status(201).json({
      device_id: device.device_id,
      // Delivered ONCE; never recoverable in plaintext afterwards.
      secret,
      credential_version: device.credential.version,
      issued_at: device.credential.issued_at,
    });
  } catch (err) {
    console.error("Error issuing credential:", err.message);
    return res.status(500).json({ error: "Server error issuing credential" });
  }
};

/**
 * POST /api/admin/devices/:device_id/credential/rotate
 * Rotate the credential (re-issue). Returns the new secret ONCE.
 */
const rotateCredential = async (req, res) => {
  try {
    const idCheck = validateDeviceId(req.params.device_id);
    if (!idCheck.ok) {
      return res.status(400).json({ error: `Bad Request: ${idCheck.error}` });
    }
    const device = await Device.findOne({ device_id: idCheck.value }).select("+credential");
    if (!device) {
      return res.status(404).json({ error: "Device not found" });
    }
    const secret = device.rotateCredential();
    await device.save();
    return res.status(200).json({
      device_id: device.device_id,
      secret,
      credential_version: device.credential.version,
      issued_at: device.credential.issued_at,
    });
  } catch (err) {
    console.error("Error rotating credential:", err.message);
    return res.status(500).json({ error: "Server error rotating credential" });
  }
};

/**
 * POST /api/admin/devices/:device_id/credential/revoke
 * Revoke the credential. The device can no longer authenticate until re-issued.
 */
const revokeCredential = async (req, res) => {
  try {
    const idCheck = validateDeviceId(req.params.device_id);
    if (!idCheck.ok) {
      return res.status(400).json({ error: `Bad Request: ${idCheck.error}` });
    }
    const device = await Device.findOne({ device_id: idCheck.value }).select("+credential");
    if (!device) {
      return res.status(404).json({ error: "Device not found" });
    }
    device.revokeCredential();
    await device.save();
    return res.status(200).json({
      device_id: device.device_id,
      revoked: device.revoked,
      revoked_at: device.revoked_at,
    });
  } catch (err) {
    console.error("Error revoking credential:", err.message);
    return res.status(500).json({ error: "Server error revoking credential" });
  }
};

// ---------------------------------------------------------------------------
// OTA orchestration — releases CRUD + per-device pin + device-facing check
// ---------------------------------------------------------------------------

/**
 * POST /api/admin/firmware-releases
 * Create a firmware release (DRAFT by default). Admin supplies the signed image
 * REFERENCE (https url + optional ref/digest); the server never signs/hosts it.
 */
const createRelease = async (req, res) => {
  try {
    const {
      version,
      image_url,
      image_ref,
      image_sha256,
      min_version,
      rollout_state,
      target_device_ids,
      target_cohorts,
      notes,
    } = req.body || {};

    if (!version || !isValidSemver(version)) {
      return res.status(400).json({ error: "version must be a valid MAJOR.MINOR.PATCH string" });
    }
    if (!image_url || typeof image_url !== "string" || !/^https:\/\//i.test(image_url)) {
      return res.status(400).json({ error: "image_url must be an https:// URL" });
    }
    if (min_version !== undefined && min_version !== null && !isValidSemver(min_version)) {
      return res.status(400).json({ error: "min_version must be a valid MAJOR.MINOR.PATCH string" });
    }
    if (rollout_state !== undefined && !ROLLOUT_STATES.includes(rollout_state)) {
      return res
        .status(400)
        .json({ error: `rollout_state must be one of: ${ROLLOUT_STATES.join(", ")}` });
    }

    const existing = await FirmwareRelease.findOne({ version });
    if (existing) {
      return res.status(409).json({ error: `Release ${version} already exists` });
    }

    const release = new FirmwareRelease({
      version,
      image_url,
      image_ref: image_ref || null,
      image_sha256: image_sha256 || null,
      min_version: min_version || null,
      rollout_state: rollout_state || ROLLOUT_STATE.DRAFT,
      target_device_ids: Array.isArray(target_device_ids) ? target_device_ids : [],
      target_cohorts: Array.isArray(target_cohorts) ? target_cohorts : [],
      notes: notes || null,
      created_by: req.user_id || null,
      updated_by: req.user_id || null,
    });
    await release.save();
    return res.status(201).json({ release: release.toPublic() });
  } catch (err) {
    if (err.code === 11000) {
      return res.status(409).json({ error: "Release version already exists" });
    }
    if (err.name === "ValidationError") {
      return res.status(400).json({ error: err.message });
    }
    console.error("Error creating release:", err.message);
    return res.status(500).json({ error: "Server error creating release" });
  }
};

/** GET /api/admin/firmware-releases — list releases (optionally by state). */
const listReleases = async (req, res) => {
  try {
    const { state } = req.query || {};
    const query = {};
    if (state !== undefined && state !== "" && state !== "all") {
      if (!ROLLOUT_STATES.includes(state)) {
        return res.status(400).json({ error: `Unknown rollout_state '${state}'` });
      }
      query.rollout_state = state;
    }
    const releases = await FirmwareRelease.find(query).sort({ createdAt: -1 });
    return res.status(200).json({
      releases: releases.map((r) => r.toPublic()),
      count: releases.length,
    });
  } catch (err) {
    console.error("Error listing releases:", err.message);
    return res.status(500).json({ error: "Server error listing releases" });
  }
};

/**
 * PATCH /api/admin/firmware-releases/:version
 * Update rollout state / targeting / notes. Used to publish (draft → active/
 * staged), pause, complete, or mark a bad release `rolled_back`.
 */
const updateRelease = async (req, res) => {
  try {
    const release = await FirmwareRelease.findOne({ version: String(req.params.version) });
    if (!release) {
      return res.status(404).json({ error: "Release not found" });
    }
    const { rollout_state, target_device_ids, target_cohorts, min_version, notes } = req.body || {};

    if (rollout_state !== undefined) {
      if (!ROLLOUT_STATES.includes(rollout_state)) {
        return res
          .status(400)
          .json({ error: `rollout_state must be one of: ${ROLLOUT_STATES.join(", ")}` });
      }
      release.rollout_state = rollout_state;
    }
    if (target_device_ids !== undefined) {
      if (!Array.isArray(target_device_ids)) {
        return res.status(400).json({ error: "target_device_ids must be an array" });
      }
      release.target_device_ids = target_device_ids;
    }
    if (target_cohorts !== undefined) {
      if (!Array.isArray(target_cohorts)) {
        return res.status(400).json({ error: "target_cohorts must be an array" });
      }
      release.target_cohorts = target_cohorts;
    }
    if (min_version !== undefined) {
      if (min_version !== null && !isValidSemver(min_version)) {
        return res.status(400).json({ error: "min_version must be a valid version or null" });
      }
      release.min_version = min_version || null;
    }
    if (notes !== undefined) {
      release.notes = notes || null;
    }
    release.updated_by = req.user_id || null;
    await release.save();
    return res.status(200).json({ release: release.toPublic() });
  } catch (err) {
    if (err.name === "ValidationError") {
      return res.status(400).json({ error: err.message });
    }
    console.error("Error updating release:", err.message);
    return res.status(500).json({ error: "Server error updating release" });
  }
};

/**
 * PUT /api/admin/devices/:device_id/ota-pin
 * Pin a device to a specific release version (single-device staged rollout OR
 * rollback to a prior version). Body { version } — null/empty clears the pin.
 */
const setDevicePin = async (req, res) => {
  try {
    const idCheck = validateDeviceId(req.params.device_id);
    if (!idCheck.ok) {
      return res.status(400).json({ error: `Bad Request: ${idCheck.error}` });
    }
    const device = await Device.findOne({ device_id: idCheck.value });
    if (!device) {
      return res.status(404).json({ error: "Device not found" });
    }
    const { version } = req.body || {};
    if (version === null || version === undefined || version === "") {
      device.pinned_release_version = null;
      await device.save();
      return res.status(200).json({ device_id: device.device_id, pinned_release_version: null });
    }
    if (!isValidSemver(version)) {
      return res.status(400).json({ error: "version must be a valid MAJOR.MINOR.PATCH string" });
    }
    const release = await FirmwareRelease.findOne({ version });
    if (!release) {
      return res.status(404).json({ error: `No firmware release ${version} to pin to` });
    }
    device.pinned_release_version = version;
    await device.save();
    return res.status(200).json({
      device_id: device.device_id,
      pinned_release_version: device.pinned_release_version,
    });
  } catch (err) {
    console.error("Error pinning device:", err.message);
    return res.status(500).json({ error: "Server error pinning device" });
  }
};

/**
 * GET /api/ingest/ota/check  (DEVICE-FACING, behind verifyDeviceAuth)
 * The authenticated device asks "is there an update for me?". Resolves against
 * its current firmware version, its pin, and all releases, then returns the
 * signed-image REFERENCE for the device to download + verify on its own.
 *
 * req.device is set by verifyDeviceAuth.
 */
const checkForUpdate = async (req, res) => {
  try {
    const device = req.device;
    if (!device) {
      return res.status(401).json({ error: "Device authentication required" });
    }
    // A device may report its current version in the signed body so a
    // freshly-booted unit gets an accurate answer before its telemetry lands;
    // fall back to the stored registry value.
    const reported = req.body && typeof req.body.firmware_version === "string"
      ? req.body.firmware_version
      : null;
    const current = reported || device.firmware_version;

    const releases = await FirmwareRelease.find({});
    const result = resolveUpdateForDevice({
      device: {
        device_id: device.device_id,
        firmware_version: current,
        cohort: device.cohort || null,
        pinned_release_version: device.pinned_release_version || null,
      },
      releases: releases.map((r) => ({
        version: r.version,
        image_url: r.image_url,
        image_ref: r.image_ref,
        image_sha256: r.image_sha256,
        min_version: r.min_version,
        rollout_state: r.rollout_state,
        target_device_ids: r.target_device_ids,
        target_cohorts: r.target_cohorts,
        created_at: r.createdAt,
      })),
    });

    return res.status(200).json(result);
  } catch (err) {
    console.error("Error checking for update:", err.message);
    return res.status(500).json({ error: "Server error checking for update" });
  }
};

// ---------------------------------------------------------------------------
// Fleet health
// ---------------------------------------------------------------------------

/**
 * GET /api/admin/fleet/health
 * Returns unhealthy devices (offline / stale-sync / low-battery) + a summary,
 * derived from last_seen / last_sync_at / battery_percent against config
 * thresholds.
 */
const getFleetHealth = async (req, res) => {
  try {
    // Consider active devices by default; ?include_inactive=true widens it.
    const query =
      req.query && req.query.include_inactive === "true" ? {} : { isActive: true };
    const devices = await Device.find(query);

    const plain = devices.map((d) => ({
      device_id: d.device_id,
      battery_percent: d.battery_percent,
      last_seen: d.last_seen,
      last_sync_at: d.last_sync_at,
    }));

    const report = classifyFleet(plain, config.fleet, Date.now());
    return res.status(200).json({
      thresholds: config.fleet,
      total: report.total,
      summary: report.summary,
      unhealthy: report.unhealthy,
    });
  } catch (err) {
    console.error("Error computing fleet health:", err.message);
    return res.status(500).json({ error: "Server error computing fleet health" });
  }
};

/**
 * GET /api/admin/devices/:device_id/health
 * Single-device health classification.
 */
const getDeviceHealth = async (req, res) => {
  try {
    const idCheck = validateDeviceId(req.params.device_id);
    if (!idCheck.ok) {
      return res.status(400).json({ error: `Bad Request: ${idCheck.error}` });
    }
    const device = await Device.findOne({ device_id: idCheck.value });
    if (!device) {
      return res.status(404).json({ error: "Device not found" });
    }
    const health = classifyDeviceHealth(
      {
        device_id: device.device_id,
        battery_percent: device.battery_percent,
        last_seen: device.last_seen,
        last_sync_at: device.last_sync_at,
      },
      config.fleet,
      Date.now()
    );
    return res.status(200).json({ device_id: device.device_id, thresholds: config.fleet, health });
  } catch (err) {
    console.error("Error computing device health:", err.message);
    return res.status(500).json({ error: "Server error computing device health" });
  }
};

module.exports = {
  // registry
  listDevices,
  getDevice,
  updateDevice,
  // credentials
  issueCredential,
  rotateCredential,
  revokeCredential,
  // OTA
  createRelease,
  listReleases,
  updateRelease,
  setDevicePin,
  checkForUpdate,
  // fleet health
  getFleetHealth,
  getDeviceHealth,
};
