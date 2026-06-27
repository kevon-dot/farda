# Farda Smart Vial — Device → Backend Wire Format (HMAC contract)

> **Status: UNVERIFIED REFERENCE.** This is the frozen contract the
> reconstructed firmware (`components/telemetry`, `components/device_identity`)
> implements and that the `smart-vial-backend` (issue **A3**) must implement
> **byte-for-byte identically** so HMAC verification matches. This replaces the
> vulnerable `{"deviceId":"%s","authKey":"%s",...}` scheme (audit finding F1 /
> B1) which leaked the device's bearer credential in cleartext.

## 0. TL;DR for the backend (A3)

- The device **never** sends its secret key. It sends a **signature**.
- Each request carries 4 headers: `x-device-id`, `x-nonce`, `x-timestamp`,
  `x-signature`.
- The backend looks up the **per-device secret** by `x-device-id`, recomputes
  `HMAC-SHA256` over the **exact same canonical input**, and compares in
  constant time. Match ⇒ authentic. Mismatch / stale nonce / old timestamp ⇒
  reject `401`.
- Replay defense: reject any `(x-device-id, x-nonce)` pair seen before, and any
  `x-timestamp` outside an acceptance window (suggest ±300 s).

## 1. Identity & secret

| Field | Meaning |
|---|---|
| `deviceId` | Lowercase hex of the ESP32 base MAC, 12 chars, e.g. `a4cf12ab34cd`. **Public, non-secret routing label.** |
| per-device secret | 32-byte (256-bit) random key, **factory-provisioned** into the device's encrypted NVS (`devKey`) and stored server-side keyed by `deviceId`. **Never transmitted.** See `docs/PROVISIONING.md`. |

The secret is **not** derived from the MAC. The MAC is guessable; the secret is
not.

## 2. HTTPS transport (primary)

`POST <api_target>` where `api_target` is an **`https://`** URL on an allowed
Farda domain (B3 — plaintext and foreign hosts are rejected by the firmware).

### Request headers

```
Content-Type: application/json
x-device-id:  <deviceId>                 # 12 lowercase hex chars
x-nonce:      <nonce_hex>                 # 32 lowercase hex chars (16 random bytes)
x-timestamp:  <unix_epoch_seconds>       # decimal ASCII, e.g. 1769073375
x-signature:  <hmac_hex>                 # 64 lowercase hex chars (HMAC-SHA256)
```

### Request body (canonical JSON, NO key)

The body is the bytes that get signed. The firmware emits exactly this, with
**no whitespace** and keys in **this order**:

```json
{"deviceId":"a4cf12ab34cd","eventType":"PILL_CHANGE","timestamp":1769073375,"currentCount":19,"countChange":-1}
```

`eventType` is one of the event names from `docs/BLE_PROTOCOL.md` §events
(`PILL_CHANGE`, `MANY_PILLS_CHANGE`, `OUTSIDE_WINDOW_CHANGE`,
`EMERGENCY_UNLOCK`, `SAFETY_TIMEOUT`, `LOW_BATTERY_5`, `LOW_BATTERY_2`,
`VIAL_RESTARTED`, `BLE_LOCK_CMD`, `BLE_UNLOCK_CMD`). `currentCount` /
`countChange` are present for all events (0 for non-count events).

> There is **deliberately no `authKey` field**. Authenticity comes from the
> signature, not from echoing a secret.

## 3. The signature (the exact bytes to HMAC)

```
signing_input = body_bytes  ||  "\n"  ||  nonce_hex  ||  "\n"  ||  timestamp_decimal
signature     = HMAC_SHA256( per_device_secret, signing_input )
x-signature   = lowercase_hex( signature )      # 64 chars
```

Where:
- `body_bytes` = the **raw UTF-8 bytes of the request body** exactly as sent
  (do not re-serialize; sign the wire bytes).
- `nonce_hex` = the **same** lowercase-hex string sent in `x-nonce`.
- `timestamp_decimal` = the **same** decimal string sent in `x-timestamp`.
- `||` = byte concatenation; the two `"\n"` are single `0x0A` separators.

### Backend verification (pseudocode for A3)

```js
const secret = lookupDeviceSecret(req.headers['x-device-id']); // 32 raw bytes
if (!secret) return res.status(401);

const ts = parseInt(req.headers['x-timestamp'], 10);
if (Math.abs(Date.now()/1000 - ts) > 300) return res.status(401); // skew window

const nonce = req.headers['x-nonce'];
if (await seenNonce(req.headers['x-device-id'], nonce)) return res.status(401); // replay

const body = req.rawBody;                       // exact received bytes
const input = Buffer.concat([
  Buffer.from(body),
  Buffer.from('\n'),
  Buffer.from(nonce, 'utf8'),
  Buffer.from('\n'),
  Buffer.from(String(ts), 'utf8'),
]);
const expected = crypto.createHmac('sha256', secret).update(input).digest('hex');
const given = req.headers['x-signature'];
if (!crypto.timingSafeEqual(Buffer.from(expected), Buffer.from(given)))
  return res.status(401);

await rememberNonce(req.headers['x-device-id'], nonce, ts); // store for replay window
// authentic -> ingest event
```

> **Migration note (audit F9):** the current `smart-vial-backend`
> `middleware/authDevice.js` authenticates with a single shared `x-api-key`.
> A3 should add this per-device HMAC scheme (per-device secret table + nonce
> store) and retire the shared key. The HMAC algorithm is **HMAC-SHA256**
> only — no SHA-1 anywhere (audit F8).

## 4. MQTTS transport (alternative)

When the device is configured for MQTT (`SET_COMM_PROT`), it connects over
**`mqtts://`** (TLS, server cert verified — B3) and publishes to:

```
topic:   vials/<deviceId>/events/up
```

The same fields travel as a JSON **envelope** around the body (since MQTT has
no headers):

```json
{
  "deviceId": "a4cf12ab34cd",
  "nonce": "<nonce_hex>",
  "timestamp": 1769073375,
  "signature": "<hmac_hex>",
  "body": "{\"deviceId\":\"a4cf12ab34cd\",\"eventType\":\"PILL_CHANGE\",\"timestamp\":1769073375,\"currentCount\":19,\"countChange\":-1}"
}
```

The signature is computed over the **inner `body` string bytes** with the same
`body || "\n" || nonce_hex || "\n" || timestamp` construction. Downstream
commands arrive on `vials/<deviceId>/commands/down`.

## 5. Constants

| Constant | Value |
|---|---|
| HMAC algorithm | HMAC-SHA256 |
| secret length | 32 bytes (256-bit) |
| nonce | 16 random bytes → 32 hex chars |
| signature | 32 bytes → 64 hex chars |
| timestamp | Unix epoch **seconds**, decimal ASCII |
| recommended clock-skew window | ±300 s |
| hex encoding | lowercase, no separators |
