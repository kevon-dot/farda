const Device = require('../models/Device');
const Event = require('../models/Event');
const { validateIngestionEvent, validateDeviceId } = require('../utils/eventValidation');

/**
 * Resolve the battery reading from a telemetry body, mapping the wire field to
 * the Device model field (#50).
 *
 * Devices/clients send `battery_percent`, but older payloads (and the original
 * handler) used `battery`. We accept BOTH and normalize to the model's
 * `battery_percent`, preferring `battery_percent` when both are present.
 *
 * @param {object} body - the raw telemetry req.body
 * @returns {number|undefined} the battery percentage, or undefined if neither
 *          field was sent (so callers can preserve the existing value / default).
 */
const resolveBatteryPercent = (body) => {
    if (!body || typeof body !== 'object') return undefined;
    if (body.battery_percent !== undefined && body.battery_percent !== null) {
        return body.battery_percent;
    }
    if (body.battery !== undefined && body.battery !== null) {
        return body.battery;
    }
    return undefined;
};

const updateTelemetry = async (req, res) => {
    try {
        const { firmware_version } = req.body;
        // Clients/devices send `battery_percent`; accept the legacy `battery`
        // too. Either way we store it on the model's `battery_percent` (#50).
        const battery_percent = resolveBatteryPercent(req.body);

        // Strictly cast device_id to a string before it reaches Mongoose so
        // operator-injection values like { $ne: null } are rejected (#37).
        const deviceIdCheck = validateDeviceId(req.body.device_id);
        if (!deviceIdCheck.ok) {
            return res.status(400).json({ error: `Bad Request: ${deviceIdCheck.error}` });
        }
        const device_id = deviceIdCheck.value;

        // Device may not exist in the database during boot, so create it if needed
        let device = await Device.findOne({ device_id });
        const now = new Date();

        if (!device) {
            // Create new device if it doesn't exist
            device = new Device({
                device_id,
                battery_percent: battery_percent !== undefined ? battery_percent : 100,
                firmware_version: firmware_version || '1.0.0',
                last_seen: now,
                // GTM-539: telemetry IS a successful sync; track it for fleet health.
                last_sync_at: now,
                battery_updated_at: battery_percent !== undefined ? now : null,
                claimed: false,
                isActive: true
            });
        } else {
            // Update existing device
            if (battery_percent !== undefined) {
                device.battery_percent = battery_percent;
                device.battery_updated_at = now;
            }
            device.firmware_version = firmware_version || device.firmware_version;
            device.last_seen = now;
            // GTM-539: a telemetry POST is a successful sync.
            device.last_sync_at = now;
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

        // Update device last_seen + last_sync_at timestamps (a successful event
        // ingestion is a successful sync; drives GTM-539 fleet-health staleness).
        const now = new Date();
        device.last_seen = now;
        device.last_sync_at = now;
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
    ingestEvent,
    resolveBatteryPercent
};