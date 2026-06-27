// ============================================
// A3 — Per-device HMAC auth + replay protection (no MongoDB required)
// ============================================
// Exercises the PURE verification core (utils/deviceAuth.js) with a mocked
// device record, plus a CONTRACT TEST pinning the canonical signed-message
// format so firmware B1 and the backend cannot silently drift.

const test = require("node:test");
const assert = require("node:assert");
const crypto = require("crypto");

const {
  buildSignatureMessage,
  computeSignature,
  verifyDeviceRequest,
  parseDecimalInt,
  safeCompareHex,
  AuthResult,
  MESSAGE_SEPARATOR,
} = require("../utils/deviceAuth");

const {
  generateDeviceSecret,
  encryptSecret,
  decryptSecret,
} = require("../utils/deviceCredentials");

// ---------------------------------------------------------------------------
// Test fixtures
// ---------------------------------------------------------------------------
const DEVICE_ID = "DEVICE001";
const SECRET = "a".repeat(64); // deterministic 32-byte hex secret
const TOLERANCE = 300;

function makeDevice(overrides = {}) {
  return {
    device_id: DEVICE_ID,
    secretKey: SECRET,
    revoked: false,
    last_nonce: -1,
    ...overrides,
  };
}

// Sign a request the way a real device would, then return the headers + raw
// body so verifyDeviceRequest can be exercised end-to-end (minus the DB).
function signedRequest({
  deviceId = DEVICE_ID,
  bodyDeviceId = DEVICE_ID,
  nonce = "0",
  timestamp,
  secret = SECRET,
  body,
} = {}) {
  const ts = String(timestamp == null ? Math.floor(Date.now() / 1000) : timestamp);
  const rawBody =
    body == null ? JSON.stringify({ device_id: bodyDeviceId, event: "OPEN" }) : body;
  const signature = computeSignature({
    secret,
    deviceId,
    nonce: String(nonce),
    timestamp: ts,
    rawBody,
  });
  return {
    headers: {
      "x-device-id": deviceId,
      "x-nonce": String(nonce),
      "x-timestamp": ts,
      "x-signature": signature,
    },
    rawBody,
    bodyDeviceId,
  };
}

function verify(req, device, nowSeconds) {
  return verifyDeviceRequest({
    headers: req.headers,
    rawBody: req.rawBody,
    bodyDeviceId: req.bodyDeviceId,
    device,
    nowSeconds: nowSeconds == null ? Math.floor(Date.now() / 1000) : nowSeconds,
    toleranceSeconds: TOLERANCE,
  });
}

// ===========================================================================
// CONTRACT TEST — pins the canonical message construction (firmware <-> backend)
// ===========================================================================

test("CONTRACT: signed message is deviceId\\n nonce\\n timestamp\\n rawBody, joined by LF", () => {
  const rawBody = '{"device_id":"DEVICE001","event":"OPEN"}';
  const message = buildSignatureMessage({
    deviceId: "DEVICE001",
    nonce: "42",
    timestamp: "1738483200",
    rawBody,
  });

  // Exact bytes both sides must hash. If this string changes, firmware breaks.
  const expected =
    "DEVICE001\n42\n1738483200\n" + '{"device_id":"DEVICE001","event":"OPEN"}';
  assert.strictEqual(message, expected);

  // Separator is a single line feed, in the documented order.
  assert.strictEqual(MESSAGE_SEPARATOR, "\n");
  assert.deepStrictEqual(message.split("\n"), [
    "DEVICE001",
    "42",
    "1738483200",
    '{"device_id":"DEVICE001","event":"OPEN"}',
  ]);
});

test("CONTRACT: signature is lowercase hex HMAC-SHA256 over the canonical message", () => {
  const rawBody = '{"device_id":"DEVICE001","event":"OPEN"}';
  const message = "DEVICE001\n42\n1738483200\n" + rawBody;

  const expected = crypto.createHmac("sha256", SECRET).update(message, "utf8").digest("hex");
  const actual = computeSignature({
    secret: SECRET,
    deviceId: "DEVICE001",
    nonce: "42",
    timestamp: "1738483200",
    rawBody,
  });

  assert.strictEqual(actual, expected);
  assert.match(actual, /^[0-9a-f]{64}$/); // lowercase hex, 32 bytes
});

// ===========================================================================
// HAPPY PATH
// ===========================================================================

test("valid signed request with matching device_id + fresh nonce is accepted", () => {
  const now = 1_700_000_000;
  const req = signedRequest({ nonce: "5", timestamp: now });
  const result = verify(req, makeDevice({ last_nonce: 4 }), now);
  assert.strictEqual(result.code, AuthResult.OK);
  assert.strictEqual(result.nonce, 5);
  assert.strictEqual(result.timestamp, now);
});

test("first-ever event (nonce 0) is accepted when last_nonce is -1", () => {
  const now = 1_700_000_000;
  const req = signedRequest({ nonce: "0", timestamp: now });
  const result = verify(req, makeDevice({ last_nonce: -1 }), now);
  assert.strictEqual(result.code, AuthResult.OK);
});

// ===========================================================================
// REJECTIONS
// ===========================================================================

test("wrong signature is rejected", () => {
  const now = 1_700_000_000;
  const req = signedRequest({ nonce: "5", timestamp: now });
  req.headers["x-signature"] = "f".repeat(64); // valid hex shape, wrong value
  const result = verify(req, makeDevice({ last_nonce: 4 }), now);
  assert.strictEqual(result.code, AuthResult.BAD_SIGNATURE);
});

test("signature signed with the wrong secret is rejected", () => {
  const now = 1_700_000_000;
  const req = signedRequest({ nonce: "5", timestamp: now, secret: "b".repeat(64) });
  const result = verify(req, makeDevice({ last_nonce: 4 }), now);
  assert.strictEqual(result.code, AuthResult.BAD_SIGNATURE);
});

test("device_id mismatch (header vs body) is rejected", () => {
  const now = 1_700_000_000;
  // Header device id is DEVICE001 but the body claims a different device.
  const req = signedRequest({ nonce: "5", timestamp: now, bodyDeviceId: "OTHER999" });
  const result = verify(req, makeDevice({ last_nonce: 4 }), now);
  assert.strictEqual(result.code, AuthResult.DEVICE_ID_MISMATCH);
});

test("device_id mismatch (header vs authenticating credential) is rejected", () => {
  const now = 1_700_000_000;
  const req = signedRequest({ nonce: "5", timestamp: now });
  // The credential we authenticate against belongs to a different device.
  const result = verify(req, makeDevice({ device_id: "SOMEONE_ELSE", last_nonce: 4 }), now);
  assert.strictEqual(result.code, AuthResult.DEVICE_ID_MISMATCH);
});

test("stale timestamp (older than tolerance) is rejected", () => {
  const now = 1_700_000_000;
  const old = now - (TOLERANCE + 1);
  const req = signedRequest({ nonce: "5", timestamp: old });
  const result = verify(req, makeDevice({ last_nonce: 4 }), now);
  assert.strictEqual(result.code, AuthResult.STALE_TIMESTAMP);
});

test("future timestamp beyond tolerance is rejected", () => {
  const now = 1_700_000_000;
  const future = now + (TOLERANCE + 1);
  const req = signedRequest({ nonce: "5", timestamp: future });
  const result = verify(req, makeDevice({ last_nonce: 4 }), now);
  assert.strictEqual(result.code, AuthResult.STALE_TIMESTAMP);
});

test("replayed nonce (equal to last-seen) is rejected", () => {
  const now = 1_700_000_000;
  const req = signedRequest({ nonce: "4", timestamp: now });
  const result = verify(req, makeDevice({ last_nonce: 4 }), now);
  assert.strictEqual(result.code, AuthResult.REPLAYED_NONCE);
});

test("old / out-of-order nonce (less than last-seen) is rejected", () => {
  const now = 1_700_000_000;
  const req = signedRequest({ nonce: "3", timestamp: now });
  const result = verify(req, makeDevice({ last_nonce: 10 }), now);
  assert.strictEqual(result.code, AuthResult.REPLAYED_NONCE);
});

test("missing signature header is rejected", () => {
  const now = 1_700_000_000;
  const req = signedRequest({ nonce: "5", timestamp: now });
  delete req.headers["x-signature"];
  const result = verify(req, makeDevice({ last_nonce: 4 }), now);
  assert.strictEqual(result.code, AuthResult.MISSING_HEADERS);
});

test("missing nonce / timestamp / device-id headers are rejected", () => {
  const now = 1_700_000_000;
  for (const h of ["x-nonce", "x-timestamp", "x-device-id"]) {
    const req = signedRequest({ nonce: "5", timestamp: now });
    delete req.headers[h];
    const result = verify(req, makeDevice({ last_nonce: 4 }), now);
    assert.strictEqual(result.code, AuthResult.MISSING_HEADERS, `expected reject when ${h} absent`);
  }
});

test("unknown device is rejected", () => {
  const now = 1_700_000_000;
  const req = signedRequest({ nonce: "5", timestamp: now });
  const result = verify(req, null, now);
  assert.strictEqual(result.code, AuthResult.DEVICE_UNKNOWN);
});

test("revoked device is rejected", () => {
  const now = 1_700_000_000;
  const req = signedRequest({ nonce: "5", timestamp: now });
  const result = verify(req, makeDevice({ revoked: true, secretKey: null, last_nonce: 4 }), now);
  assert.strictEqual(result.code, AuthResult.DEVICE_REVOKED);
});

test("device with no secret is rejected as revoked", () => {
  const now = 1_700_000_000;
  const req = signedRequest({ nonce: "5", timestamp: now });
  const result = verify(req, makeDevice({ secretKey: null, last_nonce: 4 }), now);
  assert.strictEqual(result.code, AuthResult.DEVICE_REVOKED);
});

test("non-numeric nonce / timestamp are rejected with 400-style codes", () => {
  const now = 1_700_000_000;
  const bad = signedRequest({ nonce: "5", timestamp: now });
  bad.headers["x-nonce"] = "abc";
  assert.strictEqual(verify(bad, makeDevice(), now).code, AuthResult.BAD_NONCE);

  const bad2 = signedRequest({ nonce: "5", timestamp: now });
  bad2.headers["x-timestamp"] = "not-a-time";
  assert.strictEqual(verify(bad2, makeDevice(), now).code, AuthResult.BAD_TIMESTAMP);
});

test("tampering with the body invalidates the signature", () => {
  const now = 1_700_000_000;
  const req = signedRequest({ nonce: "5", timestamp: now });
  // Attacker changes the body after the device signed it.
  req.rawBody = '{"device_id":"DEVICE001","event":"TAMPER"}';
  const result = verify(req, makeDevice({ last_nonce: 4 }), now);
  assert.strictEqual(result.code, AuthResult.BAD_SIGNATURE);
});

// ===========================================================================
// HELPERS
// ===========================================================================

test("parseDecimalInt accepts non-negative decimals, rejects junk", () => {
  assert.strictEqual(parseDecimalInt("0"), 0);
  assert.strictEqual(parseDecimalInt("42"), 42);
  assert.strictEqual(parseDecimalInt(""), null);
  assert.strictEqual(parseDecimalInt("-1"), null);
  assert.strictEqual(parseDecimalInt("1.5"), null);
  assert.strictEqual(parseDecimalInt("0x10"), null);
  assert.strictEqual(parseDecimalInt(42), null); // must be a string
});

test("safeCompareHex is false on length mismatch and junk, true on equal", () => {
  assert.strictEqual(safeCompareHex("aa", "aa"), true);
  assert.strictEqual(safeCompareHex("aa", "bb"), false);
  assert.strictEqual(safeCompareHex("aa", "aaaa"), false);
  assert.strictEqual(safeCompareHex("zz", "zz"), false); // not valid hex
  assert.strictEqual(safeCompareHex("aa", 123), false);
});

// ===========================================================================
// CREDENTIAL STORAGE — encrypt/decrypt round-trip (no DB)
// ===========================================================================

test("device secret encrypt/decrypt round-trips", () => {
  process.env.DEVICE_SECRET_ENC_KEY = "0".repeat(64);
  const secret = generateDeviceSecret();
  assert.match(secret, /^[0-9a-f]{64}$/);

  const enc = encryptSecret(secret);
  assert.ok(enc.ciphertext && enc.iv && enc.tag);
  // Ciphertext must not equal the plaintext (it's actually encrypted).
  assert.notStrictEqual(enc.ciphertext, secret);

  const back = decryptSecret(enc);
  assert.strictEqual(back, secret);
});

test("decrypt with a tampered auth tag throws (GCM integrity)", () => {
  process.env.DEVICE_SECRET_ENC_KEY = "0".repeat(64);
  const enc = encryptSecret(generateDeviceSecret());
  enc.tag = "f".repeat(enc.tag.length);
  assert.throws(() => decryptSecret(enc));
});
