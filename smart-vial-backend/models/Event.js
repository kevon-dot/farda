const mongoose = require("mongoose");
const { ALLOWED_EVENTS, ALLOWED_EVENT_TYPES } = require("../utils/eventValidation");

const EventSchema = new mongoose.Schema(
  {
    // ============================================
    // Event Identification
    // ============================================
    idempotency_key: {
      type: String,
      unique: true,
      sparse: true,
      index: true, // Allows null values while maintaining uniqueness for non-null values
    },

    // Client-side buffer ordinal (GTM-514). When the mobile app relays its
    // BLE-buffered DoseLogEvents it forwards each event's `sequence`; we persist
    // it so ordering of app-relayed events is recoverable. Firmware-ingested
    // events leave this null.
    sequence: {
      type: Number,
      default: null,
    },

    // ============================================
    // Device Information
    // ============================================
    device_id: {
      type: String,
      required: true,
      index: true, // Indexed for fast queries by device
    },

    // ============================================
    // Event Data
    // ============================================
    event_type: {
      type: String,
      required: true,
      uppercase: true // Store event types in uppercase
    },
    payload: {
      type: mongoose.Schema.Types.Mixed, // Flexible payload for any event data
      default: {}
    },

    // ============================================
    // Timestamps
    // ============================================
    device_timestamp: {
      type: Date,
      required: false,
      default: null,
      index: true,
    },
    server_timestamp: {
      type: Date,
      default: Date.now, // Time received by server
      index: true,
    },
    time_drift_seconds: {
      type: Number,
      default: 0,
    },

    processed:{
      type: Boolean,
      default: false,
      
    }
  },
  { timestamps: { createdAt: 'createdAt', updatedAt: false } },
); 

// ============================================
// Payload validation (#38)
// ============================================
// Defense-in-depth: even though the ingestion controller validates with zod
// before constructing an Event, enforce the allowed event_type + payload shape
// at the model layer so no code path can persist an unvalidated Mixed payload.
EventSchema.pre("validate", function () {
  const eventType =
    typeof this.event_type === "string" ? this.event_type.toUpperCase() : this.event_type;
  const schema = ALLOWED_EVENTS[eventType];

  if (!schema) {
    throw new Error(
      `Invalid event_type "${this.event_type}". Allowed: ${ALLOWED_EVENT_TYPES.join(", ")}`
    );
  }

  const result = schema.safeParse(this.payload == null ? {} : this.payload);
  if (!result.success) {
    throw new Error(
      `Invalid payload for ${eventType}: ${result.error.issues.map((i) => i.message).join("; ")}`
    );
  }

  // Persist the parsed payload (strips nothing valid, keeps passthrough fields).
  this.payload = result.data;
});

// ============================================
// Indexes
// ============================================
// Compound index for querying device events by time
EventSchema.index({ device_id: 1, event_type: 1, server_timestamp: -1 });
EventSchema.index({ device_id: 1, event_type: 1, device_timestamp: -1 });

EventSchema.statics.getRecentEvents = function(device_id, limit = 50) {
  return this.find({ device_id })
    .sort({ device_timestamp: -1 })
    .limit(limit);
};

EventSchema.statics.getEventsByTimeRange = function(device_id, startDate, endDate) {
  return this.find({
    device_id,
    device_timestamp: {
      $gte: startDate,
      $lte: endDate
    }
  }).sort({ device_timestamp: -1 });
};

module.exports = mongoose.model("Event", EventSchema);
