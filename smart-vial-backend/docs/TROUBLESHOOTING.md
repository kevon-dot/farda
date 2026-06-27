
# Troubleshooting Guide: Smart Vial Backend

## Database Connection

This service connects to **two** databases: MongoDB (`MONGO_URI`) for device/event
data, and PostgreSQL (`DATABASE_URL`) for better-auth identity/sessions.

**Error:** `MongoNetworkError: failed to connect to server`

* **Check URI:** Verify `MONGO_URI` in `.env`. Ensure format is `mongodb+srv://user:pass@cluster...`
* **Whitelist IP:** Add current IP or `0.0.0.0/0` in MongoDB Atlas > Network Access.
* **Credentials:** Confirm database username/password in Atlas > Database Access.

**PostgreSQL / better-auth connection issues** (user endpoints fail to authenticate)

* **Check URL:** Verify `DATABASE_URL` is set and points at the **same** PostgreSQL
  database the main app uses for better-auth.
* **Reachability:** Ensure the host/port are reachable and credentials are valid.

## Authentication

### User / Caregiver (better-auth session)

**Error:** `Access Denied: Invalid or missing authentication`

* **Session present?** Send a better-auth session as a cookie or
  `Authorization: Bearer <session_token>` (obtained from the main app). There is no
  local JWT/`JWT_SECRET` anymore.
* **Same database?** Verify `DATABASE_URL` points at the **same** PostgreSQL store the
  main app uses for better-auth; otherwise the session won't be found.
* **Base URL?** Verify `BETTER_AUTH_URL` matches the deployment URL (origin checks).
* **Expiration:** The session may be expired/revoked — re-authenticate in the main app.

### Device Ingestion (per-device HMAC)

**Error:** `Authentication required ...` / `Authentication failed.` / `Request timestamp
outside the allowed window` / `Replayed or out-of-order request rejected.`

* **Headers:** All four are required: `x-device-id`, `x-nonce`, `x-timestamp`,
  `x-signature`. `x-device-id` must equal the body `device_id`.
* **Signature:** Must be `HMAC_SHA256(device_secret, "deviceId\nnonce\ntimestamp\nrawBody")`
  as lowercase hex, signed over the **exact** bytes sent (not a re-serialized body).
* **Nonce:** Must be strictly greater than the device's last accepted nonce (replays
  and out-of-order requests are rejected).
* **Clock skew:** `|now - x-timestamp|` must be within `TYME_SYNC_TOLERANCE_SECONDS`
  (default 300). Sync the device clock.
* **Credential:** The device must have an active (non-revoked) credential; the server
  must have `DEVICE_SECRET_ENC_KEY` set to decrypt it.

See [DEVICE_AUTH.md](DEVICE_AUTH.md) for the full rejection table.

## Event Ingestion

**Issue:** Events return 200 OK but don't show in DB.

* **Idempotency:** If the response is `Duplicate event ignored`, the `event_id` is a duplicate.
* **Claimed?** Events are rejected (`400 device not claimed by any user`) unless the
  device has been claimed by a user. Telemetry auto-creates the device; events do not.
* **Event type:** Unknown `event` values are rejected with `400`. Allowed:
  `OPEN, CLOSE, BATTERY, LOW_BATTERY, HEARTBEAT, BOOT, TILT, TAMPER`.
* **DB Check:** Query `db.events` directly to rule out API caching issues.
* **Device ID:** Ensure the `device_id` in the payload matches an existing device.

**Issue:** Duplicate events.

* **Fix:** Send a unique `event_id` with every payload.
* **Index:** Ensure MongoDB has a unique index on `event_id` or your idempotency key.

## Device Claiming

**Error:** `Device already claimed by another user`

* **Check Owner:** Query `db.devices` to see current `user_id`.
* **Unclaim:** Previous owner must DELETE via `/api/user/devices/:id/unclaim` first.
* **Admin Override:** Manually clear `user_id` in DB if needed.

**Issue:** Claim success, but device list empty.

* **User Match:** Ensure the better-auth session's user id (`req.user_id`) matches the
  `user_id` on the device record.
* **Active Flag:** Ensure `isActive: true` on the device document.

## Caregiver Access

**Issue:** Caregiver cannot see assigned device.

* **Role:** Check `db.users` for the `caregiver` role on the mirror record.
* **Assignment:** Verify device `caregiver_id` matches the user's id.
* **Session:** Ensure you are using the *caregiver's* better-auth session, not the patient's.

## Server & Deployment

**Error:** `EADDRINUSE :::5000`

* **Kill Process:** Find PID using port 5000 and kill it (`Stop-Process` or `kill -9`).
* **Change Port:** Update `PORT` in `.env`.

**Error:** `MODULE_NOT_FOUND`

* **Reinstall:** Delete `node_modules` and `package-lock.json`, then run `npm install`.

**Issue:** Crashes on Heroku.

* **Logs:** Run `heroku logs --tail` immediately.
* **Config:** Run `heroku config` to ensure `MONGODB_URI` and keys are set in production.
* **IP Whitelist:** Ensure Atlas allows access from anywhere (`0.0.0.0/0`).

## Common API Errors

| Error | Cause | Fix |
| --- | --- | --- |
| `device_id is required` | Missing payload field | Add `device_id` to body/params. |
| `User not authorized` | ID mismatch | Check device ownership or caregiver assignment. |
| `Invalid device_id` | Device not in DB | Run ingestion endpoint to create device first. |
| `No events found` | Time range/ID | Check ISO date format (`YYYY-MM-DDTHH:mm:ssZ`). |

## Debugging Quick Tips

1. **Mongoose Debug:** Set `mongoose.set('debug', true)` in dev to see raw queries.
2. **Date Format:** Always use ISO 8601 strings for API queries.
3. **Indexes:** If queries are slow, check `db.collection.getIndexes()`.
4. **CORS:** CORS uses an **allowlist** (`CORS_ORIGINS`, comma-separated). If a browser
   request is blocked with `403 Origin not allowed by CORS`, add the frontend origin to
   `CORS_ORIGINS` and restart. Requests with no `Origin` header (devices, curl) are allowed.
5. **Rate limits:** A `429` response means a rate limiter was hit. Inspect the
   `RateLimit-*` response headers and tune `RATE_LIMIT_*` / `INGEST_RATE_LIMIT_*` /
   `AUTH_RATE_LIMIT_*` if needed.

*Last Updated: June 27, 2026*