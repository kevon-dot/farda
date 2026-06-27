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


//////////////////////////////////////////////////////////

## Authentication

### User & Caregiver Authentication (JWT)

All user and caregiver endpoints require JWT Bearer token:

```http
Authorization: Bearer <token>
```

**Token Structure**:
```json
{
  "sub": "user_id",
  "role": "user" | "caregiver",
 
  "iat": 1234567890,
  "exp": 1234567890
}



//////////////////////////////////////////////////////////////
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
////////////////////////////////////////////////////////////////////////////////////////////////////////
## Caregiver APIs

Base path: `/api/caregiver`

### Assign Caregiver to Device

Device owner assigns a caregiver to their device.

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
  "status": "Caregiver assigned successfully",
  "device": {
    "device_id": "DEVICE001",
    "device_name": "Smart Vial Device",
    "caregiver_id": "65def456abc123789"
  }
}
```

**Errors**:
- `403` - User is not device owner
- `404` - Caregiver not found

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

**Headers**:
```http
X-API-Key: your-strong-device-api-key
Content-Type: application/json
```

**Request Body**:
```json
{
  "device_id": "DEVICE001",
  "battery": 85,
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
- Creates device if doesn't exist
- Updates `last_seen` timestamp automatically
- Battery should be 0-100

---

### Ingest Event

ESP32 posts interaction event (open/close/etc).

**Endpoint**: `POST /api/ingest/event`

**Headers**:
```http
X-API-Key: your-strong-device-api-key
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
| 401 | Unauthorized | Missing or invalid auth token/API key |
| 403 | Forbidden | User doesn't own resource, role mismatch |
| 404 | Not Found | Device/user/event doesn't exist |
| 409 | Conflict | Device already claimed, duplicate entry |
| 500 | Server Error | Database error, unexpected exception |

### Example Error Responses

**Missing Authentication**:
```json
{
  "error": "Access Denied: No token provided"
}
```

**Invalid Token**:
```json
{
  "error": "Invalid or expired token"
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

Current configuration (from config):
- Window: 6000000ms (100 minutes)
- Max requests: 100

**Rate limit headers**:
```http
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 95
X-RateLimit-Reset: 1738489200
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

**Last Updated**: February 3, 2026
