const mongoose = require('mongoose');

const DeviceSchema = new mongoose.Schema({
    // ============================================
    // Device Identification
    // ============================================
    device_id: {
        type: String,
        required: true,
        unique: true,
        trim: true,
        index: true
    },
    device_name: {
        type: String,
        default: 'Smart Vial Device',
        trim: true,
        required: true
    },
    // ============================================
    // Owner Information
    // ============================================
    user_id: {
        type: String,
        required: false,
        default: null
    },
    claimed: {
        type: Boolean,
        default: false,
        index: true
    },
    claimed_at: {
        type: Date,
        default: null
    },

    caregiver_id: {
        type: String,
        required: false,
        default: null
    },

    // ============================================
    // Device Status & Telemetry
    // ============================================
    battery_percent: {
        type: Number,
        min: 0,
        max: 100,
        default: 0
    },
    firmware_version: {
        type: String,
        default: '1.0.0'
    },
    isActive: {
        type: Boolean,
        default: true,
        index: true
    },

    // ============================================
    // Timestamps
    // ============================================
    last_seen: {
        type: Date,
        default: Date.now,
        index: true
    },

}, { timestamps: true });

// ============================================
// Indexes
// ============================================
// Compound index for querying user's active devices
DeviceSchema.index({ user_id: 1, isActive: 1 });

// ============================================
// Instance Methods
// ============================================
// Check if device is online (seen in last 5 minutes)
DeviceSchema.methods.isOnline = function() {
    const fiveMinutesAgo = new Date(Date.now() - 5 * 60 * 1000);
    return this.last_seen >= fiveMinutesAgo;
};

module.exports = mongoose.model('Device', DeviceSchema);