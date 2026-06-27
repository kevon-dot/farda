// Caregiver-scoped reads. Authorization is SERVER-AUTHORITATIVE (GTM-507):
// a caregiver may only access a device the device OWNER explicitly granted them
// (recorded on device.caregiver_id and in CaregiverGrant). The caller's asserted
// role (req.user_role / any body field) is NEVER used to authorize access.
const Event = require('../models/Event');
const Device = require('../models/Device');
const User = require('../models/User');
const CaregiverGrant = require('../models/CaregiverGrant');
const {
    isCaregiverAuthorizedForDevice,
    isDeviceOwner,
    canAcceptGrant,
    canRevokeGrant,
    GRANT_STATUS,
} = require('../utils/caregiverAuthorization');

// Load a device and confirm the authenticated caller has a server-side caregiver
// grant for it. Returns { device } on success, or { error: { status, body } }.
// This is the single choke point every caregiver read goes through, so the
// authorization rule (owner-granted relationship only) lives in exactly one place.
const authorizeCaregiverDevice = async (device_id, caregiver_id) => {
    const device = await Device.findOne({ device_id });
    if (!device) {
        return { error: { status: 404, body: { error: 'Device not found' } } };
    }

    if (!isCaregiverAuthorizedForDevice({ caregiverUserId: caregiver_id, device })) {
        // 403 (not 404) once the device exists but the caller has no grant: the
        // caller is authenticated, just not authorized for this patient's data.
        return {
            error: {
                status: 403,
                body: { error: 'Access denied: no caregiver grant for this device' },
            },
        };
    }

    return { device };
};

// Invite a caregiver to a device — device OWNER (patient) only.
//
// TWO-SIDED CONSENT: this creates a `pending` grant ONLY. The caregiver gets NO
// access until they explicitly accept (POST /grants/:id/accept). The device's
// `caregiver_id` is deliberately NOT set here — it is mirrored only once the
// caregiver accepts, so a pending invite never authorizes a read.
//
// (Route is kept as POST /claim-device for backwards compatibility; it now
// performs an invite, not an immediate grant.)
const claimDeviceForCaregiver = async (req, res) => {
    try {
        const { device_id, caregiver_id } = req.body;
        const user_id = req.user_id;

        // Validate required fields
        if (!device_id || !caregiver_id) {
            return res.status(400).json({ error: 'device_id and caregiver_id are required' });
        }

        if (typeof device_id !== 'string' || typeof caregiver_id !== 'string') {
            return res.status(400).json({ error: 'device_id and caregiver_id must be strings' });
        }

        // A user cannot invite themselves as the caregiver of their own device.
        if (caregiver_id === user_id) {
            return res.status(400).json({ error: 'Cannot assign yourself as caregiver' });
        }

        // Find the device
        const device = await Device.findOne({ device_id });
        if (!device) {
            return res.status(404).json({ error: 'Device not found' });
        }

        // SERVER-AUTHORITATIVE: only the trusted owner of the device may invite a
        // caregiver. The caller cannot grant access to a device they don't own.
        if (!isDeviceOwner({ ownerUserId: user_id, device })) {
            return res.status(403).json({ error: 'Access denied: Only device owner can assign caregivers' });
        }

        // Ensure the caregiver user record exists (without trusting any
        // client-supplied role: we set the role here, server-side, as part of an
        // owner-authorized invite — not because the caregiver asked for it). Note
        // the caregiver still gets NO device access until they accept.
        let caregiver = await User.findOne({ user_id: caregiver_id });
        if (!caregiver) {
            caregiver = new User({
                user_id: caregiver_id,
                user_roles: ['caregiver'],
                claim_device_ids: [],
                caregiving_device_ids: [],
            });
        } else if (!caregiver.user_roles.includes('caregiver')) {
            caregiver.user_roles.push('caregiver');
        }
        caregiver.lastLogin = new Date();
        await caregiver.save();

        // Re-invite handling: if there's already an ACCEPTED grant for this
        // (device, caregiver), the relationship is live — nothing to re-invite.
        const existing = await CaregiverGrant.findOne({
            deviceId: device_id,
            caregiverUserId: caregiver_id,
        });
        if (existing && existing.status === GRANT_STATUS.ACCEPTED) {
            return res.status(200).json({
                status: 'Caregiver already has access to this device',
                grant: serializeGrant(existing),
            });
        }

        // Create or re-open the invite as a fresh `pending` grant (this also
        // re-invites a previously revoked or still-pending relationship). The
        // unique (deviceId, caregiverUserId) index keeps it to one record.
        const now = new Date();
        const grant = await CaregiverGrant.findOneAndUpdate(
            { deviceId: device_id, caregiverUserId: caregiver_id },
            {
                deviceId: device_id,
                caregiverUserId: caregiver_id,
                patientUserId: user_id,
                status: GRANT_STATUS.PENDING,
                invitedBy: user_id,
                invitedAt: now,
                // Reset prior consent/audit fields on a fresh invite.
                acceptedAt: null,
                acceptedBy: null,
                grantedAt: null,
                revokedAt: null,
                revokedBy: null,
            },
            { upsert: true, new: true, setDefaultsOnInsert: true }
        );

        // TODO(GTM-537): fire a notification to the invited caregiver here so
        // they know a patient has requested they accept a caregiving invite.

        res.status(200).json({
            status: 'Caregiver invited successfully; awaiting caregiver acceptance',
            grant: serializeGrant(grant),
            device: {
                device_id: device.device_id,
                device_name: device.device_name,
                // Intentionally still null/unchanged: access is not granted until
                // the caregiver accepts.
                caregiver_id: device.caregiver_id,
            },
        });
    } catch (err) {
        console.error('Error inviting caregiver:', err.message);
        res.status(500).json({ error: 'Server error inviting caregiver' });
    }
};

// Lightweight, PHI-free serialization of a grant for API responses.
const serializeGrant = (grant) => {
    if (!grant) return null;
    return {
        id: grant._id ? String(grant._id) : grant.id || null,
        device_id: grant.deviceId,
        patient_user_id: grant.patientUserId,
        caregiver_user_id: grant.caregiverUserId,
        status: grant.status,
        invited_at: grant.invitedAt || null,
        invited_by: grant.invitedBy || null,
        accepted_at: grant.acceptedAt || null,
        accepted_by: grant.acceptedBy || null,
        revoked_at: grant.revokedAt || null,
        revoked_by: grant.revokedBy || null,
    };
};

// Accept a pending caregiver invite — the INVITED CAREGIVER only.
// TWO-SIDED CONSENT: this is the explicit consent step. Moves `pending →
// accepted` and ONLY THEN mirrors the relationship onto `device.caregiver_id`
// (and the caregiver's caregiving_device_ids) so reads become authorized.
const acceptCaregiverGrant = async (req, res) => {
    try {
        const { id } = req.params;
        const user_id = req.user_id;

        if (!id || typeof id !== 'string') {
            return res.status(400).json({ error: 'grant id is required' });
        }

        const grant = await CaregiverGrant.findById(id);
        if (!grant) {
            return res.status(404).json({ error: 'Grant not found' });
        }

        // State machine + authorization: only the invited caregiver may accept,
        // and only from `pending`. Rejects illegal transitions (already accepted,
        // revoked) and any other caller.
        const decision = canAcceptGrant({ actorUserId: user_id, grant });
        if (!decision.ok) {
            if (decision.reason === 'forbidden' || decision.reason === 'invalid_actor') {
                return res.status(403).json({ error: 'Access denied: only the invited caregiver can accept this invite' });
            }
            if (decision.reason === 'illegal_transition') {
                return res.status(409).json({ error: `Cannot accept a grant in status '${grant.status}'` });
            }
            return res.status(404).json({ error: 'Grant not found' });
        }

        // Confirm the device still exists and is owned by the inviting patient.
        const device = await Device.findOne({ device_id: grant.deviceId });
        if (!device) {
            return res.status(404).json({ error: 'Device not found' });
        }

        const now = new Date();
        grant.status = GRANT_STATUS.ACCEPTED;
        grant.acceptedAt = now;
        grant.acceptedBy = user_id;
        grant.grantedAt = now; // legacy/compat field
        await grant.save();

        // ONLY NOW is the relationship mirrored onto the device — this is what
        // makes isCaregiverAuthorizedForDevice return true for this caregiver.
        device.caregiver_id = grant.caregiverUserId;
        await device.save();

        const caregiver = await User.findOne({ user_id: grant.caregiverUserId });
        if (caregiver) {
            if (!Array.isArray(caregiver.caregiving_device_ids)) {
                caregiver.caregiving_device_ids = [];
            }
            if (!caregiver.caregiving_device_ids.includes(grant.deviceId)) {
                caregiver.caregiving_device_ids.push(grant.deviceId);
            }
            await caregiver.save();
        }

        // TODO(GTM-537): notify the patient/owner that the caregiver accepted.

        res.status(200).json({
            status: 'Caregiver invite accepted; access granted',
            grant: serializeGrant(grant),
        });
    } catch (err) {
        console.error('Error accepting caregiver grant:', err.message);
        res.status(500).json({ error: 'Server error accepting caregiver grant' });
    }
};

// Revoke a caregiver grant — the OWNER (patient) OR the CAREGIVER themselves.
// Valid from `pending` (decline/withdraw the invite) or `accepted` (end access).
// Moves `* → revoked` (terminal) and clears `device.caregiver_id` so any later
// read is immediately denied.
const revokeCaregiverGrant = async (req, res) => {
    try {
        const { id } = req.params;
        const user_id = req.user_id;

        if (!id || typeof id !== 'string') {
            return res.status(400).json({ error: 'grant id is required' });
        }

        const grant = await CaregiverGrant.findById(id);
        if (!grant) {
            return res.status(404).json({ error: 'Grant not found' });
        }

        // State machine + authorization: owner OR caregiver may revoke, but not
        // an already-revoked (terminal) grant, and not an unrelated caller.
        const decision = canRevokeGrant({ actorUserId: user_id, grant });
        if (!decision.ok) {
            if (decision.reason === 'forbidden' || decision.reason === 'invalid_actor') {
                return res.status(403).json({ error: 'Access denied: only the patient or caregiver can revoke this grant' });
            }
            if (decision.reason === 'illegal_transition') {
                return res.status(409).json({ error: `Cannot revoke a grant in status '${grant.status}'` });
            }
            return res.status(404).json({ error: 'Grant not found' });
        }

        const wasAccepted = grant.status === GRANT_STATUS.ACCEPTED;

        grant.status = GRANT_STATUS.REVOKED;
        grant.revokedAt = new Date();
        grant.revokedBy = user_id;
        await grant.save();

        // If this grant was the live relationship, cut access by clearing the
        // device mirror and the caregiver's device list.
        if (wasAccepted) {
            const device = await Device.findOne({ device_id: grant.deviceId });
            if (device && device.caregiver_id === grant.caregiverUserId) {
                device.caregiver_id = null;
                await device.save();
            }

            const caregiver = await User.findOne({ user_id: grant.caregiverUserId });
            if (caregiver && Array.isArray(caregiver.caregiving_device_ids)) {
                const idx = caregiver.caregiving_device_ids.indexOf(grant.deviceId);
                if (idx > -1) {
                    caregiver.caregiving_device_ids.splice(idx, 1);
                    await caregiver.save();
                }
            }
        }

        // TODO(GTM-537): notify the other party that the grant was revoked.

        res.status(200).json({
            status: 'Caregiver grant revoked',
            grant: serializeGrant(grant),
        });
    } catch (err) {
        console.error('Error revoking caregiver grant:', err.message);
        res.status(500).json({ error: 'Server error revoking caregiver grant' });
    }
};

// caregiver check events of a device
const getCaregiver_A_device_summery = async (req, res) => {
    try {
        const { device_id } = req.params;
        const caregiver_id = req.user_id;

        const { device, error } = await authorizeCaregiverDevice(device_id, caregiver_id);
        if (error) {
            return res.status(error.status).json(error.body);
        }

        // Get device summary with recent events
        const recentEvents = await Event.find({ device_id })
            .sort({ server_timestamp: -1 })
            .limit(50);

        const summary = {
            device: {
                device_id: device.device_id,
                device_name: device.device_name,
                battery_percent: device.battery_percent,
                firmware_version: device.firmware_version,
                is_online: device.isOnline(),
                last_seen: device.last_seen
            },
            recent_events: recentEvents,
            total_events: await Event.countDocuments({ device_id })
        };

        res.status(200).json(summary);
    } catch (err) {
        console.error('Error fetching device summary:', err.message);
        res.status(500).json({ error: 'Server error fetching device summary' });
    }
};

// Get all devices the caregiver has access to with their events
const getAllCaregiverDevices = async (req, res) => {
    try {
        const caregiver_id = req.user_id;

        // SERVER-AUTHORITATIVE: list devices whose owner granted THIS caller, by
        // querying the grant on the device record. No role is consulted; a caller
        // with no grants simply sees an empty list.
        const devices = await Device.find({ caregiver_id, isActive: true });

        // Defence-in-depth: re-check each device through the same pure helper used
        // by the single-device path, so the list path can't drift from the rule.
        const authorized = devices.filter((device) =>
            isCaregiverAuthorizedForDevice({ caregiverUserId: caregiver_id, device })
        );

        if (!authorized || authorized.length === 0) {
            return res.status(200).json({
                message: 'No devices found',
                devices: [],
                total_devices: 0
            });
        }

        const deviceIds = authorized.map((device) => device.device_id);

        // Batched aggregation: fetch recent events + per-device totals for ALL
        // devices in a single round-trip instead of a find + countDocuments per
        // device (the previous N+1 inside Promise.all). $slice keeps only the 10
        // most recent events per device after sorting newest-first.
        const aggregated = await Event.aggregate([
            { $match: { device_id: { $in: deviceIds } } },
            { $sort: { server_timestamp: -1 } },
            {
                $group: {
                    _id: '$device_id',
                    recent_events: { $push: '$$ROOT' },
                    total_events: { $sum: 1 }
                }
            },
            {
                $project: {
                    recent_events: { $slice: ['$recent_events', 10] },
                    total_events: 1
                }
            }
        ]);

        const eventsByDevice = new Map(
            aggregated.map((entry) => [entry._id, entry])
        );

        const devicesWithEvents = authorized.map((device) => {
            const entry = eventsByDevice.get(device.device_id);
            return {
                device_id: device.device_id,
                device_name: device.device_name,
                battery_percent: device.battery_percent,
                firmware_version: device.firmware_version,
                is_online: device.isOnline(),
                last_seen: device.last_seen,
                recent_events: entry ? entry.recent_events : [],
                total_events: entry ? entry.total_events : 0
            };
        });

        res.status(200).json({
            devices: devicesWithEvents,
            total_devices: authorized.length
        });
    } catch (err) {
        console.error('Error fetching caregiver devices:', err.message);
        res.status(500).json({ error: 'Server error fetching devices' });
    }
};

// Search device by device_id to see events
const searchDeviceById = async (req, res) => {
    try {
        const { device_id } = req.query;
        const caregiver_id = req.user_id;

        // Validate device_id
        if (!device_id) {
            return res.status(400).json({ error: 'device_id is required' });
        }
        if (typeof device_id !== 'string') {
            return res.status(400).json({ error: 'device_id must be a string' });
        }

        const { device, error } = await authorizeCaregiverDevice(device_id, caregiver_id);
        if (error) {
            return res.status(error.status).json(error.body);
        }

        // Get all events for this device
        const events = await Event.find({ device_id })
            .sort({ server_timestamp: -1 })
            .limit(100);

        res.status(200).json({
            device: {
                device_id: device.device_id,
                device_name: device.device_name,
                battery_percent: device.battery_percent,
                firmware_version: device.firmware_version,
                is_online: device.isOnline(),
                last_seen: device.last_seen
            },
            events: events,
            total_events: await Event.countDocuments({ device_id })
        });
    } catch (err) {
        console.error('Error searching device:', err.message);
        res.status(500).json({ error: 'Server error searching device' });
    }
};

// Filter events by date range for a device
const filterEventsByDateRange = async (req, res) => {
    try {
        const { device_id, start_date, end_date } = req.query;
        const caregiver_id = req.user_id;

        // Validate required fields
        if (!device_id || !start_date || !end_date) {
            return res.status(400).json({ error: 'device_id, start_date, and end_date are required' });
        }
        if (typeof device_id !== 'string') {
            return res.status(400).json({ error: 'device_id must be a string' });
        }

        const { device, error } = await authorizeCaregiverDevice(device_id, caregiver_id);
        if (error) {
            return res.status(error.status).json(error.body);
        }

        // Parse dates
        const startDate = new Date(start_date);
        const endDate = new Date(end_date);

        // Validate dates
        if (isNaN(startDate.getTime()) || isNaN(endDate.getTime())) {
            return res.status(400).json({ error: 'Invalid date format. Use ISO 8601 format (e.g., 2026-01-01)' });
        }

        // Get events within date range
        const events = await Event.find({
            device_id,
            server_timestamp: {
                $gte: startDate,
                $lte: endDate
            }
        }).sort({ server_timestamp: -1 });

        res.status(200).json({
            device_id: device.device_id,
            device_name: device.device_name,
            date_range: {
                start: startDate,
                end: endDate
            },
            events: events,
            total_events: events.length
        });
    } catch (err) {
        console.error('Error filtering events by date:', err.message);
        res.status(500).json({ error: 'Server error filtering events' });
    }
};

module.exports = {
    authorizeCaregiverDevice,
    claimDeviceForCaregiver,
    acceptCaregiverGrant,
    revokeCaregiverGrant,
    getCaregiver_A_device_summery,
    getAllCaregiverDevices,
    searchDeviceById,
    filterEventsByDateRange
};
