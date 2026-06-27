// ============================================
// Event payload validation (#38)
// ============================================
// The Event model stores `payload` as Mixed, which means any shape can be
// persisted. This module enumerates the allowed event types and the expected
// shape of their payloads, then validates incoming ingestion requests with zod
// so only well-formed, typed events are stored.
//
// Wire format (unchanged — this is what real devices send to POST /api/ingest/event):
//   {
//     device_id: "DEVICE001",   // string
//     event:     "OPEN",        // string, case-insensitive, stored uppercase
//     event_id:  "evt_123",     // optional idempotency key (string)
//     timestamp: 1738483200,    // optional unix seconds (number)
//     payload:   { ... }        // optional, type-specific (see ALLOWED_EVENTS)
//   }
//
// device_id is strictly cast to a string before reaching Mongoose so values
// like { $ne: null } are rejected (defence-in-depth alongside sanitize.js).

const { z } = require("zod");

// ---------------------------------------------------------------------------
// Allowed event types and their payload schemas.
//
// Payloads are kept lenient (`.passthrough()` allows extra device fields so we
// never reject a slightly-richer-than-documented but otherwise valid event),
// but the KNOWN fields are strictly typed. Unknown event_type values are
// rejected outright.
// ---------------------------------------------------------------------------

// Cap interaction events (the documented core: OPEN / CLOSE).
const interactionPayload = z
  .object({
    duration: z.number().nonnegative().optional(),
    sensor_value: z.number().optional(),
  })
  .passthrough();

// Telemetry / status style events.
const batteryPayload = z
  .object({
    battery: z.number().min(0).max(100).optional(),
    battery_percent: z.number().min(0).max(100).optional(),
    firmware_version: z.string().optional(),
  })
  .passthrough();

const heartbeatPayload = z
  .object({
    uptime: z.number().nonnegative().optional(),
    rssi: z.number().optional(),
  })
  .passthrough();

const bootPayload = z
  .object({
    firmware_version: z.string().optional(),
    reason: z.string().optional(),
  })
  .passthrough();

const sensorPayload = z
  .object({
    sensor_value: z.number().optional(),
    angle: z.number().optional(),
  })
  .passthrough();

// An empty/loose payload accepted for events that carry no structured data.
const emptyPayload = z.object({}).passthrough();

/**
 * Map of EVENT_TYPE (uppercase) -> zod schema for its payload.
 * To add a new device event, add an entry here and the A3 device-auth /
 * ingestion work will automatically accept it.
 */
const ALLOWED_EVENTS = {
  OPEN: interactionPayload,
  CLOSE: interactionPayload,
  BATTERY: batteryPayload,
  LOW_BATTERY: batteryPayload,
  HEARTBEAT: heartbeatPayload,
  BOOT: bootPayload,
  TILT: sensorPayload,
  TAMPER: sensorPayload,
};

const ALLOWED_EVENT_TYPES = Object.keys(ALLOWED_EVENTS);

// ---------------------------------------------------------------------------
// Ingestion request schema (the full POST body).
// ---------------------------------------------------------------------------

// Strict scalar: device_id MUST be a non-empty string. z.string() rejects
// objects such as { $ne: null }, numbers, arrays, etc.
const deviceIdSchema = z.string().min(1, "device_id must be a non-empty string");

const baseIngestionSchema = z.object({
  device_id: deviceIdSchema,
  // Accept any casing on the wire; we normalize to uppercase below.
  event: z.string().min(1, "event is required"),
  event_id: z.string().min(1).optional(),
  // Unix seconds. Devices send a number.
  timestamp: z.number().finite().optional(),
  payload: z.unknown().optional(),
});

/**
 * Pure validation of an ingestion request body.
 *
 * @param {*} body - the raw req.body
 * @returns {{ ok: true, value: { device_id: string, event: string, event_id?: string,
 *            timestamp?: number, payload: object } } | { ok: false, error: string }}
 */
function validateIngestionEvent(body) {
  const base = baseIngestionSchema.safeParse(body);
  if (!base.success) {
    return { ok: false, error: formatZodError(base.error) };
  }

  const data = base.data;
  const eventType = data.event.toUpperCase();

  const payloadSchema = ALLOWED_EVENTS[eventType];
  if (!payloadSchema) {
    return {
      ok: false,
      error: `Unknown event_type "${eventType}". Allowed: ${ALLOWED_EVENT_TYPES.join(", ")}`,
    };
  }

  // Default missing payload to {} (matches existing controller behavior).
  const rawPayload = data.payload === undefined || data.payload === null ? {} : data.payload;
  const parsedPayload = payloadSchema.safeParse(rawPayload);
  if (!parsedPayload.success) {
    return {
      ok: false,
      error: `Invalid payload for ${eventType}: ${formatZodError(parsedPayload.error)}`,
    };
  }

  return {
    ok: true,
    value: {
      device_id: data.device_id,
      event: eventType,
      event_id: data.event_id,
      timestamp: data.timestamp,
      payload: parsedPayload.data,
    },
  };
}

/**
 * Pure validation of just a device_id scalar. Rejects non-strings (e.g.
 * { $ne: null }). Useful for telemetry and query params.
 *
 * @param {*} value
 * @returns {{ ok: true, value: string } | { ok: false, error: string }}
 */
function validateDeviceId(value) {
  const parsed = deviceIdSchema.safeParse(value);
  if (!parsed.success) {
    return { ok: false, error: formatZodError(parsed.error) };
  }
  return { ok: true, value: parsed.data };
}

/**
 * @param {import("zod").ZodError} error
 * @returns {string}
 */
function formatZodError(error) {
  return error.issues
    .map((i) => {
      const path = i.path.length ? `${i.path.join(".")}: ` : "";
      return `${path}${i.message}`;
    })
    .join("; ");
}

module.exports = {
  ALLOWED_EVENTS,
  ALLOWED_EVENT_TYPES,
  validateIngestionEvent,
  validateDeviceId,
};
