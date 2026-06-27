const mongoose = require("mongoose");

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
