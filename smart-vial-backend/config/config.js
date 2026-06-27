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
};