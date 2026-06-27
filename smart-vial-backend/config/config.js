const path = require("path");
require("dotenv").config({ path: path.join(__dirname, "..", ".env") });

module.exports = {
  port: process.env.PORT || 5000,
  nodeEnv: process.env.NODE_ENV || "development",

  mongoUri: {
    uri: process.env.MONGODB_URI || "mongodb://localhost:27017/myapp",
  },

  jwt: {
    secret: process.env.JWT_SECRET || "dev-secret-change-in-production",
    expiresIn: process.env.JWT_EXPIRES_IN || "30d",
  },

  device: {
    // Legacy shared key retained only so unrelated config consumers/tests don't
    // break; it is NO LONGER used for ingestion auth (A3 replaced it with
    // per-device HMAC). Do not reintroduce it on the ingestion path.
    apiKey: process.env.DEVICE_API_KEY || "our-device-api-key-change-this-in-production",
    // Master key used to encrypt per-device secrets at rest (AES-256-GCM).
    // Provide a 64-char hex string (32 bytes) in production. Never store this
    // in the database. See utils/deviceCredentials.js.
    secretEncKey: process.env.DEVICE_SECRET_ENC_KEY || "",
  },

  cors: {
    origins: process.env.CORS_ORIGINS
      ? process.env.CORS_ORIGINS.split(",")
      : ["http://localhost:5000"],
  },

  rateLimit: {
    windowMs: parseInt(process.env.RATE_LIMIT_WINDOW_MS) || 15 * 60 * 1000, // 15 minutes
    maxRequests: parseInt(process.env.RATE_LIMIT_MAX_REQUESTS) || 100, // limit each IP to 100 requests per windowMs
  },

  tymeSync: {
    // `toleranceSeconds` is the max allowed clock skew used by the A3
    // device-auth replay/freshness check.
    toleranceSeconds: parseInt(process.env.TYME_SYNC_TOLERANCE_SECONDS) || 300, // 5 minutes
  },

  // ============================================
  // GTM-539 — Admin / fleet management
  // ============================================
  admin: {
    // SERVER-AUTHORITATIVE admin allowlist. Admin-only fleet/registry/OTA
    // endpoints authorize against THIS list of better-auth user ids, never
    // against a client-asserted role/header. Comma-separated env var.
    // Empty in dev → no admin access (fail closed) unless explicitly configured.
    userIds: process.env.ADMIN_USER_IDS
      ? process.env.ADMIN_USER_IDS.split(",").map((s) => s.trim()).filter(Boolean)
      : [],
  },

  // ============================================
  // GTM-539 — Fleet-health thresholds
  // ============================================
  // Derived health (offline / stale-sync / low-battery) is computed from a
  // device's last_seen / last_sync_at / battery_percent against these knobs.
  fleet: {
    // A device not seen within this window is considered OFFLINE.
    offlineAfterSeconds:
      parseInt(process.env.FLEET_OFFLINE_AFTER_SECONDS) || 15 * 60, // 15 minutes
    // A device that has not completed a successful sync within this window is
    // STALE (it may still be "online" by last_seen but isn't reporting data).
    staleSyncAfterSeconds:
      parseInt(process.env.FLEET_STALE_SYNC_AFTER_SECONDS) || 24 * 60 * 60, // 24 hours
    // Battery at/below this percent is LOW.
    lowBatteryPercent: parseInt(process.env.FLEET_LOW_BATTERY_PERCENT) || 20,
  },
};