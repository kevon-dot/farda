# Authentication Guide


## Table of Contents

1. [Overview](#overview)
2. [User & Caregiver Authentication (better-auth)](#user--caregiver-authentication-better-auth)
3. [Device Authentication (per-device HMAC)](#device-authentication-per-device-hmac)
4. [Security Best Practices](#security-best-practices)
5. [Troubleshooting](#troubleshooting)

---

## Overview

Smart Vial uses two distinct authentication mechanisms:

| Who | Method | Backed by | Use Case |
|-----|--------|-----------|----------|
| **Users & Caregivers** | better-auth session validation | Shared **PostgreSQL** store | Mobile app / web dashboard access |
| **ESP32 Devices** | Per-device **HMAC-SHA256** signing | Encrypted secret in **MongoDB** | Device telemetry and event ingestion |

> There is **no raw JWT** auth and **no shared device API key**. Both were replaced.
> User sessions are validated by better-auth against a PostgreSQL database shared
> with the main application. Devices sign each request with their own secret.

---

## User & Caregiver Authentication (better-auth)

User/caregiver endpoints (`/api/user/*`, `/api/caregiver/*`) are protected by the
`middleware/verifyUserToken.js` middleware. It uses **better-auth** to validate the
incoming session against the shared PostgreSQL database — it does **not** decode or
verify a JWT locally.

### How it works

```
1. Client sends request with a better-auth session
   (session cookie OR Authorization: Bearer <session_token>)
   ↓
2. verifyUserToken middleware calls auth.api.getSession({ headers })
   (better-auth natively parses cookies, headers, and bearer tokens)
   ↓
3. better-auth verifies the session directly against the shared PostgreSQL DB
   ↓
4. On success, the verified identity is attached to the request:
   - req.user_id   = session.user.id
   - req.user_role = session.user.role || 'user'
   - req.user      = session.user
   - req.session   = session.session
   ↓
5. Controller processes the request
```

If the session is missing, invalid, or expired, the middleware responds with **401**
(`{ "error": "Access Denied: Invalid or missing authentication" }`). If better-auth
surfaces a specific 4xx status on its error, that status is honoured; otherwise it
defaults to 401.

### Sending credentials

Either a session cookie (set by better-auth during login on the main app) or a
bearer token works:

```http
Authorization: Bearer <better_auth_session_token>
```

### Configuration

```env
# PostgreSQL connection used by better-auth — MUST match the main app's DATABASE_URL
DATABASE_URL=postgres://user:pass@host:5432/dbname

# Base URL where this submodule runs (used by better-auth for URL generation / origin checks)
BETTER_AUTH_URL=https://your-server.com
```

The better-auth client is constructed with a `pg` `Pool` over `DATABASE_URL`, so this
JS submodule talks to the same identity store as the main TypeScript app without an ORM.

### Roles

`req.user_role` comes from the better-auth user (`session.user.role`, defaulting to
`'user'`). The local Mongo `User` model additionally tracks `user_roles`
(`['user', 'caregiver']`) and device-claim lists keyed by the better-auth user id;
this is a mirror for device/role lookups, not a login store.

---

## Device Authentication (per-device HMAC)

Every request to `POST /api/ingest/event` and `POST /api/ingest/telemetry` is
authenticated with a **per-device HMAC-SHA256 signature**, a **monotonic nonce**,
and a **fresh timestamp**, enforced by `middleware/authDevice.js`
(pure verification logic in `utils/deviceAuth.js`).

There is **no shared API key**. Each provisioned vial has its own secret, stored
encrypted at rest (AES-256-GCM) in MongoDB; the device sends only the HMAC, never
the secret.

### Request headers (every ingestion request)

| Header        | Type           | Description                                          |
| ------------- | -------------- | ---------------------------------------------------- |
| `x-device-id` | string         | Device identifier. MUST equal body `device_id`.      |
| `x-nonce`     | decimal string | Monotonic per-device counter (e.g. `"42"`).          |
| `x-timestamp` | decimal string | Unix time in **seconds** (e.g. `"1738483200"`).      |
| `x-signature` | lowercase hex  | `HMAC_SHA256(device_secret, signed_message)`.        |

### Signed message

```
x-signature = HMAC_SHA256(
    key     = device_secret,
    message = x-device-id + "\n" + x-nonce + "\n" + x-timestamp + "\n" + raw_request_body
)
```

The four parts are joined with `"\n"` in that exact order, the raw request body is
appended verbatim (the exact bytes on the wire), and the output is lowercase hex.

**Full wire contract, rejection rules, and credential lifecycle:**
see **[Device Auth (A3)](DEVICE_AUTH.md)**.

### ESP32 example (sketch)

```cpp
// Compute hex HMAC-SHA256 over: deviceId + "\n" + nonce + "\n" + ts + "\n" + body
HTTPClient http;
http.begin("https://your-server.com/api/ingest/telemetry");
http.addHeader("Content-Type", "application/json");
http.addHeader("x-device-id", "DEVICE001");
http.addHeader("x-nonce", "42");
http.addHeader("x-timestamp", "1738483200");
http.addHeader("x-signature", computedHexHmac);

String payload = "{\"device_id\":\"DEVICE001\",\"battery_percent\":85}";
int httpCode = http.POST(payload);
```

> Sign the **exact** bytes you put on the wire. The backend HMACs the raw body
> captured before JSON parsing/sanitization, so the device and backend hash
> byte-identical input.

---

## Security Best Practices

- Store `DATABASE_URL`, `MONGO_URI`, and `DEVICE_SECRET_ENC_KEY` only in
  environment variables; never commit them.
- `DEVICE_SECRET_ENC_KEY` must be a 64-char hex (32-byte) master key in production
  and must never be written to the database.
- Use HTTPS in production so headers/cookies and request bodies aren't exposed.
- Restrict `CORS_ORIGINS` to known frontends; the API uses an allowlist (no wildcard
  on credentialed routes).
- Rate limiting is active (429) — keep it enabled in production.
- Rotate or revoke a device credential if a device is lost/compromised
  (`device.rotateCredential()` / `device.revokeCredential()`).

---

## Troubleshooting

### "Access Denied: Invalid or missing authentication" (user/caregiver)

**Causes**:
1. No better-auth session sent (missing cookie / bearer token)
2. Session expired or revoked
3. `DATABASE_URL` does not point at the same PostgreSQL store as the main app
4. `BETTER_AUTH_URL` misconfigured (origin checks fail)

**Solutions**:
1. Log in via the main app and send the resulting session (cookie or bearer)
2. Verify `DATABASE_URL` matches the main app exactly
3. Verify `BETTER_AUTH_URL` matches the deployment URL

### Device ingestion returns 401 / 403 / 400

See the **[Device Auth rejection table](DEVICE_AUTH.md#rejection-rules)**. Common causes:
- Missing/blank `x-device-id` / `x-nonce` / `x-timestamp` / `x-signature` → 401
- `x-device-id` ≠ body `device_id`, or device revoked → 403
- Timestamp outside `TYME_SYNC_TOLERANCE_SECONDS` → 401
- Reused/decreasing nonce (replay) → 401
- Wrong signature (secret mismatch / body re-serialized before signing) → 401


**Last Updated**: June 27, 2026
