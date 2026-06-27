# Architecture Overview

System architecture and design documentation.

---

## System Overview

Smart Vial is an IoT medication adherence tracking system consisting of three main components:

```
┌─────────────────┐         ┌──────────────────┐         ┌──────────────────┐
│   ESP32 Smart   │  HMAC   │   Cloud Backend  │  APIs   │   Mobile Apps    │
│   Bottle Caps   │ ───────►│   (This System)  │ ───────►│  (User/Caregiver)│
│                 │         │                  │         │                  │
│  - Sensors      │         │  - REST APIs     │         │  - Patient View  │
│  - WiFi         │         │  - Auth          │         │  - Caregiver View│
│  - Battery      │         │  - Data Storage  │         │  - Dashboards    │
└─────────────────┘         └────────┬─────────┘         └──────────────────┘
                                     │
                     ┌───────────────┴────────────────┐
                     ▼                                ▼
            ┌──────────────────┐            ┌──────────────────────┐
            │   MongoDB        │            │   PostgreSQL         │
            │   - Devices      │            │   - better-auth      │
            │   - Events       │            │     identity/sessions│
            │   - Telemetry    │            │   (shared w/ main app)│
            └──────────────────┘            └──────────────────────┘
```

**Dual data store**: device/event/telemetry data lives in **MongoDB**; user
identity and sessions live in a **PostgreSQL** database shared with the main app
and validated via **better-auth**. The Mongo `users` collection is only a local
mirror of roles and device-claim lists keyed by the better-auth user id.

---

## Component Architecture

### Backend Server (Node.js + Express)

```
┌─────────────────────────────────────────────┐
│              Express Server                  │
├─────────────────────────────────────────────┤
│                                             │
│  ┌───────────┐  ┌──────────────┐  ┌──────────┐│
│  │  Routes   │  │ Middleware   │  │Controllers││
│  │           │  │              │  │           ││
│  │ userAPI   │  │ verifyUser   │  │ User APIs ││
│  │caregiverAPI│─►│ Token (b-a)  │─►│Caregiver  ││
│  │ingestionAPI│  │ authDevice   │  │Ingestion  ││
│  │           │  │ sanitize     │  │           ││
│  │           │  │ helmet/CORS/ │  │           ││
│  │           │  │ rateLimit    │  │           ││
│  └───────────┘  └──────────────┘  └──────────┘│
│                                             │
│  ┌─────────────────────────────────────────┐│
│  │         Models (Mongoose ODM)           ││
│  │                                         ││
│  │  Device  │  Event  │  User (mirror)     ││
│  └─────────────────────────────────────────┘│
│              │                  │            │
└──────────────┼──────────────────┼───────────┘
               ▼                  ▼
        ┌──────────────┐   ┌──────────────┐
        │   MongoDB    │   │  PostgreSQL  │
        │ device/event │   │ better-auth  │
        └──────────────┘   └──────────────┘
```

> `verifyUserToken` validates better-auth sessions against PostgreSQL; `authDevice`
> enforces per-device HMAC over the request. The global middleware chain in
> `Server.js` is: helmet → CORS allowlist → JSON body parsing (with raw-body capture)
> → NoSQL sanitize → general rate limiter, then per-router ingestion/auth limiters.



## API Layer Architecture

### Route Organization

```
/api/
├── /user/              # User/patient endpoints
│   ├── POST /save                       # Create/update user
│   ├── POST /claim                      # Claim device
│   ├── GET /devices                     # List user's devices
│   ├── GET /devices/:id/events          # Device events
│   ├── GET /events/all                  # All events
│   ├── GET /devices/:id/events/search   # Time range query
│   ├── DELETE /devices/:id/unclaim      # Unclaim device
│   ├── DELETE /devices/:id/events       # Delete events
│   └── DELETE /devices/:id/caregiver    # Remove caregiver
│
├── /caregiver/         # Caregiver endpoints
│   ├── POST /claim-device               # Assign caregiver
│   ├── GET /devices                     # Caregiver's devices
│   ├── GET /devices/:id/summary         # Device summary
│   ├── GET /search/device               # Search by ID
│   └── GET /events/filter/date          # Filter by date
│
└── /ingest/            # Device ingestion
    ├── POST /telemetry                  # Battery, firmware
    └── POST /event                      # Interaction events
```




## Database Architecture

### Collections

**devices** (Device Registry)
- Purpose: Track all smart bottle caps
- Key fields: device_id, user_id, caregiver_id, battery_percent
- Indexes: device_id (unique), user_id, isActive

**events** (Event Store)
- Purpose: Append-only log of all interactions
- Key fields: device_id, event_type, timestamps, idempotency_key
- Indexes: device_id, server_timestamp, idempotency_key (unique, sparse)

**users** (local mirror of better-auth identity, in MongoDB)
- Purpose: role and device-claim lookups; `user_id` is the better-auth user id
  (the authoritative identity/session record lives in PostgreSQL, not here)
- Key fields: user_id, user_roles, claim_device_ids, caregiving_device_ids
- Indexes: user_id (unique), user_roles

### Data Relationships

```
User (1) ──owns──► (N) Device
User (1) ──cares for──► (N) Device
Device (1) ──generates──► (N) Event
```

**Note**: Relationships maintained via string IDs, not MongoDB ObjectIds

---

## Security Architecture

### Authentication Layers

**Layer 1: Device Authentication**
- Method: **Per-device HMAC-SHA256** signing with replay protection
- Headers: `x-device-id`, `x-nonce`, `x-timestamp`, `x-signature`
- Scope: `/api/ingest/*` endpoints
- Validation: device-specific secret (encrypted at rest, AES-256-GCM), monotonic
  nonce, timestamp freshness window, constant-time HMAC compare
  (`middleware/authDevice.js`, `utils/deviceAuth.js`; see [DEVICE_AUTH.md](DEVICE_AUTH.md))

**Layer 2: User/Caregiver Authentication**
- Method: **better-auth** session validation
- Credential: session cookie or `Authorization: Bearer <session_token>`
- Scope: `/api/user/*` and `/api/caregiver/*` endpoints
- Validation: `auth.api.getSession()` against the shared **PostgreSQL** store
  (`middleware/verifyUserToken.js`) — not a locally-decoded JWT

**Cross-cutting hardening**
- helmet security headers
- CORS allowlist (`CORS_ORIGINS`)
- Active rate limiting (express-rate-limit, 429, `RateLimit-*` headers)
- NoSQL operator-injection sanitization (`middleware/sanitize.js`)
- JSON body size limit + clean JSON error handling

### Authorization Model

**Ownership-based**:
- Users can only access their own devices
- Check: `device.user_id === req.user_id`

**Role-based**:
- Caregivers can only access assigned devices
- Check: `device.caregiver_id === req.user_id`
- Check: `user.hasRole('caregiver')`

**Dual roles**:
- Users can be both patients and caregivers
- `user.user_roles: ["user", "caregiver"]`

---

## Scalability Considerations

### Current Limitations

1. **No caching**: All requests hit the database
2. **Single server**: No horizontal scaling by default

### Future Improvements

**Horizontal Scaling**:
```
Load Balancer
   ├── Server Instance 1
   ├── Server Instance 2
   └── Server Instance 3
        └── MongoDB (shared)
```

**Caching Layer**:
```
Request → Redis Cache → MongoDB
          (if miss)
```

**Database Scaling**:
- Read replicas for query distribution
- Sharding for large datasets
- Time-series collections for events



---

## Technology Stack

### Runtime
- **Node.js** - JavaScript runtime
- **Express.js** (Express 5) - Web framework

### Databases
- **MongoDB** + **Mongoose** - device/event/telemetry store
- **PostgreSQL** (via **pg**) - shared **better-auth** identity/session store

### Authentication
- **better-auth** - user/caregiver session validation against PostgreSQL
- **crypto** (Node.js built-in) - per-device HMAC-SHA256 + AES-256-GCM secret encryption

### Validation & Hardening
- **zod** - event payload validation
- **helmet** - security headers
- **cors** - origin allowlist
- **express-rate-limit** - rate limiting (429)
- request sanitization middleware (NoSQL injection protection)

### Utilities
- **dotenv** - Environment variable management

### Development
- **nodemon** - Auto-restart during development

---

## Design Patterns

### MVC Pattern (Modified)

```
Model       → Mongoose schemas (models/)
View        → JSON responses (no templating)
Controller  → Business logic (controllers/)
Routes      → URL mapping (routes/)
```

### Middleware Pattern

All requests pass through middleware chain before reaching controllers.



## Monitoring & Observability

### Current Implementation

- Console logging
- PM2 process monitoring (production)
- MongoDB connection status



**Last Updated**: June 27, 2026
