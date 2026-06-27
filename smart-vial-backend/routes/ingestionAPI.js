const express = require('express');
const router = express.Router();
const verifyDeviceAuth = require('../middleware/authDevice');
const { updateTelemetry, ingestEvent } = require('../controllers/ingestion.controller');
const { checkForUpdate } = require('../controllers/registry.controller');

// Update device telemetry (battery, firmware)
router.post('/telemetry', verifyDeviceAuth, updateTelemetry);

// Ingest event data from devices
router.post('/event', verifyDeviceAuth, ingestEvent);

// GTM-539 — Device-facing OTA check ("is there an update for me?"). Same
// per-device HMAC auth as ingestion; returns the signed-image REFERENCE for the
// device to download over HTTPS and verify on-device (Secure Boot v2).
router.post('/ota/check', verifyDeviceAuth, checkForUpdate);

module.exports = router;
