//can only read if have access to the device id in their caregiving_device_ids array
const Event = require('../models/Event');
const Device = require('../models/Device');
const { findOrCreateUser } = require('../utils/userProvisioning');



// Claim a device for caregiver - device owner assigns a caregiver
const claimDeviceForCaregiver = async (req, res) => {
    try {
        const { device_id, caregiver_id } = req.body;
        const user_id = req.user_id;

        // Validate required fields
        if (!device_id || !caregiver_id) {
            return res.status(400).json({ error: 'device_id and caregiver_id are required' });
        }

        // Find the device
        const device = await Device.findOne({ device_id });
        if (!device) {
            return res.status(404).json({ error: 'Device not found' });
        }

        // Check if user is the owner of the device
        if (device.user_id !== user_id) {
            return res.status(403).json({ error: 'Access denied: Only device owner can assign caregivers' });
        }

        // Find or create the caregiver user, ensuring the 'caregiver' role.
        const caregiver = await findOrCreateUser(caregiver_id, 'caregiver');

        // Assign caregiver to device
        device.caregiver_id = caregiver_id;
        await device.save();

        // Add device_id to caregiver's caregiving_device_ids array if not already present
        if (!caregiver.caregiving_device_ids.includes(device_id)) {
            caregiver.caregiving_device_ids.push(device_id);
        }
        caregiver.lastLogin = new Date();
        await caregiver.save();

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
        const user_role = req.user_role;

        // Find or create user
        const user = await findOrCreateUser(caregiver_id, user_role);

        // Check if user is a caregiver
        if (!user.hasRole('caregiver')) {
            return res.status(403).json({ error: 'Access denied: Caregiver role required' });
        }

        // Find the device
        const device = await Device.findOne({ device_id });
        if (!device) {
            return res.status(404).json({ error: 'Device not found' });
        }

        // Check if caregiver has access to this device
        if (device.caregiver_id !== caregiver_id) {
            return res.status(403).json({ error: 'Access denied: You do not have access to this device' });
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
        const user_role = req.user_role;

        // Find or create user
        const user = await findOrCreateUser(caregiver_id, user_role);

        // Check if user is a caregiver
        if (!user.hasRole('caregiver')) {
            return res.status(403).json({ error: 'Access denied: Caregiver role required' });
        }

        // Find all devices assigned to this caregiver
        const devices = await Device.find({ caregiver_id, isActive: true });

        if (!devices || devices.length === 0) {
            return res.status(200).json({ 
                message: 'No devices found',
                devices: [],
                total_devices: 0
            });
        }

        const deviceIds = devices.map((device) => device.device_id);

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

        const devicesWithEvents = devices.map((device) => {
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
            total_devices: devices.length
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
        const user_role = req.user_role;

        // Find or create user
        const user = await findOrCreateUser(caregiver_id, user_role);

        // Check if user is a caregiver
        if (!user.hasRole('caregiver')) {
            return res.status(403).json({ error: 'Access denied: Caregiver role required' });
        }

        // Validate device_id
        if (!device_id) {
            return res.status(400).json({ error: 'device_id is required' });
        }

        // Find the device and check access
        const device = await Device.findOne({ device_id, caregiver_id });
        if (!device) {
            return res.status(404).json({ error: 'Device not found or access denied' });
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
        const user_role = req.user_role;

        // Find or create user
        const user = await findOrCreateUser(caregiver_id, user_role);

        // Check if user is a caregiver
        if (!user.hasRole('caregiver')) {
            return res.status(403).json({ error: 'Access denied: Caregiver role required' });
        }

        // Validate required fields
        if (!device_id || !start_date || !end_date) {
            return res.status(400).json({ error: 'device_id, start_date, and end_date are required' });
        }

        // Check if caregiver has access to this device
        const device = await Device.findOne({ device_id, caregiver_id });
        if (!device) {
            return res.status(404).json({ error: 'Device not found or access denied' });
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
    claimDeviceForCaregiver,
    getCaregiver_A_device_summery,
    getAllCaregiverDevices,
    searchDeviceById,
    filterEventsByDateRange
};