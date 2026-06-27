# Device Ingestion Authentication (A3)

Single source of truth for the device <-> backend authentication wire contract.
**Firmware B1 and this backend MUST implement this scheme identically.** The
contract test in `tests/deviceAuth.test.js` pins the canonical message string so
the two sides cannot silently drift.

## Overview

Every request to `POST /api/ingest/event` and `POST /api/ingest/telemetry` is
authenticated with a **per-device HMAC-SHA256** signature plus a **monotonic
nonce** and a **fresh timestamp**. There is no shared API key — each provisioned
vial has its own secret. The device sends only the HMAC, never the raw secret.

This replaces the previous shared `x-api-key` scheme, which was spoofable by
anyone who learned the single key.

## Transport headers (every ingestion request)

| Header        | Type            | Description                                        |
| ------------- | --------------- | -------------------------------------------------- |
| `x-device-id` | string          | The device identifier. MUST equal body `device_id`.|
| `x-nonce`     | decimal string  | Monotonic per-device counter (e.g. `"42"`).        |
| `x-timestamp` | decimal string  | Unix time in **seconds** (e.g. `"1738483200"`).    |
| `x-signature` | lowercase hex   | HMAC-SHA256 — see below.                            |

## Signature

```
x-signature = HMAC_SHA256(
    key     = device_secret,
    message = x-device-id + "\n" + x-nonce + "\n" + x-timestamp + "\n" + raw_request_body
)
```

- The four parts are joined with a single line-feed (`"\n"`, 0x0A) separator, in
  this exact order: **device id, nonce, timestamp, raw body**.
- `raw_request_body` is the **exact bytes** the device transmitted as the JSON
  body — the backend hashes the bytes captured by the `express.json({ verify })`
  hook, **not** the re-serialized or sanitized body. The device must HMAC the
  identical bytes it puts on the wire.
- `x-nonce` and `x-timestamp` are signed as their **decimal string** forms (the
  same strings sent in the headers).
- The output is encoded as **lowercase hexadecimal**.
- The backend compares signatures with `crypto.timingSafeEqual` (constant time).

### Canonical message example

For `x-device-id: DEVICE001`, `x-nonce: 42`, `x-timestamp: 1738483200`, and a
raw body of `{"device_id":"DEVICE001","event":"OPEN"}`, the signed message is the
literal bytes:

```
DEVICE001
42
1738483200
{"device_id":"DEVICE001","event":"OPEN"}
```

(Three `\n` separators; the body is appended verbatim with no trailing newline.)

## Rejection rules

A request is rejected if **any** of the following hold (checked in this order):

| Condition                                               | HTTP |
| ------------------------------------------------------- | ---- |
| Missing/blank `x-device-id`/`x-nonce`/`x-timestamp`/`x-signature` | 401 |
| `x-nonce` not a non-negative decimal integer            | 400  |
| `x-timestamp` not a non-negative decimal integer        | 400  |
| Device unknown                                          | 401  |
| Device revoked / no credential                          | 403  |
| `x-device-id` != device record id, or != body `device_id` | 403 |
| `\|now - x-timestamp\| > TYME_SYNC_TOLERANCE_SECONDS`   | 401  |
| `x-nonce <= last-seen nonce` for that device (replay / out-of-order) | 401 |
| Signature mismatch                                      | 401  |

The signature is verified **last** so a forged signature can't be used as an
oracle for the cheaper checks.

On success the backend advances the device's `last_nonce` watermark atomically
(only an update with `last_nonce < new_nonce` wins), making concurrent requests
with the same nonce race-safe.

`TYME_SYNC_TOLERANCE_SECONDS` defaults to **300** (5 minutes).

## Credential storage (server side)

- The per-device secret is a 256-bit random value, hex-encoded.
- It is stored **encrypted at rest** with **AES-256-GCM** under a server-held
  master key (`DEVICE_SECRET_ENC_KEY`, never written to the database). The DB
  holds only `{ ciphertext, iv, tag }`.
- A one-way hash (bcrypt/SHA) is **not** usable here: HMAC verification must
  re-compute the signature and therefore needs the original secret. Encryption
  (reversible only with the master key) is the correct primitive. An attacker
  with DB-only access cannot forge device events.
- The plaintext secret is decrypted into memory only at the moment a signature
  is verified.

## Credential lifecycle

Implemented as `Device` instance methods (see `models/Device.js`):

- **issue** — `device.issueCredential()` generates a fresh secret, stores its
  ciphertext, clears `revoked`, resets `last_nonce` to `-1`, and **returns the
  plaintext secret** to be delivered to the device exactly once.
- **rotate** — `device.rotateCredential()` is a re-issue (same effect, new
  secret, bumped `credential.version`). The old secret stops working immediately.
- **revoke** — `device.revokeCredential()` clears the credential and sets
  `revoked = true`. The device cannot authenticate until a new credential is
  issued.

The caller persists with `device.save()` after any lifecycle call.

## Configuration

| Env var                       | Purpose                                                 |
| ----------------------------- | ------------------------------------------------------- |
| `DEVICE_SECRET_ENC_KEY`       | 64-char hex (32-byte) AES master key. Required in prod. |
| `TYME_SYNC_TOLERANCE_SECONDS` | Max clock skew in seconds (default 300).                |
