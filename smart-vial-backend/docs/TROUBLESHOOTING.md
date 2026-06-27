
# Troubleshooting Guide: Smart Vial Backend

## Database Connection

**Error:** `MongoNetworkError: failed to connect to server`

* **Check URI:** Verify `MONGODB_URI` in `.env`. Ensure format is `mongodb+srv://user:pass@cluster...`
* **Whitelist IP:** Add current IP or `0.0.0.0/0` in MongoDB Atlas > Network Access.
* **Credentials:** Confirm database username/password in Atlas > Database Access.

## Authentication

**Error:** `Invalid token` / `No token provided`

* **Header Format:** Must be `Authorization: Bearer <token>`. Check for typos or missing "Bearer".
* **Secret:** Verify `JWT_SECRET` matches the one used to sign the token.
* **Expiration:** Check if token is expired (decode via `jwt.io` or log expiration).

**Error:** `Invalid API Key` (Device Ingestion)

* **Header Name:** Must be exactly `X-API-Key` (case-sensitive).
* **Env Var:** Verify `DEVICE_API_KEY` exists in `.env`.

## Event Ingestion

**Issue:** Events return 200 OK but don't show in DB.

* **Idempotency:** If response is `Event already logged`, the `event_id` is a duplicate.
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

* **User Match:** Decode JWT to ensure `sub` (user ID) matches the `user_id` on the device record.
* **Active Flag:** Ensure `isActive: true` on the device document.

## Caregiver Access

**Issue:** Caregiver cannot see assigned device.

* **Role:** Check `db.users` for `caregiver` role.
* **Assignment:** Verify device `caregiver_id` matches the user's ID.
* **Token:** Ensure you are using a token generated for the *caregiver*, not the patient.

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
4. **CORS:** If browser blocks request, install `cors` package and use `app.use(cors())`.

*last Updated- 3 feb 2026