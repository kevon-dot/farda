# Authentication Guide


## Table of Contents

1. [Overview](#overview)
2. [User & Caregiver Authentication (JWT)](#user--caregiver-authentication-jwt)
3. [Device Authentication (API Key)](#device-authentication-api-key)
4. [Token Management](#token-management)
5. [Security Best Practices](#security-best-practices)

---

## Overview

Smart Vial uses two authentication methods:

| Who | Method | Use Case |
|-----|--------|----------|
| **Users & Caregivers** | JWT (JSON Web Tokens) | Mobile app, web dashboard access |
| **ESP32 Devices** | API Key | Device telemetry and event ingestion |

---

## User & Caregiver Authentication (JWT)

### Token Structure

JWT tokens contain:

```json
{
  "sub": "65abc123def456789",    // user_id (subject)
  "role": "user",                 // or "caregiver"
  "email": "user@example.com",    // optional metadata
  "iat": 1738483200,              // issued at (Unix timestamp)
  "exp": 1741075200               // expires at (Unix timestamp)
}
```

### Configuration

Configured in `.env`:

```env
JWT_SECRET=your-super-secret-jwt-key-change-this-in-production
JWT_EXPIRES_IN=30d
```

### Generating Tokens

#### For Testing (Development)

Use the provided utility:

```bash
cd utils
node generateTestToken.js
```

Output:
```
=== TEST JWT TOKENS ===

USER TOKEN (role: user):
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...

CAREGIVER TOKEN (role: caregiver):
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

### Using Tokens in Requests

Include token in `Authorization` header:

```http
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```


### Token Verification Flow

```
1. Client sends request with token
   ↓
2. verifyUserToken middleware extracts token
   ↓
3. JWT.verify() validates signature & expiration
   ↓
4. Decoded payload attached to req object:
   - req.user_id
   - req.user_role
   ↓
5. Controller processes request
```

**Middleware code**: `middleware/verifyUserToken.js`

### Token Expiration

- Default: 30 days
- Configurable via `JWT_EXPIRES_IN` in `.env`
- Format: `7d`, `24h`, `60m`, or seconds

**Handling expired tokens**:
```json
{
  "error": "Invalid or expired token"
}
```

Client should:
1. Detect 401/403 response
2. Prompt user to re-authenticate
3. Obtain new token

### Role-Based Access Control

Users can have multiple roles:

```javascript
user_roles: ["user", "caregiver"]
```

**Example**: User owns devices AND cares for others' devices.

---

## Device Authentication (API Key)

### Configuration

Set in `.env`:

```env
DEVICE_API_KEY=your-strong-device-api-key
```
### Using API Key in Requests

Include key in `X-API-Key` header:

```http
X-API-Key: your-strong-device-api-key
Content-Type: application/json
```

**ESP32 Example** (Arduino/C++):
```cpp
HTTPClient http;
http.begin("https://your-server.com/api/ingest/telemetry");
http.addHeader("Content-Type", "application/json");
http.addHeader("X-API-Key", "your-strong-device-api-key");

String payload = "{\"device_id\":\"DEVICE001\",\"battery\":85}";
int httpCode = http.POST(payload);
```

### API Key Verification Flow

```
1. Device sends request with X-API-Key header
   ↓
2. authDevice middleware extracts key
   ↓
3. Compares with config.device.apiKey
   ↓
4. If valid, proceeds to controller
   ↓
5. If invalid, returns 401
```

**Middleware code**: `middleware/authDevice.js`

### Security Considerations

**Current Limitation**: Single shared API key for all devices

**Risks**:
- Key compromise affects all devices
- Cannot revoke access per-device

**Recommendations for Production**:

1. **Per-Device Keys**:
   - Generate unique key during device provisioning
   - Store in Device model: `device.api_key`
   - Verify against device-specific key

2. **Certificate-Based Auth**:
   - Use client certificates (mTLS)
   - More secure, harder to compromise
---



### Logout

No server-side logout needed (stateless JWT).

Client should:
1. Delete stored token
2. Clear user session
3. Redirect to login

## Troubleshooting

### "Invalid or expired token"

**Causes**:
1. Token actually expired
2. Wrong JWT_SECRET (server vs token generation)
3. Malformed token
4. Token modified/corrupted

**Solutions**:
1. Generate fresh token
2. Verify JWT_SECRET matches
3. Check token format (3 parts separated by dots)
4. Ensure no extra spaces/newlines

### "API key required"

**Causes**:
1. Missing `X-API-Key` header
2. Header name typo (case-sensitive)

**Solutions**:
1. Add header: `X-API-Key: your-key`
2. Check spelling: `X-API-Key` not `x-api-key`


**Last Updated**: February 3, 2026
