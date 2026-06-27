# Farda Smart Vial — Device → Backend Wire Format (HMAC contract)

> **Matches `smart-vial-backend/docs/DEVICE_AUTH.md` (merged) — keep in sync.**
>
> The backend (`smart-vial-backend/utils/deviceAuth.js`, issue **A3**) is the
> **source of truth**. This firmware (`components/telemetry`,
> `components/device_identity`) implements the **identical** scheme. The
> backend's contract test (`tests/deviceAuth.test.js`) pins the canonical
> message string, so the two sides cannot silently drift. This replaces the
> vulnerable `{"deviceId":"%s","authKey":"%s",...}` scheme (audit F1 / B1) that
> leaked the device's bearer credential.

## 0. TL;DR for the backend (A3)

- The device **never** sends its secret key. It sends a **signature**.
- Each request carries 4 headers: `x-device-id`, `x-nonce`, `x-timestamp`,
  `x-signature`.
- The backend looks up the **per-device secret** by `x-device-id`, recomputes
  `HMAC-SHA256` over the **exact same canonical input** (see §3), and compares
  in constant time. Match ⇒ authentic.
- Replay defense: `x-nonce` is a **monotonic per-device counter**; the backend
  rejects any event whose nonce `<=` the last accepted nonce. `x-timestamp`
  must be within `TYME_SYNC_TOLERANCE_SECONDS` (default 300 s) of now.

## 1. Identity & secret

| Field | Meaning |
|---|---|
| `device_id` | Device identifier. The firmware uses the lowercase hex of the ESP32 base MAC, e.g. `a4cf12ab34cd`. **Public, non-secret routing label.** MUST equal the body `device_id`. |
| per-device secret | 32-byte (256-bit) random key, **factory-provisioned** into the device's encrypted NVS (`devKey`) and stored server-side (AES-256-GCM encrypted at rest) keyed by `device_id`. **Never transmitted.** See `docs/PROVISIONING.md`. |

The secret is **not** derived from the MAC. The MAC is guessable; the secret is
not.

## 2. Headers (every ingestion request)

```
Content-Type: application/json
x-device-id:  <device_id>                # == body device_id
x-nonce:      <counter>                   # MONOTONIC decimal string, e.g. "42"
x-timestamp:  <unix_epoch_seconds>        # decimal ASCII, e.g. 1738483200
x-signature:  <hmac_hex>                  # 64 lowercase hex chars (HMAC-SHA256)
```

- **`x-nonce` is a decimal monotonic counter, NOT random.** The firmware
  persists the last counter in NVS (`nonceCtr`) and increments it per event, so
  it strictly increases across reboots. The backend rejects `nonce <=
  last_nonce` for that device.
- **`x-timestamp` is Unix epoch SECONDS** as a decimal string.

## 3. The signature (the exact bytes to HMAC)

The four parts are joined with a single line-feed (`"\n"`, `0x0A`), in this
**exact order — device id, nonce, timestamp, raw body**:

```
signing_input = x-device-id + "\n" + x-nonce + "\n" + x-timestamp + "\n" + raw_request_body
signature     = HMAC_SHA256( per_device_secret, signing_input )
x-signature   = lowercase_hex( signature )      # 64 chars
```

Where:
- `raw_request_body` = the **exact UTF-8 bytes** of the request body as sent
  (sign the wire bytes; do not re-serialize). The backend hashes the bytes from
  its `express.json({ verify })` hook, not the sanitized body.
- `x-nonce` and `x-timestamp` are signed as their **decimal string** forms (the
  same strings sent in the headers).
- Output is **lowercase hex**.

### Canonical message example

For `x-device-id: a4cf12ab34cd`, `x-nonce: 42`, `x-timestamp: 1738483200`, and a
raw body of
`{"device_id":"a4cf12ab34cd","event":"PILL_CHANGE","timestamp":1738483200,"payload":{"currentCount":19,"countChange":-1}}`,
the signed message is the literal bytes:

```
a4cf12ab34cd
42
1738483200
{"device_id":"a4cf12ab34cd","event":"PILL_CHANGE","timestamp":1738483200,"payload":{"currentCount":19,"countChange":-1}}
```

(Three `\n` separators; the body is appended verbatim with no trailing newline.)

## 4. Request body (canonical JSON, NO key)

Field names match the backend ingestion schema
(`smart-vial-backend/utils/eventValidation.js`): `device_id`, `event`,
`timestamp` (unix seconds), and a per-type `payload` (passthrough). The firmware
emits exactly this, no whitespace, keys in this order:

```json
{"device_id":"a4cf12ab34cd","event":"PILL_CHANGE","timestamp":1738483200,"payload":{"currentCount":19,"countChange":-1}}
```

`event` is one of the event names from `docs/BLE_PROTOCOL.md` §events
(`PILL_CHANGE`, `MANY_PILLS_CHANGE`, `OUTSIDE_WINDOW_CHANGE`,
`EMERGENCY_UNLOCK`, `SAFETY_TIMEOUT`, `LOW_BATTERY_5`, `LOW_BATTERY_2`,
`VIAL_RESTARTED`, `BLE_LOCK_CMD`, `BLE_UNLOCK_CMD`).

> There is **deliberately no `authKey` field**. Authenticity comes from the
> signature, not from echoing a secret. `body.device_id` MUST equal
> `x-device-id` or the backend returns `DEVICE_ID_MISMATCH` (403).

## 5. Backend verification (already implemented in A3)

`verifyDeviceRequest()` in `smart-vial-backend/utils/deviceAuth.js`, in order
(fail closed at the first failure): headers present + well-formed → device
exists → not revoked → `x-device-id === device.device_id === body.device_id`
→ `|now - timestamp| <= tolerance` → `nonce > last_nonce` → constant-time HMAC
match. Signature is checked **last** so it can't be used as an oracle.

```js
const expected = computeSignature({
  secret: device.secretKey,
  deviceId: req.headers['x-device-id'],
  nonce: req.headers['x-nonce'],          // decimal string, as received
  timestamp: req.headers['x-timestamp'],  // decimal string, as received
  rawBody: req.rawBody,                    // exact received bytes
});
// computeSignature builds: deviceId + "\n" + nonce + "\n" + timestamp + "\n" + rawBody
crypto.timingSafeEqual(Buffer.from(expected), Buffer.from(req.headers['x-signature']));
```

## 6. MQTTS transport (alternative)

When configured for MQTT (`SET_COMM_PROT`), the device connects over `mqtts://`
(TLS, server cert verified — B3) and publishes to `vials/<device_id>/events/up`.
Since MQTT has no headers, the same fields travel as a JSON envelope around the
body; the signature is computed over the **inner `body` string bytes** with the
identical `deviceId + "\n" + nonce + "\n" + timestamp + "\n" + body`
construction. Downstream commands arrive on `vials/<device_id>/commands/down`.

## 7. Constants

| Constant | Value |
|---|---|
| HMAC algorithm | HMAC-SHA256 |
| secret length | 32 bytes (256-bit) |
| nonce | **monotonic decimal counter**, persisted in NVS, strictly increasing |
| signature | 32 bytes → 64 lowercase hex chars |
| timestamp | Unix epoch **seconds**, decimal ASCII |
| signing order | `device_id \n nonce \n timestamp \n raw_body` |
| separator | single `\n` (0x0A), three of them, no trailing newline |
| tolerance | `TYME_SYNC_TOLERANCE_SECONDS`, default 300 s |
| hex encoding | lowercase, no separators |
