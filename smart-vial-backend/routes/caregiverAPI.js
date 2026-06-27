const express = require('express');
const router = express.Router();
const verifyToken = require('../middleware/verifyUserToken');
const {
    claimDeviceForCaregiver,
    acceptCaregiverGrant,
    revokeCaregiverGrant,
    listCaregiverGrants,
    getCaregiver_A_device_summery,
    getAllCaregiverDevices,
    searchDeviceById,
    filterEventsByDateRange
} = require('../controllers/caregiver.controller');

// Two-sided consent flow (GTM-507 follow-up):
//   1. Owner INVITES a caregiver — creates a `pending` grant (no access yet).
//      Kept on the legacy /claim-device path for backwards compatibility.
router.post('/claim-device', verifyToken, claimDeviceForCaregiver);
//   2. Invited CAREGIVER ACCEPTS — `pending → accepted`, access granted.
router.post('/grants/:id/accept', verifyToken, acceptCaregiverGrant);
//   3. Owner OR caregiver REVOKES — `* → revoked`, access cut.
router.post('/grants/:id/revoke', verifyToken, revokeCaregiverGrant);

// List the session user's caregiver grants (server-authoritative, PHI-free):
//   as a caregiver (my invites inbox / patients I look after) and/or as an
//   owner (relationships I created). Filterable by ?status= and ?role=.
router.get('/grants', verifyToken, listCaregiverGrants);

// Get summary of a specific device (caregiver access)
router.get('/devices/:device_id/summary', verifyToken, getCaregiver_A_device_summery);

// Get all devices assigned to the caregiver
router.get('/devices', verifyToken, getAllCaregiverDevices);

// Search for a device by device_id
router.get('/search/device', verifyToken, searchDeviceById);

// Filter events by date range for a device
router.get('/events/filter/date', verifyToken, filterEventsByDateRange);

module.exports = router;
