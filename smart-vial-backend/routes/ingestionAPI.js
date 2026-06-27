const express = require('express');
const router = express.Router();
const verifyDeviceAuth = require('../middleware/authDevice');
const { updateTelemetry, ingestEvent } = require('../controllers/ingestion.controller');

// Update device telemetry (battery, firmware)
router.post('/telemetry', verifyDeviceAuth, updateTelemetry);

// Ingest event data from devices
router.post('/event', verifyDeviceAuth, ingestEvent);

module.exports = router;
