const express = require("express");
const router = express.Router();
const verifyToken = require("../middleware/verifyUserToken");
const {
  saveUser,
  claimDevice,
  getUserDevices,
  getADeviceEvents,
  getAllDevicesEvents,
  searchDeviceEventsByTimeRange,
  removeClaimedDevice,
  deleteDeviceEvents,
  deleteCaregiverAccessToDevice,
  ingestUserDeviceEvent,
  ingestDoseEventMicrostructure,
  recordEmaResponse,
  recordPillCountCheckpoint,
  getDoseDetectionMetrics
} = require("../controllers/app.api.controller");

// Save user to database
router.post("/save", verifyToken, saveUser);

// Claim device
router.post("/claim", verifyToken, claimDevice);

// Get all devices for a user
router.get("/devices", verifyToken, getUserDevices);

// Get single device events
router.get("/devices/:device_id/events", verifyToken, getADeviceEvents);

// GTM-514 — user-bearer dose-event ingest relay. The mobile app drains its
// BLE-buffered events here over the user's better-auth session; the device must
// be claimed by that session user. Coexists with the firmware HMAC ingest path.
router.post("/devices/:device_id/events/ingest", verifyToken, ingestUserDeviceEvent);

// GTM-519 — dose-event microstructure capture. Records one full dose interaction
// (reminder → unlock → cap open → weigh → cap close → sync) as a typed, ordered,
// tokenization-ready, PHI-free DoseEvent. Server-authoritative ordering; the
// device must be claimed by the session user (IDOR-guarded).
router.post(
  "/devices/:device_id/dose-events/ingest",
  verifyToken,
  ingestDoseEventMicrostructure
);

// GTM-521 — ground-truth validation substream. Self-report EMA + manual
// pill-count checkpoints are the supervised LABEL we validate device
// dose-detection against. All deny-by-default (verifyToken) + IDOR-guarded (the
// device must be claimed by the session user); subject ids are server-derived.
//
// Record an EMA self-report ("did you just take your dose?" yes/no/unsure).
router.post(
  "/devices/:device_id/ema-responses",
  verifyToken,
  recordEmaResponse
);
// Record a manual pill-count checkpoint (manual vs device-inferred remaining).
router.post(
  "/devices/:device_id/pill-count-checkpoints",
  verifyToken,
  recordPillCountCheckpoint
);
// Read computed dose-detection sensitivity/specificity over a window (self).
router.get(
  "/devices/:device_id/dose-detection-metrics",
  verifyToken,
  getDoseDetectionMetrics
);

// Get all events from all user's devices
router.get("/events/all", verifyToken, getAllDevicesEvents);

// Search device events by time range
router.get("/devices/:device_id/events/search", verifyToken, searchDeviceEventsByTimeRange);

// Remove claimed device (unclaim)
router.delete("/devices/:device_id/unclaim", verifyToken, removeClaimedDevice);

// Delete all events for a device
router.delete("/devices/:device_id/events", verifyToken, deleteDeviceEvents);

// Delete caregiver access to a device
router.delete("/devices/:device_id/caregiver", verifyToken, deleteCaregiverAccessToDevice);

module.exports = router;
