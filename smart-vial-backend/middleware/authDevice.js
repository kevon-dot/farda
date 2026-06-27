// ============================================
// A3 — Per-device HMAC authentication + replay enforcement
// ============================================
// Replaces the old shared `x-api-key` check. Every ingestion request must carry
// a per-device HMAC over its exact raw body plus a monotonic nonce and a fresh
// timestamp. See utils/deviceAuth.js for the pure, unit-tested verification
// logic and docs/DEVICE_AUTH.md for the wire contract shared with firmware B1.

const Device = require("../models/Device");
const config = require("../config/config");
const { validateDeviceId } = require("../utils/eventValidation");
const {
  AuthResult,
  AUTH_RESULT_HTTP,
  verifyDeviceRequest,
} = require("../utils/deviceAuth");

// Human-readable messages per result code (kept deliberately generic so we
// don't leak which check failed to an attacker).
const RESULT_MESSAGE = {
  [AuthResult.MISSING_HEADERS]:
    "Authentication required. Provide x-device-id, x-nonce, x-timestamp and x-signature headers.",
  [AuthResult.BAD_NONCE]: "Invalid x-nonce header.",
  [AuthResult.BAD_TIMESTAMP]: "Invalid x-timestamp header.",
  [AuthResult.DEVICE_UNKNOWN]: "Authentication failed.",
  [AuthResult.DEVICE_REVOKED]: "Device credential is revoked.",
  [AuthResult.DEVICE_ID_MISMATCH]: "Device identity mismatch.",
  [AuthResult.STALE_TIMESTAMP]: "Request timestamp outside the allowed window.",
  [AuthResult.REPLAYED_NONCE]: "Replayed or out-of-order request rejected.",
  [AuthResult.BAD_SIGNATURE]: "Authentication failed.",
};

/**
 * Express middleware enforcing per-device HMAC auth + replay protection.
 */
const verifyDeviceAuth = async (req, res, next) => {
  try {
    // The raw body bytes captured by express.json({ verify }) in Server.js.
    // Falls back to "" so an empty-body request still has a defined message.
    const rawBody = req.rawBody !== undefined && req.rawBody !== null ? req.rawBody : "";

    const headerDeviceId = req.headers["x-device-id"];

    // Validate the header device id is a clean scalar string before it ever
    // touches Mongoose (defence-in-depth alongside sanitize.js).
    const idCheck = validateDeviceId(headerDeviceId);
    if (!idCheck.ok) {
      return res
        .status(AUTH_RESULT_HTTP[AuthResult.MISSING_HEADERS])
        .json({ success: false, error: RESULT_MESSAGE[AuthResult.MISSING_HEADERS] });
    }

    // Look up the device WITH its (normally hidden) encrypted credential.
    const device = await Device.findOne({ device_id: idCheck.value }).select("+credential");

    // Decrypt the device secret only if we have a usable credential. Decryption
    // failures (bad master key / corrupt ciphertext) must not 500 a forged
    // request into leaking detail — treat as an unverifiable device.
    let secretKey = null;
    if (device && device.credential && !device.revoked) {
      try {
        secretKey = device.getSecret();
      } catch (e) {
        console.error("Device secret decryption failed:", e.message);
        secretKey = null;
      }
    }

    const result = verifyDeviceRequest({
      headers: {
        "x-device-id": req.headers["x-device-id"],
        "x-nonce": req.headers["x-nonce"],
        "x-timestamp": req.headers["x-timestamp"],
        "x-signature": req.headers["x-signature"],
      },
      rawBody,
      bodyDeviceId: req.body ? req.body.device_id : undefined,
      device: device
        ? {
            device_id: device.device_id,
            secretKey,
            revoked: device.revoked === true,
            last_nonce: typeof device.last_nonce === "number" ? device.last_nonce : -1,
          }
        : null,
      nowSeconds: Math.floor(Date.now() / 1000),
      toleranceSeconds: config.tymeSync.toleranceSeconds,
    });

    if (result.code !== AuthResult.OK) {
      const status = AUTH_RESULT_HTTP[result.code] || 401;
      return res
        .status(status)
        .json({ success: false, error: RESULT_MESSAGE[result.code] || "Authentication failed." });
    }

    // Accepted: advance the per-device nonce watermark atomically. The guard
    // (last_nonce < newNonce) makes concurrent requests with the same nonce
    // race-safe — only one update wins, the other sees no match.
    await Device.updateOne(
      { device_id: device.device_id, last_nonce: { $lt: result.nonce } },
      { $set: { last_nonce: result.nonce } }
    );

    // Hand the verified context to downstream handlers.
    req.device = device;
    req.deviceAuth = { nonce: result.nonce, timestamp: result.timestamp };
    next();
  } catch (error) {
    console.error("Device authentication error:", error.message);
    return res.status(500).json({ success: false, error: "Authentication error" });
  }
};

module.exports = verifyDeviceAuth;
