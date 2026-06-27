const express = require('express');
const router = express.Router();
const verifyToken = require('../middleware/verifyUserToken');
const {
    claimDeviceForCaregiver,
    getCaregiver_A_device_summery,
    getAllCaregiverDevices,
    searchDeviceById,
    filterEventsByDateRange
} = require('../controllers/caregiver.controller');

// Assign a caregiver to a device (device owner only)
router.post('/claim-device', verifyToken, claimDeviceForCaregiver);

// Get summary of a specific device (caregiver access)
router.get('/devices/:device_id/summary', verifyToken, getCaregiver_A_device_summery);

// Get all devices assigned to the caregiver
router.get('/devices', verifyToken, getAllCaregiverDevices);

// Search for a device by device_id
router.get('/search/device', verifyToken, searchDeviceById);

// Filter events by date range for a device
router.get('/events/filter/date', verifyToken, filterEventsByDateRange);

module.exports = router;
