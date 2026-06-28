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
  ingestDoseEventMicrostructure
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
