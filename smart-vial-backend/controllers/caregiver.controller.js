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

// Claim a device for caregiver - device owner assigns a caregiver
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

        // A user cannot make themselves the caregiver of their own device.
        if (caregiver_id === user_id) {
            return res.status(400).json({ error: 'Cannot assign yourself as caregiver' });
        }

        // Find the device
        const device = await Device.findOne({ device_id });
        if (!device) {
            return res.status(404).json({ error: 'Device not found' });
        }

        // SERVER-AUTHORITATIVE: only the trusted owner of the device may grant a
        // caregiver. The caller cannot grant access to a device they don't own.
        if (!isDeviceOwner({ ownerUserId: user_id, device })) {
            return res.status(403).json({ error: 'Access denied: Only device owner can assign caregivers' });
        }

        // Ensure the caregiver user record exists (without trusting any
        // client-supplied role: we set the role here, server-side, as part of an
        // owner-authorized grant — not because the caregiver asked for it).
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

        // Assign caregiver to device (the owner-granted relationship).
        device.caregiver_id = caregiver_id;
        await device.save();

        if (!caregiver.caregiving_device_ids.includes(device_id)) {
            caregiver.caregiving_device_ids.push(device_id);
        }
        caregiver.lastLogin = new Date();
        await caregiver.save();

        // Record/refresh the auditable consent grant (server-authoritative).
        await CaregiverGrant.findOneAndUpdate(
            { deviceId: device_id, caregiverUserId: caregiver_id },
            {
                deviceId: device_id,
                caregiverUserId: caregiver_id,
                patientUserId: user_id,
                status: GRANT_STATUS.ACCEPTED,
                grantedAt: new Date(),
                revokedAt: null,
            },
            { upsert: true, new: true, setDefaultsOnInsert: true }
        );

        res.status(200).json({
            status: 'Caregiver assigned successfully',
            device: {
                device_id: device.device_id,
                device_name: device.device_name,
                caregiver_id: device.caregiver_id
            }
        });
    } catch (err) {
        console.error('Error assigning caregiver:', err.message);
        res.status(500).json({ error: 'Server error assigning caregiver' });
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
    getCaregiver_A_device_summery,
    getAllCaregiverDevices,
    searchDeviceById,
    filterEventsByDateRange
};
