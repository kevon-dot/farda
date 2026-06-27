const express = require("express");
const router = express.Router();
const verifyToken = require("../middleware/verifyUserToken");
const verifyAdmin = require("../middleware/verifyAdmin");
const {
  listDevices,
  getDevice,
  updateDevice,
  issueCredential,
  rotateCredential,
  revokeCredential,
  createRelease,
  listReleases,
  updateRelease,
  setDevicePin,
  getFleetHealth,
  getDeviceHealth,
} = require("../controllers/registry.controller");

// GTM-539 — Fleet-wide registry / OTA / health. ADMIN-ONLY: every route is
// gated by verifyToken (better-auth session) THEN verifyAdmin (server-side
// allowlist). Admin status is never taken from a client-asserted role/header.
router.use(verifyToken, verifyAdmin);

// ---- Device registry -------------------------------------------------------
router.get("/devices", listDevices);
router.get("/devices/:device_id", getDevice);
router.patch("/devices/:device_id", updateDevice);
router.get("/devices/:device_id/health", getDeviceHealth);

// ---- Per-device credential lifecycle (A3) ----------------------------------
router.post("/devices/:device_id/credential/issue", issueCredential);
router.post("/devices/:device_id/credential/rotate", rotateCredential);
router.post("/devices/:device_id/credential/revoke", revokeCredential);

// ---- OTA orchestration -----------------------------------------------------
router.get("/firmware-releases", listReleases);
router.post("/firmware-releases", createRelease);
router.patch("/firmware-releases/:version", updateRelease);
// Per-device OTA pin (single-device staged rollout AND rollback to a prior).
router.put("/devices/:device_id/ota-pin", setDevicePin);

// ---- Fleet health ----------------------------------------------------------
router.get("/fleet/health", getFleetHealth);

module.exports = router;
