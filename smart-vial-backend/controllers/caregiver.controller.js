//can only read if have access to the device id in their caregiving_device_ids array
const User = require('../models/User');
const Event = require('../models/Event');
const Device = require('../models/Device');



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

        // Verify the caregiver exists or create them
        let caregiver = await User.findOne({ user_id: caregiver_id });
        
        if (!caregiver) {
            // Create caregiver user if doesn't exist
            caregiver = new User({
                user_id: caregiver_id,
                user_roles: ['caregiver'],
                claim_device_ids: [],
                caregiving_device_ids: []
            });
        } else if (!caregiver.user_roles.includes('caregiver')) {
            // Add caregiver role if user exists but doesn't have the role
            caregiver.user_roles.push('caregiver');
        }

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
        let user = await User.findOne({ user_id: caregiver_id });
        if (!user) {
            user = new User({
                user_id: caregiver_id,
                user_roles: [user_role],
                claim_device_ids: [],
                caregiving_device_ids: []
            });
            await user.save();
        }

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
        let user = await User.findOne({ user_id: caregiver_id });
        if (!user) {
            user = new User({
                user_id: caregiver_id,
                user_roles: [user_role],
                claim_device_ids: [],
                caregiving_device_ids: []
            });
            await user.save();
        }

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

        // Get recent events for all devices
        const devicesWithEvents = await Promise.all(devices.map(async (device) => {
            const recentEvents = await Event.find({ device_id: device.device_id })
                .sort({ server_timestamp: -1 })
                .limit(10);

            return {
                device_id: device.device_id,
                device_name: device.device_name,
                battery_percent: device.battery_percent,
                firmware_version: device.firmware_version,
                is_online: device.isOnline(),
                last_seen: device.last_seen,
                recent_events: recentEvents,
                total_events: await Event.countDocuments({ device_id: device.device_id })
            };
        }));

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
        let user = await User.findOne({ user_id: caregiver_id });
        if (!user) {
            user = new User({
                user_id: caregiver_id,
                user_roles: [user_role],
                claim_device_ids: [],
                caregiving_device_ids: []
            });
            await user.save();
        }

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
        let user = await User.findOne({ user_id: caregiver_id });
        if (!user) {
            user = new User({
                user_id: caregiver_id,
                user_roles: [user_role],
                claim_device_ids: [],
                caregiving_device_ids: []
            });
            await user.save();
        }

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