# Smart Vial Backend Documentation

Complete documentation for the Smart Vial IoT backend system.

## 📚 Documentation Index

### Getting Started
- [Development Setup](DEVELOPMENT.md) - Local environment setup
- [Architecture Overview](ARCHITECTURE.md) - System design and components

### API Documentation
- [API Reference](API_REFERENCE.md) - Complete API endpoint documentation
- [Authentication Guide](AUTHENTICATION.md) - better-auth sessions (users) + device HMAC
- [Device Auth Contract](DEVICE_AUTH.md) - Per-device HMAC signing wire format

### Technical Details
- [Database Schema](DATABASE_SCHEMA.md) - Data models (MongoDB) and the identity store

### Deployment & Operations
- [Deployment Guide](DEPLOYMENT.md) - Production deployment steps
- [Troubleshooting](TROUBLESHOOTING.md) - Common issues and solutions


---

## 🚀 Quick Start

### Prerequisites
```bash
- Node.js (LTS recommended)
- MongoDB (device/event/telemetry store)
- PostgreSQL / better-auth (shared identity store, same as the main app)
- npm or pnpm
```

1. **Configure environment**
```bash
# Set MONGO_URI, DATABASE_URL, BETTER_AUTH_URL, DEVICE_SECRET_ENC_KEY in .env
```

2. **Start the server**
```bash
npm start
# or for development
npm run dev
```

Server runs on `http://localhost:5000`.

> User endpoints require a real **better-auth** session (cookie or bearer token)
> obtained from the main app — there is no local test-token generator anymore.
> Device endpoints require a signed HMAC request (see [Device Auth](DEVICE_AUTH.md)).

---

## 📖 Project Overview

### What is Smart Vial?

Smart Vial is an IoT-enabled medication adherence tracking system consisting of:

- **ESP32-based smart caps** that detect bottle openings/closings
- **Cloud backend** (this project) that stores events and telemetry
- **Mobile app** for patients and caregivers to view adherence data

### System Components

```
┌─────────────┐  HMAC   ┌──────────────┐  APIs   ┌──────────────┐
│   ESP32     ├────────►│   Backend    ├────────►│  Mobile App  │
│  Devices    │         │   Server     │         │   (User/CG)  │
└─────────────┘         └──────┬───────┘         └──────────────┘
                               │
                ┌──────────────┴──────────────┐
                ▼                              ▼
        ┌──────────────┐              ┌──────────────────┐
        │   MongoDB    │              │   PostgreSQL     │
        │ devices/     │              │ better-auth      │
        │ events/      │              │ identity/        │
        │ telemetry    │              │ sessions         │
        └──────────────┘              └──────────────────┘
```

### Key Features

✅ **Multi-device support** - Users can claim multiple smart bottles
✅ **Dual role system** - Users can be both patients and caregivers
✅ **Real-time telemetry** - Battery levels (`battery_percent`), firmware
✅ **Typed event tracking** - OPEN/CLOSE + BATTERY/HEARTBEAT/BOOT/TILT/TAMPER, payloads validated per `event_type`
✅ **Caregiver dashboards** - Read-only views for caregivers
✅ **Idempotent ingestion** - Prevents duplicate events
✅ **Secure authentication** - better-auth sessions for users, per-device HMAC for devices
✅ **Hardening** - helmet, CORS allowlist, active rate limiting, NoSQL injection sanitization

---

## 🏗️ Architecture

### Technology Stack

**Backend**
- Runtime: Node.js with Express.js (Express 5)
- Device/event data store: MongoDB with Mongoose ODM
- Identity store: PostgreSQL (shared **better-auth** database, accessed via `pg`)
- User authentication: better-auth session validation (not raw JWT)
- Device authentication: per-device HMAC-SHA256 signatures (not a shared API key)
- Validation/hardening: zod, helmet, cors (allowlist), express-rate-limit, request sanitization

**Cloud Agnostic**
- Can deploy on AWS, GCP, Azure, or any VPS
- Typically MongoDB Atlas for device data + the main app's PostgreSQL for identity

### Directory Structure

```
smart-vial-backend/
├── config/                 # Configuration files
│   └── config.js          # Main config loader
├── controllers/            # Business logic
│   ├── app.api.controller.js       # User endpoints
│   ├── caregiver.controller.js     # Caregiver endpoints
│   ├── ingestion.controller.js     # Device ingestion
│   └── saveUserController.js        # User save/provisioning
├── middleware/            # Express middleware
│   ├── authDevice.js      # Per-device HMAC auth + replay protection
│   ├── verifyUserToken.js # better-auth session validation (PostgreSQL)
│   └── sanitize.js        # NoSQL operator-injection sanitization
├── models/                # MongoDB schemas
│   ├── Device.js          # Device registry + encrypted credential
│   ├── Event.js           # Typed event store
│   └── User.js            # Local role/claim mirror (keyed by better-auth user id)
├── routes/                # API routes
│   ├── userAPI.js         # /api/user/*
│   ├── caregiverAPI.js    # /api/caregiver/*
│   └── ingestionAPI.js    # /api/ingest/*
├── utils/                 # Helper utilities
│   ├── deviceAuth.js      # Pure HMAC verification (wire contract)
│   ├── deviceCredentials.js # AES-256-GCM device-secret encryption
│   ├── deviceClaim.js     # Device claim helpers
│   ├── eventValidation.js # zod event validation
│   └── userProvisioning.js
├── docs/                  # Documentation (you are here)
├── .env                   # Environment variables
├── Server.js              # Application entry point (Mongo connect, security, routes)
└── package.json           # Dependencies
```

---

## 🔐 Authentication Overview

### For Users & Caregivers (better-auth session)

Send a better-auth session — a session cookie or a bearer token — validated by
`middleware/verifyUserToken.js` against the shared PostgreSQL store:

```http
Authorization: Bearer <better_auth_session_token>
```

Configure in `.env`:
```env
DATABASE_URL=postgres://user:pass@host:5432/dbname   # same DB as the main app
BETTER_AUTH_URL=https://your-server.com
```

### For Devices (per-device HMAC)

Each ingestion request is signed with the device's own secret (no shared API key):

```http
x-device-id: DEVICE001
x-nonce: 42
x-timestamp: 1738483200
x-signature: <lowercase hex HMAC-SHA256>
```

Configure in `.env`:
```env
DEVICE_SECRET_ENC_KEY=64-char-hex-32-byte-master-key   # encrypts device secrets at rest
TYME_SYNC_TOLERANCE_SECONDS=300
```

See [Authentication Guide](AUTHENTICATION.md) and the [Device Auth Contract](DEVICE_AUTH.md).

---

## 📡 API Overview

### User APIs (`/api/user`)
- Claim devices
- View device status and events
- Manage caregiver access
- Search event history

### Caregiver APIs (`/api/caregiver`)
- View assigned devices
- Access patient adherence data (read-only)
- Filter events by date range

### Device APIs (`/api/ingest`)
- Update telemetry (battery, firmware)
- Post interaction events

See [API Reference](API_REFERENCE.md) for complete documentation.

---

## 🗄️ Data Models

> Device, Event, and telemetry data live in **MongoDB**. User identity/sessions
> live in **PostgreSQL** (better-auth). The Mongo `User` model below is only a local
> mirror of roles/claims keyed by the better-auth user id.

### Device (MongoDB)
```javascript
{
  device_id: "DEVICE001",
  user_id: "better-auth-user-id",
  caregiver_id: "better-auth-user-id",
  battery_percent: 85,
  firmware_version: "1.0.2",
  last_seen: Date,
  claimed: true,
  // Per-device HMAC auth state (select:false credential):
  credential: { ciphertext, iv, tag, version, issued_at }, // AES-256-GCM, hidden by default
  revoked: false,
  last_nonce: 41               // highest accepted nonce (replay watermark)
}
```

### Event (MongoDB)
```javascript
{
  device_id: "DEVICE001",
  event_type: "OPEN",          // OPEN/CLOSE/BATTERY/LOW_BATTERY/HEARTBEAT/BOOT/TILT/TAMPER
  device_timestamp: Date,
  server_timestamp: Date,
  idempotency_key: "unique-id",
  payload: {}                  // validated per event_type (zod)
}
```

### User (MongoDB — local mirror)
```javascript
{
  user_id: "better-auth-user-id",   // the better-auth user id, not a Mongo ObjectId
  user_roles: ["user", "caregiver"],
  claim_device_ids: ["DEVICE001", "DEVICE002"],
  caregiving_device_ids: ["DEVICE003"],
  lastLogin: Date
}
```

See [Database Schema](DATABASE_SCHEMA.md) for complete details.

---


## 📄 License

1. Transfer of Rights: Upon final payment and delivery, the Developer hereby assigns and transfers all intellectual property rights, title, and interest in the software to the Client.

2. Grant of License: The Developer provides the Client with a perpetual, irrevocable, worldwide license to use, modify, and distribute the source code.

3. Warranty & Liability: The Developer is not liable for any damages resulting from the use or inability to use the software.

4. Third-Party Libraries: This software utilizes [e.g., Node.js, Express, MongoDB, PostgreSQL, better-auth]. These components remain subject to their respective open-source licenses (MIT, Apache, etc.).




**Last Updated**: June 27, 2026
