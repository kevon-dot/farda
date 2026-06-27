# Database Schema



---

## Table of Contents

1. [Overview](#overview)
2. [Device Model](#device-model)
3. [Event Model](#event-model)
4. [User Model](#user-model)
5. [Indexes](#indexes)
6. [Relationships](#relationships)

---

## Overview

This backend uses a **dual data store**:

- **MongoDB** (Mongoose ODM) — device, event, and telemetry data (this document).
- **PostgreSQL** — the shared **better-auth** identity/session store, owned by the
  main application. This submodule validates sessions against it via better-auth
  (`middleware/verifyUserToken.js`) but does **not** define its schema here.

**MongoDB collections**:
- `devices` - Device registry (incl. encrypted per-device auth credential)
- `events` - Typed event store (append-only)
- `users` - **Local mirror** of roles/claims keyed by the better-auth user id
  (NOT the authoritative login store — that lives in PostgreSQL)

**Connection strings**:
```env
# MongoDB (Server.js connects with process.env.MONGO_URI)
MONGO_URI=mongodb+srv://user:password@cluster.mongodb.net/database

# PostgreSQL / better-auth (verifyUserToken connects with process.env.DATABASE_URL)
DATABASE_URL=postgres://user:password@host:5432/database
```

---

## Device Model

**Collection**: `devices`

**File**: `models/Device.js`

### Schema

```javascript
{
  // Identification
  device_id: String,           // Unique device identifier
  device_name: String,         // Display name

  // Ownership (IDs are better-auth user ids, stored as strings)
  user_id: String | null,      // Owner's user id
  claimed: Boolean,            // Is device claimed?
  claimed_at: Date | null,     // When was it claimed
  caregiver_id: String | null, // Assigned caregiver id

  // Status & Telemetry
  battery_percent: Number,     // 0-100
  firmware_version: String,    // e.g., "1.0.2"
  isActive: Boolean,           // Is device active
  last_seen: Date,             // Last communication timestamp

  // Per-device authentication (A3 — see DEVICE_AUTH.md)
  credential: {                // AES-256-GCM encrypted device secret; select:false
    ciphertext: String,
    iv: String,
    tag: String,
    version: Number,           // bumped on each rotation
    issued_at: Date
  } | null,
  revoked: Boolean,            // revoked devices cannot authenticate
  revoked_at: Date | null,
  last_nonce: Number,          // highest accepted nonce (replay watermark; starts -1)

  // Timestamps (auto-managed)
  createdAt: Date,
  updatedAt: Date
}
```

> The `credential` subdocument is marked `select: false`, so it is **never returned
> by default queries**; the ingestion auth path explicitly selects it. The plaintext
> secret is decrypted into memory only at signature-verification time and is never
> stored. Credential lifecycle methods: `issueCredential()`, `rotateCredential()`,
> `revokeCredential()`, `getSecret()` (see `models/Device.js` and DEVICE_AUTH.md).

Example document:

```json
{
  "_id": "ObjectId(507f1f77bcf86cd799439011)",
  "device_id": "DEVICE001",
  "device_name": "Smart Vial Device",
  "user_id": "65abc123def456789",
  "claimed": true,
  "claimed_at": "2026-01-15T10:00:00.000Z",
  "caregiver_id": "65def456abc123789",
  "battery_percent": 85,
  "firmware_version": "1.0.2",
  "isActive": true,
  "last_seen": "2026-02-02T10:00:00.000Z",
  "createdAt": "2026-01-01T00:00:00.000Z",
  "updatedAt": "2026-02-02T10:00:00.000Z"
}
```

### Validation Rules

- `device_id`: Required, unique, trimmed
- `device_name`: Required, trimmed
- `battery_percent`: Min 0, Max 100
- `user_id`: Can be null (unclaimed devices)

---

## Event Model

**Collection**: `events`

**File**: `models/Event.js`

### Schema

```javascript
{
  // Identification
  idempotency_key: String | null,  // Unique event id (optional; sparse-unique index)

  // Device Reference
  device_id: String,               // Which device

  // Event Data
  event_type: String,              // uppercase; one of the allowed types (see below)
  payload: Object,                 // type-specific, validated per event_type (zod)

  // Timestamps
  device_timestamp: Date | null,   // Time from device (from request `timestamp`, unix s)
  server_timestamp: Date,          // Time received by server
  time_drift_seconds: Number,      // server_time - device_time, in seconds

  processed: Boolean,              // processing flag (default false)

  // Metadata (auto-managed)
  createdAt: Date                  // NOTE: only createdAt; updatedAt is disabled
}
```

**Allowed `event_type` values** (others are rejected at validation):
`OPEN`, `CLOSE`, `BATTERY`, `LOW_BATTERY`, `HEARTBEAT`, `BOOT`, `TILT`, `TAMPER`.

**Payload validation**: payloads are validated against a per-`event_type` zod schema
both in the ingestion controller and again in the model's `pre("validate")` hook
(defense-in-depth), so no code path can persist an unknown type or malformed payload.
Known fields are strictly typed; unknown extra fields are allowed (passthrough).
**How it works**:
1. Device sends `event_id` (optional)
2. Stored as `idempotency_key`
3. Unique index enforces one event per key
4. Duplicate requests return `200` without creating new event

**Example**:
```json
{
  "event_id": "evt_12345",  // Sent by device
  // Stored as:
  "idempotency_key": "evt_12345"
}
```

### Example Document

```json
{
  "_id": "ObjectId(507f1f77bcf86cd799439011)",
  "idempotency_key": "evt_abc123",
  "device_id": "DEVICE001",
  "event_type": "OPEN",
  "payload": {
    "duration": 5.2,
    "sensor_value": 123
  },
  "device_timestamp": "2026-02-02T09:00:00.000Z",
  "server_timestamp": "2026-02-02T09:00:05.123Z",
  "time_drift_seconds": 5,
  "processed": false,
  "createdAt": "2026-02-02T09:00:05.123Z"
}
```

### Validation Rules

- `device_id`: Required
- `event_type`: Required, converted to uppercase
- `idempotency_key`: Optional, but unique if provided (sparse index)

### Querying Events

**By device**:
```javascript
Event.find({ device_id: "DEVICE001" })
  .sort({ server_timestamp: -1 })
  .limit(100);
```

**By time range**:
```javascript
Event.find({
  device_id: "DEVICE001",
  server_timestamp: {
    $gte: new Date("2026-01-01"),
    $lte: new Date("2026-02-02")
  }
});
```

**By event type**:
```javascript
Event.find({
  device_id: "DEVICE001",
  event_type: "OPEN"
});
```

**Purpose**: User lookup, role filtering, device relationship queries

---

## User Model

**Collection**: `users` (MongoDB)

**File**: `models/User.js`

This is a **local mirror** used for role and device-claim lookups. The authoritative
user identity and sessions live in **PostgreSQL** (better-auth); `user_id` here is the
better-auth user id, not a Mongo ObjectId.

### Schema

```javascript
{
  user_id: String,                  // better-auth user id (unique)
  user_roles: [String],             // subset of ["caregiver", "user"]; must be non-empty
  claim_device_ids: [String],       // devices this user owns
  caregiving_device_ids: [String],  // devices this user monitors as a caregiver
  createdAt: Date,
  lastLogin: Date
}
```

### Validation Rules

- `user_id`: Required, unique, indexed
- `user_roles`: Enum `['caregiver', 'user']`; must contain at least one role
- Instance helpers: `hasRole(role)`, `addRole(role)`, `removeRole(role)`

---

## Relationships

### Entity Relationship Diagram

```
┌──────────┐       owns        ┌──────────┐
│   User   │ ─────────────────►│  Device  │
│          │  claim_device_ids │          │
└──────────┘                   └──────────┘
     │                              │
     │ caregiving_device_ids        │
     │                              │
     └──────────────────────────────┘
            cares for

┌──────────┐                   ┌──────────┐
│  Device  │ ─────────────────►│  Event   │
│          │     generates     │          │
└──────────┘                   └──────────┘
```



**Last Updated**: June 27, 2026
