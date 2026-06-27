# Development Setup

Guide for setting up local development environment.

---

## Prerequisites

### Required Software

- **Node.js**: LTS recommended
  - Download: https://nodejs.org/
  - Verify: `node --version`

- **npm** (or pnpm): comes with Node.js
  - Verify: `npm --version`

- **MongoDB**: device/event/telemetry store
  - Option A: MongoDB Atlas (cloud, free tier)
  - Option B: Local installation
  - Verify: `mongosh --version` or `mongod --version`

- **PostgreSQL / better-auth**: shared identity store
  - Use the same database the main app uses for better-auth (`DATABASE_URL`).
  - Without it, authenticated user/caregiver endpoints cannot validate sessions.

- **Git**: Latest version
  - Download: https://git-scm.com/
  - Verify: `git --version`

### Optional Tools

- **Postman**: For API testing
- **MongoDB Compass**: GUI for database
- **VS Code**: Recommended IDE

---



## Running the Server

### Development Mode

```bash
npm run dev
```

Features:
- Auto-restart on file changes (nodemon)
- Detailed error logging
- Source maps enabled

Expected output:
```
MongoDB connected
server running on port 5000
```

### Production Mode

```bash
npm start
```

Features:
- Optimized for performance
- Minimal logging
- No auto-restart

---

## Project Structure

```
smart-vial-backend/
├── config/               # Configuration files
│   └── config.js        # Main config loader
├── controllers/          # Business logic
│   ├── app.api.controller.js       # User endpoints
│   ├── caregiver.controller.js     # Caregiver endpoints
│   ├── ingestion.controller.js     # Device ingestion
│   └── saveUserController.js        # User save/provisioning
├── middleware/          # Express middleware
│   ├── authDevice.js    # Per-device HMAC auth + replay protection
│   ├── verifyUserToken.js # better-auth session validation (PostgreSQL)
│   └── sanitize.js      # NoSQL operator-injection sanitization
├── models/              # MongoDB schemas
│   ├── Device.js        # Device model (+ encrypted credential)
│   ├── Event.js         # Typed event model
│   └── User.js          # Local role/claim mirror (better-auth user id)
├── routes/              # API route definitions
│   ├── caregiverAPI.js  # /api/caregiver/*
│   ├── ingestionAPI.js  # /api/ingest/*
│   └── userAPI.js       # /api/user/*
├── utils/               # Helper utilities
│   ├── deviceAuth.js    # Pure HMAC verification (wire contract)
│   ├── deviceCredentials.js # AES-256-GCM device-secret encryption
│   ├── deviceClaim.js   # Device claim helpers
│   ├── eventValidation.js # zod event validation
│   └── userProvisioning.js
├── docs/                # Documentation
├── .env                 # Environment variables (gitignored)
├── package.json        # Dependencies
├── Server.js           # Entry point
└── README.md           # Project overview
```

---

## Development Workflow

### 1. Start Development Server

```bash
npm run dev
```

Server runs on `http://localhost:5000`

### 2. Obtain a User Session

There is no local test-token generator anymore (the old `generateTestToken.js` /
`testJWT.js` were removed with raw-JWT auth). To call authenticated user/caregiver
endpoints, obtain a real **better-auth** session from the main app and send it as a
session cookie or `Authorization: Bearer <session_token>`.

### 3. Test APIs

Use Postman or curl:

```bash
# Test user API (better-auth session)
curl -H "Authorization: Bearer <better_auth_session_token>" \
  http://localhost:5000/api/user/devices

# Test device ingestion (per-device HMAC headers — see docs/DEVICE_AUTH.md
# for how to compute x-signature)
curl -X POST http://localhost:5000/api/ingest/telemetry \
  -H "x-device-id: DEVICE001" \
  -H "x-nonce: 1" \
  -H "x-timestamp: $(date +%s)" \
  -H "x-signature: <lowercase hex HMAC-SHA256>" \
  -H "Content-Type: application/json" \
  -d '{"device_id":"DEVICE001","battery_percent":85}'
```

> Note: there is no `GET /` health-check route; requesting `/` returns the default
> 404 handler.

### 4. View Logs

Server logs appear in terminal:
- Request logs
- Database queries
- Error stack traces

### 5. Database Inspection

Use MongoDB Compass:
1. Connect to `mongodb://localhost:27017`
2. Select `smartvial` database
3. Browse collections: `devices`, `events`, `users`

---

## Common Tasks

### Create New API Endpoint

1. **Define route** in `routes/`:
```javascript
// routes/userAPI.js
router.get('/new-endpoint', verifyToken, newController);
```

2. **Create controller** in `controllers/`:
```javascript
// controllers/app.api.controller.js
const newController = async (req, res) => {
  try {
    // Your logic here
    res.json({ message: 'Success' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};
```

3. **Export controller**:
```javascript
module.exports = {
  // ... existing
  newController
};
```

### Add New Database Model

1. Create file in `models/`:
```javascript
// models/NewModel.js
const mongoose = require('mongoose');

const NewSchema = new mongoose.Schema({
  field1: String,
  field2: Number
});

module.exports = mongoose.model('NewModel', NewSchema);
```

2. Import in controller:
```javascript
const NewModel = require('../models/NewModel');
```

### Add Middleware

1. Create file in `middleware/`:
```javascript
// middleware/newMiddleware.js
module.exports = (req, res, next) => {
  // Your logic
  next();
};
```

2. Apply to routes:
```javascript
const newMiddleware = require('../middleware/newMiddleware');
router.get('/endpoint', newMiddleware, controller);
```

---

## Testing

### Manual Testing

Use Postman or curl (see the Postman material under `utils/postman-test/`). Set up a
better-auth session for user endpoints and compute HMAC headers for device endpoints.

### Unit Testing

```bash
npm test   # runs the node:test suite (node --test)
```

Pure modules like `utils/deviceAuth.js` and `utils/eventValidation.js` are designed to
be unit-testable without a live database.


## Next Steps

1. ✅ Set up development environment
2. ✅ Run server locally
3. ✅ Test APIs with Postman
4. 📖 [API Reference](API_REFERENCE.md)
5. 📖 [Database Schema](DATABASE_SCHEMA.md)



**Last Updated**: June 27, 2026
