# Architecture Overview

System architecture and design documentation.

---

## System Overview

Smart Vial is an IoT medication adherence tracking system consisting of three main components:

```
┌─────────────────┐         ┌──────────────────┐         ┌──────────────────┐
│   ESP32 Smart   │         │   Cloud Backend  │         │   Mobile Apps    │
│   Bottle Caps   │ HTTPS   │   (This System)  │  APIs   │  (User/Caregiver)│
│                 ├────────►│                  ├────────►│                  │
│  - Sensors      │         │  - REST APIs     │         │  - Patient View  │
│  - WiFi         │         │  - Auth          │         │  - Caregiver View│
│  - Battery      │         │  - Data Storage  │         │  - Dashboards    │
└─────────────────┘         └──────────────────┘         └──────────────────┘
                                     │
                                     ▼
                            ┌──────────────────┐
                            │   MongoDB Atlas  │
                            │   - Devices      │
                            │   - Events       │
                            │   - Users        │
                            └──────────────────┘
```

---

## Component Architecture

### Backend Server (Node.js + Express)

```
┌─────────────────────────────────────────────┐
│              Express Server                  │
├─────────────────────────────────────────────┤
│                                             │
│  ┌───────────┐  ┌───────────┐  ┌──────────┐│
│  │  Routes   │  │Middleware │  │Controllers││
│  │           │  │           │  │           ││
│  │ userAPI   │  │ verifyJWT │  │ User APIs ││
│  │caregiverAPI│─►│authDevice│─►│Caregiver  ││
│  │ingestionAPI│  │CORS/etc  │  │Ingestion  ││
│  └───────────┘  └───────────┘  └──────────┘│
│                                             │
│  ┌─────────────────────────────────────────┐│
│  │         Models (Mongoose ODM)           ││
│  │                                         ││
│  │  Device  │  Event  │  User              ││
│  └─────────────────────────────────────────┘│
│                     │                       │
└─────────────────────┼───────────────────────┘
                      │
                      ▼
              ┌──────────────┐
              │   MongoDB    │
              └──────────────┘
```



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

**users** (User Accounts) for faster search of devices 
- Purpose: User profiles and role management
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
- Method: Shared API Key
- Header: X-API-Key
- Scope: /api/ingest/* endpoints
- Validation: Simple string comparison

**Layer 2: User/Caregiver Authentication**
- Method: JWT (JSON Web Tokens)
- Header: Authorization: Bearer <token>
- Scope: /api/user/* and /api/caregiver/* endpoints
- Validation: Signature verification, expiration check

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

1. **Single API Key**: All devices share same key
2. **No caching**: All requests hit database
3. **Single server**: No horizontal scaling

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
- **Node.js** v16+ - JavaScript runtime
- **Express.js** - Web framework

### Database
- **MongoDB** - NoSQL database
- **Mongoose** - ODM (Object Data Modeling)

### Authentication
- **jsonwebtoken** - JWT creation/validation
- Custom API key middleware

### Utilities
- **dotenv** - Environment variable management
- **crypto** (Node.js built-in) - For generating secrets

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



**Last Updated**: February 3, 2026
