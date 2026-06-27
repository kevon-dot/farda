# Smart Vial Backend Documentation

Complete documentation for the Smart Vial IoT backend system.

## 📚 Documentation Index

### Getting Started
- [Development Setup](DEVELOPMENT.md) - Local environment setup
- [Architecture Overview](ARCHITECTURE.md) - System design and components

### API Documentation
- [API Reference](API_REFERENCE.md) - Complete API endpoint documentation
- [Authentication Guide](AUTHENTICATION.md) - JWT tokens and API keys

### Technical Details
- [Database Schema](DATABASE_SCHEMA.md) - MongoDB models and relationships

### Deployment & Operations
- [Deployment Guide](DEPLOYMENT.md) - Production deployment steps
- [Troubleshooting](TROUBLESHOOTING.md) - Common issues and solutions


---

## 🚀 Quick Start

### Prerequisites
```bash
- Node.js >= 16.x
- MongoDB >= 5.x
- npm or yarn
```

2. **Configure environment**
```bash
cp .env.example .env
# Edit .env with your settings
```

3. **Start the server**
```bash
npm start
# or for development
npm run dev
```

4. **Generate test tokens**
```bash
node utils/generateTestToken.js
```

Server runs on `http://localhost:5000`

---

## 📖 Project Overview

### What is Smart Vial?

Smart Vial is an IoT-enabled medication adherence tracking system consisting of:

- **ESP32-based smart caps** that detect bottle openings/closings
- **Cloud backend** (this project) that stores events and telemetry
- **Mobile app** for patients and caregivers to view adherence data

### System Components

```
┌─────────────┐         ┌──────────────┐         ┌──────────────┐
│   ESP32     │ HTTPS   │   Backend    │  APIs   │  Mobile App  │
│  Devices    ├────────►│   Server     ├────────►│   (User/CG)  │
└─────────────┘         └──────────────┘         └──────────────┘
      │                        │
      │                        │
      └────────────────────────┘
              MongoDB
```

### Key Features

✅ **Multi-device support** - Users can claim multiple smart bottles
✅ **Dual role system** - Users can be both patients and caregivers
✅ **Real-time telemetry** - Battery levels, connection status
✅ **Event tracking** - Open/close events with timestamps
✅ **Caregiver dashboards** - Read-only views for caregivers
✅ **Idempotent ingestion** - Prevents duplicate events
✅ **Secure authentication** - JWT for users, API keys for devices

---

## 🏗️ Architecture

### Technology Stack

**Backend**
- Runtime: Node.js with Express.js
- Database: MongoDB with Mongoose ODM
- Authentication: JSON Web Tokens (JWT)
- Device Auth: API Key headers

**Cloud Agnostic**
- Can deploy on AWS, GCP, Azure, or any VPS
- Currently configured for MongoDB Atlas

### Directory Structure

```
smart-vial-backend/
├── config/                 # Configuration files
│   ├── config.js          # Main config loader
│   └── databaseConfig.js  # MongoDB connection
├── controllers/            # Business logic
│   ├── app.api.controller.js       # User endpoints
│   ├── caregiver.controller.js     # Caregiver endpoints
│   └── ingestion.controller.js     # Device ingestion
├── middleware/            # Express middleware
│   ├── authDevice.js      # Device API key auth
│   └── verifyUserToken.js # JWT verification
├── models/                # MongoDB schemas
│   ├── Device.js          # Device registry
│   ├── Event.js           # Event store
│   └── User.js            # User accounts
├── routes/                # API routes
│   ├── userAPI.js         # /api/user/*
│   ├── caregiverAPI.js    # /api/caregiver/*
│   └── ingestionAPI.js    # /api/ingest/*
├── utils/                 # Helper utilities
│   └── generateTestToken.js
├── docs/                  # Documentation (you are here)
├── .env                   # Environment variables
├── Server.js              # Application entry point
└── package.json           # Dependencies
```

---

## 🔐 Authentication Overview

### For Users & Caregivers (JWT)

```http
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

Generate tokens:
```bash
node utils/generateTestToken.js
```

### For Devices (API Key)

```http
X-API-Key: your-strong-device-api-key
```

Configure in `.env`:
```env
DEVICE_API_KEY=your-strong-device-api-key
```

See [Authentication Guide](AUTHENTICATION.md) for details.

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

### Device
```javascript
{
  device_id: "DEVICE001",
  user_id: "65abc123...",
  caregiver_id: "65def456...",
  battery_percent: 85,
  firmware_version: "1.0.2",
  last_seen: Date,
  claimed: true
}
```

### Event
```javascript
{
  device_id: "DEVICE001",
  event_type: "OPEN",
  device_timestamp: Date,
  server_timestamp: Date,
  idempotency_key: "unique-id",
  payload: {}
}
```

### User
```javascript
{
  user_id: "65abc123...",
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

4. Third-Party Libraries: This software utilizes [e.g., Node.js, Express, MongoDB]. These components remain subject to their respective open-source licenses (MIT, Apache, etc.).




**Last Updated**: February 3, 2026
