const Device = require('../models/Device');
const Event = require('../models/Event');
const { validateIngestionEvent, validateDeviceId } = require('../utils/eventValidation');

const updateTelemetry = async (req, res) => {
    try {
        const { battery, firmware_version } = req.body;

        // Strictly cast device_id to a string before it reaches Mongoose so
        // operator-injection values like { $ne: null } are rejected (#37).
        const deviceIdCheck = validateDeviceId(req.body.device_id);
        if (!deviceIdCheck.ok) {
            return res.status(400).json({ error: `Bad Request: ${deviceIdCheck.error}` });
        }
        const device_id = deviceIdCheck.value;

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
        // Validate the full ingestion payload against the allowed event-type
        // schemas (#38). This strictly casts device_id to a string (rejecting
        // operator-injection values like { $ne: null }, #37), confirms the
        // event_type is known, and type-checks the payload. Malformed events
        // are rejected with 400 before anything reaches Mongoose.
        const validation = validateIngestionEvent(req.body);
        if (!validation.ok) {
            return res.status(400).json({ error: `Bad Request: ${validation.error}` });
        }

        const { device_id, event, event_id, timestamp, payload } = validation.value;

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