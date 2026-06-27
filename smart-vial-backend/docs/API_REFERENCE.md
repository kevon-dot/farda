# API Reference

Complete API documentation for Smart Vial Backend.

**Base URL**: `http://localhost:5000` (development)

---

## Table of Contents

1. [Authentication](#authentication)
2. [User APIs](#user-apis)
3. [Caregiver APIs](#caregiver-apis)
4. [Device Ingestion APIs](#device-ingestion-apis)
5. [Error Responses](#error-responses)


---

## Authentication

### User & Caregiver Authentication (better-auth session)

All `/api/user/*` and `/api/caregiver/*` endpoints require a valid **better-auth**
session. Send it as a session cookie or as a bearer token; it is validated by
`middleware/verifyUserToken.js` against the shared PostgreSQL store (it is **not** a
locally-verified JWT).

```http
Authorization: Bearer <better_auth_session_token>
```

On success the request carries `req.user_id`, `req.user_role`, `req.user`, and
`req.session`. A missing/invalid/expired session returns **401**.

### Device Authentication (per-device HMAC)

All `/api/ingest/*` endpoints require per-device HMAC headers — there is **no shared
API key**:

```http
x-device-id: DEVICE001
x-nonce: 42
x-timestamp: 1738483200
x-signature: <lowercase hex HMAC-SHA256>
```

The signature is `HMAC_SHA256(device_secret, "x-device-id\nx-nonce\nx-timestamp\nraw_body")`.
See **[Device Auth](DEVICE_AUTH.md)** for the complete contract and rejection rules.

---

## User APIs

Base path: `/api/user`

### Save User

Create or update user in database.

**Endpoint**: `POST /api/user/save`

**Headers**:
```http
Authorization: Bearer <token>
```

**Response** (201 Created):
```json
{
  "status": "success",
  "message": "User created successfully",
  "user": {
    "user_id": "65abc123def456789",
    "user_roles": ["user"],
    "createdAt": "2026-02-02T10:00:00.000Z",
    "lastLogin": "2026-02-02T10:00:00.000Z"
  }
}
```

**Response** (200 OK - existing user):
```json
{
  "status": "success",
  "message": "User updated successfully",
  "user": {
    "user_id": "65abc123def456789",
    "user_roles": ["user", "caregiver"],
    "claim_device_ids": ["DEVICE001"],
    "caregiving_device_ids": ["DEVICE002"],
    "createdAt": "2026-02-01T10:00:00.000Z",
    "lastLogin": "2026-02-02T10:00:00.000Z"
  }
}
```

---

### Claim Device

Assign a device to the authenticated user.

**Endpoint**: `POST /api/user/claim`

**Headers**:
```http
Authorization: Bearer <token>
Content-Type: application/json
```

**Request Body**:
```json
{
  "device_id": "DEVICE001"
}
```

**Response** (200 OK):
```json
{
  "status": "success",
  "device": {
    "device_id": "DEVICE001",
    "device_name": "Smart Vial Device",
    "user_id": "65abc123def456789",
    "claimed": true,
    "battery_percent": 85,
    "firmware_version": "1.0.2",
    "last_seen": "2026-02-02T10:00:00.000Z"
  }
}
```

**Errors**:
- `404` - Device not found
- `409` - Device already claimed

---

### Get User Devices

Retrieve all devices owned by the user.

**Endpoint**: `GET /api/user/devices`

**Headers**:
```http
Authorization: Bearer <token>
```

**Response** (200 OK):
```json
[
  {
    "device_id": "DEVICE001",
    "device_name": "Smart Vial Device",
    "user_id": "65abc123def456789",
    "battery_percent": 85,
    "firmware_version": "1.0.2",
    "last_seen": "2026-02-02T10:00:00.000Z",
    "claimed": true,
    "isActive": true
  }
]
```

---

### Get Device Events

Retrieve recent events for a specific device.

**Endpoint**: `GET /api/user/devices/:device_id/events`

**Headers**:
```http
Authorization: Bearer <token>
```

**Path Parameters**:
- `device_id` - Device identifier

**Response** (200 OK):
```json
[
  {
    "_id": "507f1f77bcf86cd799439011",
    "device_id": "DEVICE001",
    "event_type": "OPEN",
    "device_timestamp": "2026-02-02T09:00:00.000Z",
    "server_timestamp": "2026-02-02T09:00:05.000Z",
    "idempotency_key": "evt_12345",
    "payload": {}
  },
  {
    "_id": "507f1f77bcf86cd799439012",
    "device_id": "DEVICE001",
    "event_type": "CLOSE",
    "device_timestamp": "2026-02-02T09:05:00.000Z",
    "server_timestamp": "2026-02-02T09:05:03.000Z",
    "idempotency_key": "evt_12346",
    "payload": {}
  }
]
```

**Limits**: Returns last 100 events, sorted by newest first

---

### Get All Events

Retrieve events from all user's devices.

**Endpoint**: `GET /api/user/events/all`

**Headers**:
```http
Authorization: Bearer <token>
```

**Response** (200 OK):
```json
[
  {
    "device_id": "DEVICE001",
    "event_type": "OPEN",
    "device_timestamp": "2026-02-02T09:00:00.000Z",
    "server_timestamp": "2026-02-02T09:00:05.000Z"
  }
]
```

**Limits**: Returns last 500 events across all devices

---

### Search Events by Time Range

Filter device events by time period.

**Endpoint**: `GET /api/user/devices/:device_id/events/search`

**Headers**:
```http
Authorization: Bearer <token>
```

**Path Parameters**:
- `device_id` - Device identifier

**Query Parameters**:
- `start_time` (required) - ISO 8601 timestamp or date string
- `end_time` (required) - ISO 8601 timestamp or date string

**Example**:
```http
GET /api/user/devices/DEVICE001/events/search?start_time=2026-01-01T00:00:00Z&end_time=2026-02-02T23:59:59Z
```

**Response** (200 OK):
```json
[
  {
    "device_id": "DEVICE001",
    "event_type": "OPEN",
    "device_timestamp": "2026-01-15T09:00:00.000Z",
    "server_timestamp": "2026-01-15T09:00:05.000Z"
  }
]
```

---

### Unclaim Device

Remove device from user's account.

**Endpoint**: `DELETE /api/user/devices/:device_id/unclaim`

**Headers**:
```http
Authorization: Bearer <token>
```

**Path Parameters**:
- `device_id` - Device identifier

**Response** (200 OK):
```json
{
  "status": "success",
  "message": "Device unclaimed successfully"
}
```

---

### Delete Device Events

Delete all events for a specific device (owner only).

**Endpoint**: `DELETE /api/user/devices/:device_id/events`

**Headers**:
```http
Authorization: Bearer <token>
```

**Path Parameters**:
- `device_id` - Device identifier

**Response** (200 OK):
```json
{
  "status": "success",
  "message": "Device events deleted successfully",
  "deletedCount": 42
}
```

---

### Remove Caregiver Access

Revoke caregiver access to a device.

**Endpoint**: `DELETE /api/user/devices/:device_id/caregiver`

**Headers**:
```http
Authorization: Bearer <token>
```

**Path Parameters**:
- `device_id` - Device identifier

**Response** (200 OK):
```json
{
  "status": "success",
  "message": "Caregiver access removed successfully"
}
```

---

## Caregiver APIs

Base path: `/api/caregiver`

### Two-sided caregiver consent

Caregiver access uses an explicit two-sided consent state machine. A caregiver
gets **no access** until they accept an invite from the device owner (patient):

```
(none) --invite(owner)--> pending --accept(caregiver)--> accepted
                              |                              |
                              +--------revoke(owner|cg)------+--> revoked
```

- **Owner invites** the caregiver → creates a `pending` grant. The caregiver has
  no access while pending; `device.caregiver_id` is NOT set yet.
- **The invited caregiver accepts** → `pending → accepted`; only now is access
  granted (the relationship is mirrored to `device.caregiver_id`).
- **Owner OR caregiver revokes** → `* → revoked` (terminal); access is cut.

Each grant carries a PHI-free consent audit: `invitedBy/invitedAt`,
`acceptedBy/acceptedAt`, `revokedBy/revokedAt`.

### Invite Caregiver to Device

Device owner (patient) invites a caregiver. Creates a **pending** grant — the
caregiver gets no access until they accept.

**Endpoint**: `POST /api/caregiver/claim-device`

**Headers**:
```http
Authorization: Bearer <user_token>
Content-Type: application/json
```

**Request Body**:
```json
{
  "device_id": "DEVICE001",
  "caregiver_id": "65def456abc123789"
}
```

**Response** (200 OK):
```json
{
  "status": "Caregiver invited successfully; awaiting caregiver acceptance",
  "grant": {
    "id": "65fa...",
    "device_id": "DEVICE001",
    "patient_user_id": "65abc...",
    "caregiver_user_id": "65def456abc123789",
    "status": "pending",
    "invited_at": "2026-06-27T10:00:00.000Z",
    "invited_by": "65abc..."
  },
  "device": {
    "device_id": "DEVICE001",
    "device_name": "Smart Vial Device",
    "caregiver_id": null
  }
}
```

**Errors**:
- `403` - User is not device owner
- `404` - Device not found

---

### Accept Caregiver Invite

The **invited caregiver** explicitly accepts a pending invite. Moves
`pending → accepted` and grants access.

**Endpoint**: `POST /api/caregiver/grants/:id/accept`

**Headers**:
```http
Authorization: Bearer <caregiver_token>
```

**Response** (200 OK):
```json
{
  "status": "Caregiver invite accepted; access granted",
  "grant": { "id": "65fa...", "status": "accepted", "accepted_by": "65def...", "accepted_at": "2026-06-27T10:05:00.000Z" }
}
```

**Errors**:
- `403` - Caller is not the invited caregiver
- `404` - Grant not found
- `409` - Illegal transition (e.g. grant is not `pending`)

---

### Revoke Caregiver Grant

The **owner (patient) OR the caregiver** revokes a grant. Valid from `pending`
(decline/withdraw) or `accepted` (end access). Moves `* → revoked` and cuts
access.

**Endpoint**: `POST /api/caregiver/grants/:id/revoke`

**Headers**:
```http
Authorization: Bearer <user_or_caregiver_token>
```

**Response** (200 OK):
```json
{
  "status": "Caregiver grant revoked",
  "grant": { "id": "65fa...", "status": "revoked", "revoked_by": "65abc...", "revoked_at": "2026-06-27T11:00:00.000Z" }
}
```

**Errors**:
- `403` - Caller is neither the patient nor the caregiver
- `404` - Grant not found
- `409` - Illegal transition (grant already `revoked`)

---

### Get Device Summary

Caregiver views summary of assigned device.

**Endpoint**: `GET /api/caregiver/devices/:device_id/summary`

**Headers**:
```http
Authorization: Bearer <caregiver_token>
```

**Path Parameters**:
- `device_id` - Device identifier

**Response** (200 OK):
```json
{
  "device": {
    "device_id": "DEVICE001",
    "device_name": "Smart Vial Device",
    "battery_percent": 85,
    "firmware_version": "1.0.2",
    "is_online": true,
    "last_seen": "2026-02-02T10:00:00.000Z"
  },
  "recent_events": [
    {
      "event_type": "OPEN",
      "device_timestamp": "2026-02-02T09:00:00.000Z",
      "server_timestamp": "2026-02-02T09:00:05.000Z"
    }
  ],
  "total_events": 150
}
```

**Errors**:
- `403` - Caregiver doesn't have access to device

---

### Get All Caregiver Devices

Retrieve all devices assigned to the caregiver.

**Endpoint**: `GET /api/caregiver/devices`

**Headers**:
```http
Authorization: Bearer <caregiver_token>
```

**Response** (200 OK):
```json
{
  "devices": [
    {
      "device_id": "DEVICE001",
      "device_name": "Smart Vial Device",
      "battery_percent": 85,
      "firmware_version": "1.0.2",
      "is_online": true,
      "last_seen": "2026-02-02T10:00:00.000Z",
      "recent_events": [],
      "total_events": 150
    }
  ],
  "total_devices": 1
}
```

---

### Search Device by ID

Search for a specific device (caregiver must have access).

**Endpoint**: `GET /api/caregiver/search/device`

**Headers**:
```http
Authorization: Bearer <caregiver_token>
```

**Query Parameters**:
- `device_id` (required) - Device identifier

**Example**:
```http
GET /api/caregiver/search/device?device_id=DEVICE001
```

**Response** (200 OK):
```json
{
  "device": {
    "device_id": "DEVICE001",
    "device_name": "Smart Vial Device",
    "battery_percent": 85,
    "firmware_version": "1.0.2",
    "is_online": true,
    "last_seen": "2026-02-02T10:00:00.000Z"
  },
  "events": [],
  "total_events": 150
}
```

---

### Filter Events by Date Range

Filter device events by date range (caregiver view).

**Endpoint**: `GET /api/caregiver/events/filter/date`

**Headers**:
```http
Authorization: Bearer <caregiver_token>
```

**Query Parameters**:
- `device_id` (required) - Device identifier
- `start_date` (required) - Date string (YYYY-MM-DD or ISO 8601)
- `end_date` (required) - Date string (YYYY-MM-DD or ISO 8601)

**Example**:
```http
GET /api/caregiver/events/filter/date?device_id=DEVICE001&start_date=2026-01-01&end_date=2026-02-02
```

**Response** (200 OK):
```json
{
  "device_id": "DEVICE001",
  "device_name": "Smart Vial Device",
  "date_range": {
    "start": "2026-01-01T00:00:00.000Z",
    "end": "2026-02-02T00:00:00.000Z"
  },
  "events": [],
  "total_events": 45
}
```

---

## Device Ingestion APIs

Base path: `/api/ingest`

### Update Device Telemetry

ESP32 posts battery and firmware status.

**Endpoint**: `POST /api/ingest/telemetry`

**Headers** (per-device HMAC — see [Device Auth](DEVICE_AUTH.md)):
```http
x-device-id: DEVICE001
x-nonce: 42
x-timestamp: 1738483200
x-signature: <lowercase hex HMAC-SHA256>
Content-Type: application/json
```

**Request Body**:
```json
{
  "device_id": "DEVICE001",
  "battery_percent": 85,
  "firmware_version": "1.0.2"
}
```

**Response** (200 OK):
```json
{
  "status": "Device telemetry updated"
}
```

**Notes**:
- Send `battery_percent` (0–100). The legacy `battery` field is still accepted and
  normalized to `battery_percent`, preferring `battery_percent` when both are present.
- Creates device if it doesn't exist
- Updates `last_seen` timestamp automatically

---

### Ingest Event

ESP32 posts interaction event (open/close/etc).

**Endpoint**: `POST /api/ingest/event`

**Headers** (per-device HMAC — see [Device Auth](DEVICE_AUTH.md)):
```http
x-device-id: DEVICE001
x-nonce: 43
x-timestamp: 1738483200
x-signature: <lowercase hex HMAC-SHA256>
Content-Type: application/json
```

**Request Body**:
```json
{
  "device_id": "DEVICE001",
  "event": "OPEN",
  "event_id": "evt_unique_12345",
  "timestamp": 1738483200,
  "payload": {
    "duration": 5.2,
    "sensor_value": 123
  }
}
```

**Fields**:
- `device_id` (string, required) — must equal `x-device-id`.
- `event` (string, required) — case-insensitive, stored uppercase. Must be one of the
  allowed event types (otherwise **400**):
  `OPEN`, `CLOSE`, `BATTERY`, `LOW_BATTERY`, `HEARTBEAT`, `BOOT`, `TILT`, `TAMPER`.
- `event_id` (string, optional) — idempotency key.
- `timestamp` (number, optional) — unix seconds.
- `payload` (object, optional) — validated per `event_type` (zod). Known fields are
  type-checked; unknown extra fields are allowed (passthrough). Examples:
  `OPEN`/`CLOSE` → `{ duration, sensor_value }`; `BATTERY`/`LOW_BATTERY` →
  `{ battery, battery_percent, firmware_version }`; `TILT`/`TAMPER` →
  `{ sensor_value, angle }`.

The device must also exist and be **claimed**, otherwise the event is rejected with
**400** (`device not found` / `device not claimed by any user`).

**Response** (200 OK):
```json
{
  "status": "Event logged successfully"
}
```

**Duplicate Detection**:
If `event_id` already exists:
```json
{
  "status": "Duplicate event ignored"
}
```

---

## Error Responses

### Standard Error Format

All errors follow this structure:

```json
{
  "error": "Human-readable error message"
}
```

### Common HTTP Status Codes

| Code | Meaning | Common Causes |
|------|---------|---------------|
| 400 | Bad Request | Missing required fields, invalid data |
| 401 | Unauthorized | Missing/invalid better-auth session, or device HMAC auth failure |
| 413 | Payload Too Large | Request body exceeds the JSON body size limit |
| 429 | Too Many Requests | Rate limit exceeded |
| 403 | Forbidden | User doesn't own resource, role mismatch |
| 404 | Not Found | Device/user/event doesn't exist |
| 409 | Conflict | Device already claimed, duplicate entry |
| 500 | Server Error | Database error, unexpected exception |

### Example Error Responses

**Missing/Invalid User Session** (user/caregiver routes):
```json
{
  "error": "Access Denied: Invalid or missing authentication"
}
```

**Device Auth Failure** (ingestion routes — message is intentionally generic):
```json
{
  "success": false,
  "error": "Authentication failed."
}
```

**Rate Limited** (HTTP 429):
```json
{
  "error": "Too many requests, please try again later."
}
```

**Device Not Found**:
```json
{
  "error": "Device not found"
}
```

**Access Denied**:
```json
{
  "error": "Access denied: Only device owner can assign caregivers"
}
```

**Missing Required Field**:
```json
{
  "error": "device_id is required"
}
```

---

## Rate Limiting

Rate limiting is **active** (`express-rate-limit`). Exceeding a limit returns HTTP
**429** with a JSON body. Standardized `RateLimit-*` headers are sent
(`standardHeaders: true`); the legacy `X-RateLimit-*` headers are disabled
(`legacyHeaders: false`).

| Limiter   | Scope                              | Default window | Default max | Env overrides |
| --------- | ---------------------------------- | -------------- | ----------- | ------------- |
| General   | All routes                         | 15 min         | 100 / IP    | `RATE_LIMIT_WINDOW_MS`, `RATE_LIMIT_MAX_REQUESTS` |
| Ingestion | `/api/ingest/*`                    | 1 min          | 120 / IP    | `INGEST_RATE_LIMIT_WINDOW_MS`, `INGEST_RATE_LIMIT_MAX` |
| Auth      | `/api/user/*`, `/api/caregiver/*`  | 15 min         | 100 / IP    | `AUTH_RATE_LIMIT_WINDOW_MS`, `AUTH_RATE_LIMIT_MAX` |

**Standard headers** (example):
```http
RateLimit-Limit: 100
RateLimit-Remaining: 95
RateLimit-Reset: 600
```

---

## Pagination

Currently not implemented. APIs return:
- Device events: Last 100 records
- All user events: Last 500 records

Future enhancement: Add `limit` and `offset` query parameters.

---

## Versioning

Current version: v1 (implicit in base path)

No versioning strategy currently implemented. Future: `/api/v2/...`

---

**Last Updated**: June 27, 2026
