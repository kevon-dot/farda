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

**Database**: MongoDB (Mongoose ODM)

**Collections**:
- `devices` - Device registry
- `events` - Event store (append-only)
- `users` - User accounts

**Connection String**:
```env
MONGO_URI=mongodb+srv://user:password@cluster.mongodb.net/database
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
  
  // Ownership
  user_id: String | null,      // Owner's user ID
  claimed: Boolean,            // Is device claimed?
  claimed_at: Date | null,     // When was it claimed
  caregiver_id: String | null, // Assigned caregiver ID
  
  // Status & Telemetry
  battery_percent: Number,     // 0-100
  firmware_version: String,    // e.g., "1.0.2"
  isActive: Boolean,           // Is device active
  last_seen: Date,             // Last communication timestamp
  
  // Timestamps (auto-managed)
  createdAt: Date,
  updatedAt: Date
}
//example data set 

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
  idempotency_key: String | null,  // Unique event ID (optional) // strongly recomnd 
  
  // Device Reference
  device_id: String,               // Which device
  
  // Event Data
  event_type: String,              
  payload: Object,                 // Additional event data
  
  // Timestamps
  device_timestamp: Date | null,   // Time from device
  server_timestamp: Date,          // Time received by server
  
  // Metadata (auto-managed)
  createdAt: Date,
  updatedAt: Date
}
```
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
  "createdAt": "2026-02-02T09:00:05.123Z",
  "updatedAt": "2026-02-02T09:00:05.123Z"
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



**Last Updated**: February 3, 2026
