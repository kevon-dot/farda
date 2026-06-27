const Device = require('../models/Device');
const Event = require('../models/Event');

const updateTelemetry = async (req, res) => {
    try {
        const { device_id, battery, firmware_version } = req.body;

        if (!device_id) {
            return res.status(400).json({ error: 'device_id is required' });
        }

        // Device may not exist in the database during boot, so create it if needed
        let device = await Device.findOne({ device_id });

        if (!device) {
            // Create new device if it doesn't exist
            device = new Device({
                device_id,
                battery_percent: battery || 100,
                firmware_version: firmware_version || '1.0.0',
                last_seen: new Date(),
                claimed: false,
                isActive: true
            });
        } else {
            // Update existing device
            device.battery_percent = battery || device.battery_percent;
            device.firmware_version = firmware_version || device.firmware_version;
            device.last_seen = new Date();
        }

        await device.save();

        res.status(200).json({ status: 'Device telemetry updated' });
    } catch (err) {
        console.error('Error updating telemetry:', err.message);
        res.status(500).json({ error: 'Server error updating device telemetry' });
    }
};

// Save event data from devices to the database
const ingestEvent = async (req, res) => {
    try {
        const { event, event_id, timestamp, payload, device_id } = req.body;

        // Validate required fields
        if (!device_id) {
            return res.status(400).json({ error: 'Bad Request: device_id is required' });
        }

        if (!event) {
            return res.status(400).json({ error: 'Bad Request: event is required' });
        }

        // Check for duplicate event using idempotency key
        if (event_id) {
            const existingEvent = await Event.findOne({ idempotency_key: event_id });
            if (existingEvent) {
                console.log('Duplicate event received, ignoring:', event_id);
                return res.status(200).json({ status: 'Duplicate event ignored' });
            }
        }

        //check user claimed device
        //check device exists
        const device = await Device.findOne({ device_id });
        if (!device) {
            return res.status(400).json({ error: 'Bad Request: device not found' });
        }

        if (!device.claimed) {
            return res.status(400).json({ error: 'Bad Request: device not claimed by any user' });
        }

        // Create new event
        const newEvent = new Event({
            device_id: device_id,
            event_type: event,
            device_timestamp: timestamp ? new Date(timestamp * 1000) : null,
            server_timestamp: new Date(),
            payload: payload || {},
            idempotency_key: event_id || null,
            time_drift_seconds: timestamp ? Math.floor(Date.now() / 1000 - timestamp) : 0
        });

        await newEvent.save();

        // Update device last_seen timestamp if device exists
        device.last_seen = new Date();
        await device.save();

        res.status(200).json({ status: 'Event logged successfully' });
    } catch (err) {
        if (err.code === 11000) {
            return res.status(200).json({ status: 'Duplicate event ignored' });
        }
        console.error('Error ingesting event:', err.message);
        res.status(500).json({ error: 'Server error logging event' });
    }
};

module.exports = {
    updateTelemetry,
    ingestEvent
};