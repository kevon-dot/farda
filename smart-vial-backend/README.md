# Smart Vial IoT Backend

REST API backend for Smart Vial 
---

## Quick Links

📖 **[Complete Documentation →](docs/README.md)**

Essential guides:
- **[API Reference](docs/API_REFERENCE.md)** - All endpoints with examples
- **[Quick Start](docs/DEVELOPMENT.md#quick-start)** - Get running in 5 minutes
- **[Authentication](docs/AUTHENTICATION.md)** - JWT and API key setup
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
- Log OPEN/CLOSE events from devices
- Timestamp-based adherence tracking
- Idempotent event ingestion (prevents duplicates)

✅ **Dual Role System**
- Users can be patients (own devices)
- Users can be caregivers (monitor others' devices)
- Same user can have both roles simultaneously

✅ **RESTful APIs**
- User/Patient APIs for device ownership
- Caregiver APIs for monitoring
- Device ingestion APIs for telemetry

---

## Tech Stack

- **Runtime**: Node.js 16+
- **Framework**: Express.js
- **Database**: MongoDB (Mongoose ODM)
- **Authentication**: JWT (users/caregivers), API Keys (devices)

---

## Quick Start

### Prerequisites

- Node.js 16 or higher
- MongoDB database (MongoDB Atlas recommended)
- npm or yarn

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

3. **Configure environment**:
   ```bash
   cp .env.example .env
   ```
   
   Edit `.env` and set:
   ```env
   MONGODB_URI=your_mongodb_connection_string
   JWT_SECRET=your_secret_key_min_32_chars
   DEVICE_API_KEY=your_device_api_key
   ```

4. **Start server**:
   ```bash
   # Development (auto-restart)
   npm run dev
   
   # Production
   npm start
   ```

5. **Test connection**:
   ```bash
   curl http://localhost:5000/
   # Should return: "Welcome to Vial Server!"
   ```

---

## API Overview

### User/Patient APIs (`/api/user`)

- `POST /save` - Create/update user account
- `POST /claim` - Claim ownership of a device
- `GET /devices` - List your devices
- `GET /devices/:id/events` - Get device events
- `DELETE /devices/:id/unclaim` - Release device ownership

### Caregiver APIs (`/api/caregiver`)

- `POST /claim-device` - Assign caregiver to device
- `GET /devices` - List devices you're monitoring
- `GET /devices/:id/summary` - Device summary with latest events
- `GET /events/filter/date` - Filter events by date range

### Device Ingestion APIs (`/api/ingest`)

- `POST /telemetry` - Update battery, firmware version
- `POST /event` - Log OPEN/CLOSE interaction events

**Authentication**:
- User/Caregiver APIs: `Authorization: Bearer <JWT_TOKEN>`
- Device APIs: `X-API-Key: <API_KEY>`

📘 **[Full API Documentation →](docs/API_REFERENCE.md)**

---

## Project Structure

```
smart-vial-backend/
├── Server.js                 # Application entry point
├── config/
│   ├── config.js             # Environment configuration
│   └── databaseConfig.js     # MongoDB connection
├── models/
│   ├── User.js               # User accounts (dual roles)
│   ├── Device.js             # Smart bottle cap registry
│   └── Event.js              # Interaction event log
├── controllers/
│   ├── app.api.controller.js         # User API logic
│   ├── caregiver.controller.js       # Caregiver API logic
│   └── ingestion.controller.js       # Device ingestion logic
├── routes/
│   ├── userAPI.js            # User endpoint routes
│   ├── caregiverAPI.js       # Caregiver endpoint routes
│   └── ingestionAPI.js       # Device ingestion routes
├── middleware/
│   ├── verifyUserToken.js    # JWT authentication
│   └── authDevice.js         # API key validation
├── utils/
│   ├── generateTestToken.js  # Create test JWT tokens
│   └── testJWT.js            # Validate JWT tokens
└── docs/                     # Complete documentation
    ├── README.md             # Documentation index
    ├── API_REFERENCE.md      # API endpoints
    ├── AUTHENTICATION.md     # Auth guide
    ├── DEVELOPMENT.md        # Local development
    ├── DEPLOYMENT.md         # Production deployment
    ├── DATABASE_SCHEMA.md    # MongoDB schema
    ├── ARCHITECTURE.md       # System architecture
    └── TROUBLESHOOTING.md    # Common issues
```

---

## Development

### Available Scripts

```bash
# Start development server (auto-restart on changes)
npm run dev

# Start production server
npm start

# Generate test JWT token
node utils/generateTestToken.js

# Validate JWT token
node utils/testJWT.js <token>
```

### Testing APIs

Generate a test token:
```bash
node utils/generateTestToken.js
```

Test user endpoint:
```bash
curl -H "Authorization: Bearer <token>" \
  http://localhost:5000/api/user/devices
```

📘 **[Development Guide →](docs/DEVELOPMENT.md)**

---

## Deployment

### Heroku Deployment

```bash
# Login to Heroku
heroku login

# Create app
heroku create your-app-name

# Set environment variables
heroku config:set MONGODB_URI="your_mongodb_uri"
heroku config:set JWT_SECRET="your_jwt_secret"
heroku config:set DEVICE_API_KEY="your_api_key"

# Deploy
git push heroku main

# View logs
heroku logs --tail
```

📘 **[Full Deployment Guide →](docs/DEPLOYMENT.md)**

---

## Database Schema

### Models

**User** - User accounts with flexible roles
```javascript
{
  user_id: String,
  user_roles: [String],  // ["user", "caregiver"]
  claim_device_ids: [String],
  caregiving_device_ids: [String]
}
```

**Device** - Smart bottle cap registry
```javascript
{
  device_id: String,
  user_id: String,
  caregiver_id: String,
  battery_percent: Number,
  firmware_version: String,
  isActive: Boolean
}
```

**Event** - Interaction event log
```javascript
{
  device_id: String,
  event_type: String,  // "OPEN" or "CLOSE"
  timestamp: Date,
  server_timestamp: Date,
  idempotency_key: String
}
```

📘 **[Complete Schema Documentation →](docs/DATABASE_SCHEMA.md)**

---

## Security

🔐 **Authentication**:
- JWT tokens for user/caregiver endpoints (30-day expiration)
- API keys for device endpoints
- Ownership validation on all operations

🛡️ **Best Practices**:
- Store JWT_SECRET and API keys in environment variables
- Use HTTPS in production
- Implement rate limiting
- Regular security audits

📘 **[Security Guide →](docs/AUTHENTICATION.md#security-best-practices)**

---

## Environment Variables

Required configuration in `.env`:

```env
# Server
PORT=5000
NODE_ENV=production

# Database
MONGODB_URI=mongodb+srv://user:pass@cluster.mongodb.net/dbname

# Authentication
JWT_SECRET=your-secret-min-32-characters
DEVICE_API_KEY=your-device-api-key
```

📘 **[Environment Configuration →](docs/DEPLOYMENT.md#environment-variables)**

---

## Troubleshooting

Common issues:

- **Database connection fails**: Check MongoDB URI and network access
- **Invalid token**: Regenerate using `generateTestToken.js`
- **Device already claimed**: Unclaim first or use different device
- **Empty response**: Check server logs for errors

📘 **[Full Troubleshooting Guide →](docs/TROUBLESHOOTING.md)**

---

## API Examples

### Claim a Device

```bash
curl -X POST http://localhost:5000/api/user/claim \
  -H "Authorization: Bearer <your_token>" \
  -H "Content-Type: application/json" \
  -d '{"device_id": "DEVICE001"}'
```

### Get Device Events

```bash
curl -H "Authorization: Bearer <your_token>" \
  http://localhost:5000/api/user/devices/DEVICE001/events
```

### Log Device Event (from ESP32)

```bash
curl -X POST http://localhost:5000/api/ingest/event \
  -H "X-API-Key: your_api_key" \
  -H "Content-Type: application/json" \
  -d '{
    "device_id": "DEVICE001",
    "event": "OPEN",
    "event_id": "unique_id_123"
  }'
```

📘 **[More Examples →](docs/API_REFERENCE.md)**

---

## Documentation

Complete documentation is available in the [`docs/`](docs/) folder:

| Document | Description |
|----------|-------------|
| [README](docs/README.md) | Documentation index and overview |
| [API Reference](docs/API_REFERENCE.md) | Complete API endpoint documentation |
| [Authentication](docs/AUTHENTICATION.md) | JWT and API key setup |
| [Database Schema](docs/DATABASE_SCHEMA.md) | MongoDB models and relationships |
| [Development](docs/DEVELOPMENT.md) | Local development guide |
| [Deployment](docs/DEPLOYMENT.md) | Production deployment |
| [Architecture](docs/ARCHITECTURE.md) | System architecture and design |
| [Troubleshooting](docs/TROUBLESHOOTING.md) | Common issues and solutions |

---

## Support

- 📧 Report issues in GitHub Issues
- 📖 Check [Troubleshooting Guide](docs/TROUBLESHOOTING.md)
- 💬 Review [API Documentation](docs/API_REFERENCE.md)

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

4. Third-Party Libraries: This software utilizes [e.g., Node.js, Express, MongoDB]. These components remain subject to their respective open-source licenses (MIT, Apache, etc.).


---

**Last Updated**: February 3, 2026
