# Smart Vial IoT Backend

REST API backend for Smart Vial
---

## Quick Links

📖 **[Complete Documentation →](docs/README.md)**

Essential guides:
- **[API Reference](docs/API_REFERENCE.md)** - All endpoints with examples
- **[Quick Start](docs/DEVELOPMENT.md)** - Get running locally
- **[Authentication](docs/AUTHENTICATION.md)** - User (better-auth) + device (HMAC) auth
- **[Device Auth Wire Contract](docs/DEVICE_AUTH.md)** - Per-device HMAC signing scheme
- **[Deployment](docs/DEPLOYMENT.md)** - Production deployment guide
- **[Troubleshooting](docs/TROUBLESHOOTING.md)** - Common issues and fixes

---

## Overview

**Smart Vial** helps patients and caregivers track medication adherence through:
- 🔌 **ESP32 smart bottle caps** that detect when medications are accessed
- ☁️ **Cloud backend** (this repository) that receives and stores interaction data
- 📱 **Mobile applications** for patients and caregivers to view adherence history

### System Components

```
ESP32 Device → Cloud Backend → Mobile Apps
                (This Repo)
```

---

## Features

✅ **Device Management**
- Register and claim smart bottle cap devices
- Track battery levels and firmware versions
- Multi-user support (patient + caregiver)

✅ **Event Tracking**
- Log typed device events (OPEN/CLOSE, BATTERY, HEARTBEAT, BOOT, TILT, TAMPER, …)
- Per-`event_type` payload validation (zod)
- Timestamp-based adherence tracking
- Idempotent event ingestion (prevents duplicates)

✅ **Dual Role System**
- Users can be patients (own devices)
- Users can be caregivers (monitor others' devices)
- Same user can have both roles simultaneously

✅ **Security**
- User/caregiver auth via **better-auth** session validation (shared PostgreSQL store)
- Device auth via **per-device HMAC-SHA256** signing with replay protection
- `helmet` security headers, CORS allowlist, and active rate limiting
- NoSQL operator-injection sanitization on every request

✅ **RESTful APIs**
- User/Patient APIs for device ownership
- Caregiver APIs for monitoring
- Device ingestion APIs for telemetry and events

---

## Tech Stack

- **Runtime**: Node.js, Express.js (Express 5)
- **Databases (dual-store)**:
  - **MongoDB** (Mongoose ODM) — devices, events, telemetry
  - **PostgreSQL** — shared **better-auth** identity/session store (accessed via `pg`)
- **User authentication**: better-auth session validation (NOT raw JWT)
- **Device authentication**: per-device HMAC-SHA256 signatures (NOT a shared API key)
- **Validation**: zod (event payloads), request sanitization middleware
- **Hardening**: helmet, cors (allowlist), express-rate-limit

> **Note on data stores.** Device, event, and telemetry data live in **MongoDB**.
> User identity and sessions live in a **PostgreSQL** database shared with the main
> application; this backend validates sessions against it through better-auth. There
> is no Mongo `User`-collection-based login — the local `User` model only mirrors
> roles and device-claim lists keyed by the better-auth user id.

---

## Quick Start

### Prerequisites

- Node.js (LTS recommended)
- MongoDB database (MongoDB Atlas recommended) for device/event data
- Access to the shared PostgreSQL / better-auth database used by the main app
- npm or pnpm

### Installation

1. **Clone repository**:
   ```bash
   git clone <your-repo-url>
   cd smart-vial-backend
   ```

2. **Install dependencies**:
   ```bash
   npm install
   ```

3. **Configure environment** (`.env`):
   ```env
   # Server
   PORT=5000
   NODE_ENV=development

   # MongoDB (device/event/telemetry store)
   MONGO_URI=your_mongodb_connection_string

   # PostgreSQL / better-auth (shared identity store)
   DATABASE_URL=postgres://user:pass@host:5432/dbname
   BETTER_AUTH_URL=http://localhost:5000

   # Device auth (per-device HMAC secrets are encrypted at rest)
   DEVICE_SECRET_ENC_KEY=64_char_hex_32_byte_master_key
   TYME_SYNC_TOLERANCE_SECONDS=300

   # CORS + rate limiting (optional; sensible defaults exist)
   CORS_ORIGINS=https://app.example.com,https://admin.example.com
   RATE_LIMIT_WINDOW_MS=900000
   RATE_LIMIT_MAX_REQUESTS=100
   ```

   > `Server.js` connects to MongoDB with `process.env.MONGO_URI`. The better-auth
   > middleware connects to PostgreSQL with `process.env.DATABASE_URL`.

4. **Start server**:
   ```bash
   # Development (auto-restart with nodemon, if installed)
   npm run dev

   # Production
   npm start
   ```

---

## API Overview

### User/Patient APIs (`/api/user`)

- `POST /save` - Create/update user record (mirrors better-auth identity locally)
- `POST /claim` - Claim ownership of a device
- `GET /devices` - List your devices
- `GET /devices/:device_id/events` - Get device events
- `GET /events/all` - Get events across all your devices
- `GET /devices/:device_id/events/search` - Search a device's events by time range
- `DELETE /devices/:device_id/unclaim` - Release device ownership
- `DELETE /devices/:device_id/events` - Delete a device's events
- `DELETE /devices/:device_id/caregiver` - Remove caregiver access

### Caregiver APIs (`/api/caregiver`)

- `POST /claim-device` - Assign caregiver to device
- `GET /devices` - List devices you're monitoring
- `GET /devices/:device_id/summary` - Device summary with latest events
- `GET /search/device` - Search a device by `device_id`
- `GET /events/filter/date` - Filter events by date range

### Device Ingestion APIs (`/api/ingest`)

- `POST /telemetry` - Update battery (`battery_percent`) and firmware version
- `POST /event` - Log a typed device event

**Authentication**:
- User/Caregiver APIs: better-auth session — sent as a session cookie **or**
  `Authorization: Bearer <session_token>` (validated against PostgreSQL via better-auth).
- Device APIs: per-device HMAC headers
  `x-device-id`, `x-nonce`, `x-timestamp`, `x-signature`
  (see **[Device Auth](docs/DEVICE_AUTH.md)**).

📘 **[Full API Documentation →](docs/API_REFERENCE.md)**

---

## Project Structure

```
smart-vial-backend/
├── Server.js                 # App entry: helmet, CORS, rate limiting, routes, Mongo connect
├── config/
│   └── config.js             # Environment configuration
├── models/                   # MongoDB (Mongoose) models
│   ├── User.js               # Local role/claim mirror keyed by better-auth user id
│   ├── Device.js             # Smart bottle cap registry + encrypted device credential
│   └── Event.js              # Typed interaction event log
├── controllers/
│   ├── app.api.controller.js         # User API logic
│   ├── caregiver.controller.js       # Caregiver API logic
│   ├── ingestion.controller.js       # Device ingestion logic
│   └── saveUserController.js         # User save/provisioning logic
├── routes/
│   ├── userAPI.js            # User endpoint routes
│   ├── caregiverAPI.js       # Caregiver endpoint routes
│   └── ingestionAPI.js       # Device ingestion routes
├── middleware/
│   ├── verifyUserToken.js    # better-auth session validation (PostgreSQL)
│   ├── authDevice.js         # Per-device HMAC auth + replay protection
│   └── sanitize.js           # NoSQL operator-injection sanitization
├── utils/
│   ├── deviceAuth.js         # Pure HMAC verification (wire contract)
│   ├── deviceCredentials.js  # AES-256-GCM encrypt/decrypt of device secrets
│   ├── deviceClaim.js        # Device claim helpers
│   ├── eventValidation.js    # zod event-type/payload validation
│   └── userProvisioning.js   # User provisioning helpers
└── docs/                     # Complete documentation
    ├── README.md             # Documentation index
    ├── API_REFERENCE.md      # API endpoints
    ├── AUTHENTICATION.md      # Auth guide (better-auth + device HMAC)
    ├── DEVICE_AUTH.md         # Device HMAC wire contract
    ├── DEVELOPMENT.md         # Local development
    ├── DEPLOYMENT.md          # Production deployment
    ├── DATABASE_SCHEMA.md     # Data models (MongoDB) + identity store
    ├── ARCHITECTURE.md        # System architecture
    └── TROUBLESHOOTING.md     # Common issues
```

---

## Development

### Available Scripts

```bash
# Start server
npm start          # node Server.js
npm run dev        # node Server.js (use nodemon for auto-restart in dev)

# Run tests
npm test           # node --test
```

> The old `generateTestToken.js` / `testJWT.js` helpers were removed when raw-JWT
> auth was replaced by better-auth. To exercise authenticated user endpoints, obtain
> a real better-auth session from the main app and send it as a cookie or bearer token.

### Testing APIs

User/caregiver endpoint (better-auth session as bearer token):
```bash
curl -H "Authorization: Bearer <better_auth_session_token>" \
  http://localhost:5000/api/user/devices
```

Device ingestion requires a signed request — see **[Device Auth](docs/DEVICE_AUTH.md)**
for how to compute `x-signature`.

📘 **[Development Guide →](docs/DEVELOPMENT.md)**

---

## Rate Limiting

Rate limiting is **active** (`express-rate-limit`) and returns HTTP **429** when
exceeded. Standardized `RateLimit-*` headers are sent (`standardHeaders: true`);
the legacy `X-RateLimit-*` headers are disabled.

| Limiter   | Scope                          | Default window | Default max |
| --------- | ------------------------------ | -------------- | ----------- |
| General   | All routes                     | 15 min         | 100 / IP    |
| Ingestion | `/api/ingest/*`                | 1 min          | 120 / IP    |
| Auth      | `/api/user/*`, `/api/caregiver/*` | 15 min      | 100 / IP    |

Windows/limits are configurable via env (`RATE_LIMIT_*`, `INGEST_RATE_LIMIT_*`,
`AUTH_RATE_LIMIT_*`). See [API Reference](docs/API_REFERENCE.md#rate-limiting).

---

## Security

🔐 **Authentication**:
- **better-auth** session validation for user/caregiver endpoints (shared PostgreSQL store)
- **Per-device HMAC-SHA256** signatures for device endpoints, with monotonic-nonce
  replay protection and a timestamp freshness window
- Ownership/role validation on all operations

🛡️ **Hardening**:
- `helmet` security headers
- CORS allowlist (`CORS_ORIGINS`); requests with no `Origin` (native devices, curl)
  are allowed so device ingestion keeps working
- Active rate limiting (429) on general, ingestion, and auth surfaces
- NoSQL operator-injection sanitization (strips `$`-prefixed/dotted keys)
- Per-device secrets encrypted at rest (AES-256-GCM); plaintext never stored
- Use HTTPS in production

📘 **[Security & Auth Guide →](docs/AUTHENTICATION.md)**

---

## Environment Variables

Required/important configuration in `.env`:

```env
# Server
PORT=5000
NODE_ENV=production

# MongoDB (devices/events/telemetry)
MONGO_URI=mongodb+srv://user:pass@cluster.mongodb.net/dbname

# PostgreSQL / better-auth (shared identity store)
DATABASE_URL=postgres://user:pass@host:5432/dbname
BETTER_AUTH_URL=https://your-server.com

# Device auth
DEVICE_SECRET_ENC_KEY=64-char-hex-32-byte-master-key   # required in prod
TYME_SYNC_TOLERANCE_SECONDS=300

# CORS + rate limiting
CORS_ORIGINS=https://app.example.com
RATE_LIMIT_WINDOW_MS=900000
RATE_LIMIT_MAX_REQUESTS=100
```

📘 **[Environment Configuration →](docs/DEPLOYMENT.md)**

---

## API Examples

### Claim a Device

```bash
curl -X POST http://localhost:5000/api/user/claim \
  -H "Authorization: Bearer <better_auth_session_token>" \
  -H "Content-Type: application/json" \
  -d '{"device_id": "DEVICE001"}'
```

### Get Device Events

```bash
curl -H "Authorization: Bearer <better_auth_session_token>" \
  http://localhost:5000/api/user/devices/DEVICE001/events
```

### Log a Device Event (from ESP32)

Device requests are signed with per-device HMAC headers (no shared API key):

```bash
curl -X POST http://localhost:5000/api/ingest/event \
  -H "x-device-id: DEVICE001" \
  -H "x-nonce: 42" \
  -H "x-timestamp: 1738483200" \
  -H "x-signature: <lowercase_hex_hmac_sha256>" \
  -H "Content-Type: application/json" \
  -d '{"device_id":"DEVICE001","event":"OPEN","event_id":"unique_id_123"}'
```

See **[Device Auth](docs/DEVICE_AUTH.md)** for exactly how `x-signature` is computed.

📘 **[More Examples →](docs/API_REFERENCE.md)**

---

## Documentation

Complete documentation is available in the [`docs/`](docs/) folder:

| Document | Description |
|----------|-------------|
| [README](docs/README.md) | Documentation index and overview |
| [API Reference](docs/API_REFERENCE.md) | Complete API endpoint documentation |
| [Authentication](docs/AUTHENTICATION.md) | better-auth (users) + device HMAC setup |
| [Device Auth](docs/DEVICE_AUTH.md) | Per-device HMAC wire contract |
| [Database Schema](docs/DATABASE_SCHEMA.md) | Data models and stores |
| [Development](docs/DEVELOPMENT.md) | Local development guide |
| [Deployment](docs/DEPLOYMENT.md) | Production deployment |
| [Architecture](docs/ARCHITECTURE.md) | System architecture and design |
| [Troubleshooting](docs/TROUBLESHOOTING.md) | Common issues and solutions |

---

## License

SOFTWARE LICENSE AND OWNERSHIP TRANSFER
Project: smart vial api

Developer: n Chathu

Client: kevon

Date: February 3, 2026

1. Transfer of Rights: Upon final payment and delivery, the Developer hereby assigns and transfers all intellectual property rights, title, and interest in the software to the Client.

2. Grant of License: The Developer provides the Client with a perpetual, irrevocable, worldwide license to use, modify, and distribute the source code.

3. Warranty & Liability: The software is provided "as is" without warranty of any kind. The Developer is not liable for any damages resulting from the use or inability to use the software.

4. Third-Party Libraries: This software utilizes [e.g., Node.js, Express, MongoDB, PostgreSQL]. These components remain subject to their respective open-source licenses (MIT, Apache, etc.).
