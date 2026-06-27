// ============================================
// A3 — Per-device HMAC authentication + replay protection
// ============================================
// This module is the single source of truth for the device <-> backend wire
// contract. The firmware (B1) implements the IDENTICAL scheme; keep this file
// and docs/DEVICE_AUTH.md in lock-step. The contract test in tests/ pins the
// canonical message-construction string so the two sides can't silently drift.
//
// Wire format (headers on every POST /api/ingest/* request):
//   x-device-id   device identifier (string)              == body.device_id
//   x-nonce       monotonic per-device counter (decimal string, e.g. "42")
//   x-timestamp   unix seconds (decimal string, e.g. "1738483200")
//   x-signature   lowercase hex HMAC-SHA256 (see below)
//
// Signature:
//   HMAC_SHA256(
//     key     = device_secret,
//     message = x-device-id + "\n" + x-nonce + "\n" + x-timestamp + "\n" + raw_body
//   )
// where raw_body is the EXACT bytes the device sent (captured by the
// express.json({ verify }) hook in Server.js), NOT the re-serialized/sanitized
// body. The device never transmits the raw secret — only the HMAC.
//
// Everything in this file is PURE (no DB, no Express). The middleware supplies
// the device record + raw body; these functions decide accept/reject. This is
// what makes the security behaviour unit-testable without a live MongoDB.

const crypto = require("crypto");

// Field separator used when constructing the signed message. Changing this is a
// BREAKING wire-format change and must be coordinated with the firmware.
const MESSAGE_SEPARATOR = "\n";

/**
 * Build the canonical message that both sides feed into HMAC-SHA256.
 *
 * IMPORTANT: the parts are joined with "\n" in the EXACT order
 *   deviceId, nonce, timestamp, rawBody
 * and rawBody is appended verbatim. This is the line the contract test pins.
 *
 * @param {object} parts
 * @param {string} parts.deviceId   value of x-device-id
 * @param {string} parts.nonce      value of x-nonce (decimal string)
 * @param {string} parts.timestamp  value of x-timestamp (decimal string)
 * @param {string|Buffer} parts.rawBody  exact request body bytes
 * @returns {string} the canonical message string
 */
function buildSignatureMessage({ deviceId, nonce, timestamp, rawBody }) {
  const body =
    rawBody == null ? "" : Buffer.isBuffer(rawBody) ? rawBody.toString("utf8") : String(rawBody);
  return [String(deviceId), String(nonce), String(timestamp), body].join(MESSAGE_SEPARATOR);
}

/**
 * Compute the lowercase-hex HMAC-SHA256 signature for a request.
 *
 * @param {object} args
 * @param {string} args.secret    the device's symmetric secret (hex string)
 * @param {string} args.deviceId
 * @param {string} args.nonce
 * @param {string} args.timestamp
 * @param {string|Buffer} args.rawBody
 * @returns {string} lowercase hex signature
 */
function computeSignature({ secret, deviceId, nonce, timestamp, rawBody }) {
  const message = buildSignatureMessage({ deviceId, nonce, timestamp, rawBody });
  return crypto.createHmac("sha256", secret).update(message, "utf8").digest("hex");
}

/**
 * Constant-time comparison of two lowercase-hex signatures.
 * Returns false (never throws) on any malformed / mismatched-length input so a
 * caller can treat the result as a plain boolean.
 *
 * @param {string} expectedHex
 * @param {string} providedHex
 * @returns {boolean}
 */
function safeCompareHex(expectedHex, providedHex) {
  if (typeof expectedHex !== "string" || typeof providedHex !== "string") return false;
  if (expectedHex.length !== providedHex.length) return false;
  let a;
  let b;
  try {
    a = Buffer.from(expectedHex, "hex");
    b = Buffer.from(providedHex, "hex");
  } catch {
    return false;
  }
  // Buffer.from with an odd-length / non-hex string silently truncates; guard
  // against a length mismatch that would make timingSafeEqual throw.
  if (a.length === 0 || a.length !== b.length) return false;
  return crypto.timingSafeEqual(a, b);
}

/**
 * Parse a decimal string into a safe integer, or return null if invalid.
 * Used for x-nonce and x-timestamp. Rejects empty strings, signs other than a
 * leading digit run, floats, and anything beyond Number.MAX_SAFE_INTEGER.
 *
 * @param {*} value
 * @returns {number|null}
 */
function parseDecimalInt(value) {
  if (typeof value !== "string" || !/^\d+$/.test(value)) return null;
  const n = Number(value);
  if (!Number.isSafeInteger(n)) return null;
  return n;
}

// Result codes returned by verifyDeviceRequest. The middleware maps these to
// HTTP statuses; tests assert on the code so they don't depend on transport.
const AuthResult = Object.freeze({
  OK: "OK",
  MISSING_HEADERS: "MISSING_HEADERS",
  BAD_NONCE: "BAD_NONCE",
  BAD_TIMESTAMP: "BAD_TIMESTAMP",
  DEVICE_UNKNOWN: "DEVICE_UNKNOWN",
  DEVICE_REVOKED: "DEVICE_REVOKED",
  DEVICE_ID_MISMATCH: "DEVICE_ID_MISMATCH",
  STALE_TIMESTAMP: "STALE_TIMESTAMP",
  REPLAYED_NONCE: "REPLAYED_NONCE",
  BAD_SIGNATURE: "BAD_SIGNATURE",
});

/**
 * Pure verification of an authenticated ingestion request.
 *
 * The caller (middleware) is responsible ONLY for fetching the device record
 * by deviceId and supplying the raw body + headers + current time. This
 * function does NOT touch the database, which is exactly what makes it unit
 * testable with a mocked device.
 *
 * Order of checks (fail closed at the first failure):
 *   1. all four headers present + well-formed nonce/timestamp
 *   2. device exists                          -> DEVICE_UNKNOWN
 *   3. device not revoked + has a secret      -> DEVICE_REVOKED
 *   4. x-device-id === body device_id         -> DEVICE_ID_MISMATCH
 *   5. |now - x-timestamp| <= tolerance       -> STALE_TIMESTAMP
 *   6. nonce > device.last_nonce              -> REPLAYED_NONCE
 *   7. HMAC matches (constant-time)           -> BAD_SIGNATURE
 *
 * @param {object} args
 * @param {object} args.headers      lower-cased header map
 *   ({ 'x-device-id', 'x-nonce', 'x-timestamp', 'x-signature' })
 * @param {string|Buffer} args.rawBody  exact request body bytes
 * @param {string} args.bodyDeviceId  the device_id parsed from the JSON body
 * @param {object|null} args.device   device record:
 *   { device_id, secretKey (hex)|null, revoked (bool), last_nonce (number) }
 * @param {number} args.nowSeconds    current unix time in seconds
 * @param {number} args.toleranceSeconds  max allowed clock skew
 * @returns {{ code: string, nonce?: number, timestamp?: number }}
 */
function verifyDeviceRequest({
  headers,
  rawBody,
  bodyDeviceId,
  device,
  nowSeconds,
  toleranceSeconds,
}) {
  const h = headers || {};
  const deviceId = h["x-device-id"];
  const nonceRaw = h["x-nonce"];
  const timestampRaw = h["x-timestamp"];
  const signature = h["x-signature"];

  if (
    typeof deviceId !== "string" ||
    deviceId.length === 0 ||
    typeof nonceRaw !== "string" ||
    typeof timestampRaw !== "string" ||
    typeof signature !== "string" ||
    signature.length === 0
  ) {
    return { code: AuthResult.MISSING_HEADERS };
  }

  const nonce = parseDecimalInt(nonceRaw);
  if (nonce === null) return { code: AuthResult.BAD_NONCE };

  const timestamp = parseDecimalInt(timestampRaw);
  if (timestamp === null) return { code: AuthResult.BAD_TIMESTAMP };

  // 2. device exists
  if (!device) return { code: AuthResult.DEVICE_UNKNOWN };

  // 3. device active + provisioned with a secret
  if (device.revoked === true || !device.secretKey) {
    return { code: AuthResult.DEVICE_REVOKED };
  }

  // 4. header device id must match the authenticating credential AND body
  if (deviceId !== device.device_id || deviceId !== bodyDeviceId) {
    return { code: AuthResult.DEVICE_ID_MISMATCH };
  }

  // 5. freshness window
  const skew = Math.abs(nowSeconds - timestamp);
  if (!Number.isFinite(skew) || skew > toleranceSeconds) {
    return { code: AuthResult.STALE_TIMESTAMP };
  }

  // 6. strictly monotonic nonce (rejects replays + out-of-order)
  const lastNonce = typeof device.last_nonce === "number" ? device.last_nonce : -1;
  if (nonce <= lastNonce) {
    return { code: AuthResult.REPLAYED_NONCE };
  }

  // 7. signature (constant-time). Done LAST so a forged signature can't be used
  //    as an oracle for the cheaper checks above.
  const expected = computeSignature({
    secret: device.secretKey,
    deviceId,
    nonce: nonceRaw,
    timestamp: timestampRaw,
    rawBody,
  });
  if (!safeCompareHex(expected, signature)) {
    return { code: AuthResult.BAD_SIGNATURE };
  }

  return { code: AuthResult.OK, nonce, timestamp };
}

// HTTP status mapping for each result code. 401 = "we don't trust this
// request" (auth/signature/replay), 400 = malformed, 403 = known-but-forbidden
// credential (revoked / id mismatch).
const AUTH_RESULT_HTTP = Object.freeze({
  [AuthResult.MISSING_HEADERS]: 401,
  [AuthResult.BAD_NONCE]: 400,
  [AuthResult.BAD_TIMESTAMP]: 400,
  [AuthResult.DEVICE_UNKNOWN]: 401,
  [AuthResult.DEVICE_REVOKED]: 403,
  [AuthResult.DEVICE_ID_MISMATCH]: 403,
  [AuthResult.STALE_TIMESTAMP]: 401,
  [AuthResult.REPLAYED_NONCE]: 401,
  [AuthResult.BAD_SIGNATURE]: 401,
});

module.exports = {
  MESSAGE_SEPARATOR,
  AuthResult,
  AUTH_RESULT_HTTP,
  buildSignatureMessage,
  computeSignature,
  safeCompareHex,
  parseDecimalInt,
  verifyDeviceRequest,
};
