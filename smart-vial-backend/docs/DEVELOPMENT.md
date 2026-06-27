# Development Setup

Guide for setting up local development environment.

---

## Prerequisites

### Required Software

- **Node.js**: >= 16.x (LTS recommended)
  - Download: https://nodejs.org/
  - Verify: `node --version`

- **npm**: >= 8.x (comes with Node.js)
  - Verify: `npm --version`

- **MongoDB**: >= 5.x
  - Option A: MongoDB Atlas (cloud, free tier)
  - Option B: Local installation
  - Verify: `mongo --version` or `mongod --version`

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
server running on port 5000
MongoDB connected
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
│   ├── config.js        # Main config loader
│   └── databaseConfig.js # MongoDB setup
├── controllers/          # Business logic
│   ├── app.api.controller.js       # User endpoints
│   ├── caregiver.controller.js     # Caregiver endpoints
│   └── ingestion.controller.js     # Device ingestion
├── middleware/          # Express middleware
│   ├── authDevice.js    # Device API key auth
│   └── verifyUserToken.js # JWT verification
├── models/              # MongoDB schemas
│   ├── Device.js        # Device model
│   ├── Event.js         # Event model
│   └── User.js          # User model
├── routes/              # API route definitions
│   ├── caregiverAPI.js  # /api/caregiver/*
│   ├── ingestionAPI.js  # /api/ingest/*
│   └── userAPI.js       # /api/user/*
├── utils/               # Helper utilities
│   ├── generateTestToken.js # JWT token generator
│   └── testJWT.js      # Token tester
├── docs/                # Documentation
├── .env                 # Environment variables (gitignored)
├── .env.example         # Example environment file
├── .gitignore          # Git ignore rules
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

### 2. Generate Test Tokens

```bash
cd utils
node generateTestToken.js
```

Copy the tokens for API testing.

### 3. Test APIs

Use Postman or curl:

```bash
# Health check
curl http://localhost:5000/

# Test device ingestion
curl -X POST http://localhost:5000/api/ingest/telemetry \
  -H "X-API-Key: your-strong-device-api-key" \
  -H "Content-Type: application/json" \
  -d '{"device_id":"DEVICE001","battery":85}'

# Test user API
curl -H "Authorization: Bearer YOUR_TOKEN" \
  http://localhost:5000/api/user/devices
```

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

Use Postman collection:
1. Import `POSTMAN_TESTS.md`
2. Set up environment variables
3. Run requests

### Unit Testing (Future)

```bash
npm test
```


## Next Steps

1. ✅ Set up development environment
2. ✅ Run server locally
3. ✅ Test APIs with Postman
4. 📖 [API Reference](API_REFERENCE.md)
5. 📖 [Database Schema](DATABASE_SCHEMA.md)



**Last Updated**: February 3, 2026
