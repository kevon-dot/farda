# Vial service contract v1 — consumer foundation

This document supersedes the older API/auth/schema examples. It describes code in this branch, not validated hardware capabilities. No production database, provisioning service or physical device was used to validate it.

## What changed

- Telemetry cannot create devices. Fleet API keys and development JWT/secret fallbacks are removed.
- Mobile APIs accept the main API's opaque Bearer session token. Each request queries the shared PostgreSQL Prisma `"Session"` and `"User"` tables, checks expiration and observes revocation without a cookie cache. JWTs from the removed test-token utility are not valid sessions.
- A claim requires a trusted, expiring, single-use possession grant bound to the session user and current credential version. An identifier or BLE connection does not constitute proof.
- Claim and release change a device atomically. Release clears pending/accepted caregiver access and invalidates the previous credential. Event history remains attributed to its observation-time owner.
- Raw events are append-only observations. No movement, call, device event or caregiver view writes a dose-taking status.
- An observation receipt is returned only after a MongoDB transaction commits. Deduplication requires real compound unique indexes.

## Startup and deployment requirements

`MONGODB_URI` (legacy `MONGO_URI` alias accepted) and `DATABASE_URL` are required. `node Server.js` fails before listening if either configuration, replica-set support, required indexes or exact session-table mapping is unavailable. MongoDB standalone deployments are unsupported because ownership checks and observation commits must serialize with release/revocation.

Startup creates missing declared indexes; it does not drop old indexes, repair ambiguous duplicates or infer legacy owners. Review index creation on a staging copy first. Existing globally sparse `idempotency_key` indexes may remain because new writes omit that field entirely. Existing events without a proven `owner_id` and epoch are quarantined from consumer queries. Do not backfill their owner from a device's current owner.

All request bodies are capped at 16 KiB; observation payloads at 4 KiB. The process-local limiter bounds bursts and memory; a multi-instance deployment needs a shared gateway limit, trusted proxy configuration, TLS, operational monitoring and a least-privilege MongoDB role. The append-only Mongoose guards do not protect against administrators or direct database clients. A reviewed retention/account-deletion process remains a separate launch requirement.

## Authentication

Mobile requests use `Authorization: Bearer <opaque-session-token>` from the existing main API. Caller-supplied owner IDs and roles are never accepted. Expired/revoked/missing sessions return 401; an unavailable session database returns 503. The shared database connection must use the same schema mapping as the main API.

Provisioned direct-device requests require all three headers:

| Header | Meaning |
| --- | --- |
| `X-Device-Id` | Canonical provisioned device identity; must equal body `device_id` |
| `X-Credential-Id` | Nonsecret identifier of this device's current credential |
| `X-API-Key` | High-entropy per-device credential, never a fleet key |

Only SHA-256 credential digests are stored and comparisons are constant-time. These must be randomly generated secrets of at least 32 bytes, not passwords. Device record credentials are hidden from normal selection and all responses. Credential version/revocation is rechecked in the committing write. The server contract does not prove encrypted firmware transport, secure key storage or replay-resistant vendor possession. Direct ingestion must remain unavailable to existing devices until that contract is implemented and verified.

## Enrollment, release and recovery

`POST /api/user/claim` accepts `{ "device_id": "…", "claim_token": "…" }`.

| Result | Status and behavior |
| --- | --- |
| Already owned by this authenticated user with a verified epoch | 200, `ownership_verified: true`, `already_owned: true` |
| Claimed by another user | 409, no foreign owner details |
| Not provisioned | 404 |
| No supported trusted possession grant | 503 `claim_verification_unavailable` |
| Wrong user, token, credential version or expired proof | 403 `invalid_claim_proof` |
| Grant consumed while request was in flight | Same-owner idempotent 200, otherwise 409 |

A successful response contains a sanitized `device` with `device_id`, `user_id`, `ownership_epoch`, `claimed_at`, name and telemetry. The main API must require `ownership_verified: true` and exact identity equality before binding a prescription. A 409 is never interchangeable with ownership proof.

There is intentionally **no public device provisioner or grant issuer**. A future trusted enrollment component must verify physical possession through an agreed vendor protocol, rotate/deliver a distinct credential securely, audit the verification, and place a short-lived `claim_grant` on the device:

```json
{
  "method": "vendor-possession-v1",
  "user_id": "verified-session-user",
  "token_hash": "sha256-of-one-use-random-token",
  "expires_at": "ISO timestamp",
  "credential_version": 1
}
```

That method name is a reserved server contract, not a claim that the current firmware implements it. No environment flag turns an arbitrary ID into a verified device. Existing claimed records without an epoch require reviewed migration; the code does not certify them retroactively.

`DELETE /api/user/devices/:device_id/unclaim` clears the owner, claim grant and all caregiver access; changes the epoch; removes the credential hash; and increments/revokes its version in one majority-acknowledged write. Reclaim/transfer requires trusted provisioning and fresh physical possession. Old buffered events cannot be silently attached to a new owner. They need a separately authenticated, reviewed recovery process; current endpoints reject them.

## Observation inbox and durable receipts

Phone upload: `POST /api/user/devices/:device_id/observations`, with the owner's Bearer session. Direct device upload: `POST /api/ingest/event`, with per-device headers and matching body `device_id`.

```json
{
  "event_id": "immutable-event-id",
  "ownership_epoch": "epoch-returned-by-verified-claim",
  "boot_id": "immutable-boot-id",
  "sequence": 0,
  "event": "PILL_CHANGE",
  "timestamp": 1792065600,
  "payload": { "chng": 1, "cnt": 9 }
}
```

`timestamp` above is illustrative; accepted values are integer Unix seconds from 2000 onward, no more than 300 seconds into the server's future and not before the current ownership period. IDs must match `[A-Za-z0-9][A-Za-z0-9._:-]{0,127}`. Sequence must be a nonnegative JavaScript-safe integer. Unknown fields, null/absent identity, unknown event types, key-like payload fields and oversized/deep payloads are rejected. Do not generate new IDs on retry. Out-of-order arrival is accepted; the composite immutable identity deduplicates each sequence rather than rejecting every older sequence as a replay.

Supported case-sensitive event taxonomy from the supplied firmware/docs: `OPEN`, `CLOSE`, `PILL_CHANGE`, `MANY_PILLS_CHANGE`, `OUTSIDE_WINDOW_CHANGE`, `BLE_LOCK_CMD`, `BLE_UNLOCK_CMD`, `EMERGENCY_UNLOCK`, `SAFETY_TIMEOUT`, `VIAL_RESTARTED`, `LOW_BATTERY_5`, `LOW_BATTERY_2`. These names are stored as observations and do not prove ingestion or wrongdoing. Firmware must confirm the actual wire schema before transport is enabled.

Success (including a matching replay) returns HTTP 200:

```json
{
  "status": "stored",
  "evidence_type": "vial_observation",
  "receipt": {
    "event_id": "immutable-event-id",
    "device_id": "vial-id",
    "ownership_epoch": "epoch-returned-by-verified-claim",
    "boot_id": "immutable-boot-id",
    "sequence": 0,
    "committed": true
  }
}
```

`status` is `duplicate` for identical committed content. The unique identities are `(device_id, ownership_epoch, event_id)` and `(device_id, ownership_epoch, boot_id, sequence)`. Conflicting content under either identity returns 409 `event_identity_conflict`. Authorization is checked before a duplicate receipt can be returned. The current device row is written in the same transaction as the event, so release/revoke conflicts with ingestion instead of racing a read-only ownership check. Uncertain commits return an error; retry the same immutable identity and inspect a durable receipt.

Phone uploads are labeled `source: phone_ble`, which records the transport/account assertion and **does not authenticate the hardware measurement**. Direct credential-authenticated submissions use `device_credential`. Neither sets `takenAt`, updates a `Dose`, decrements inventory, or triggers a caregiver alert. The main routine model remains responsible for explicit user confirmations and later audited reconciliation.

A receipt permits the phone to remove that exact upload from its durable inbox. It does **not** authorize blanket firmware `0x31` log deletion. Existing firmware lacks the agreed immutable event/boot/epoch/ranged-ACK contract; keep destructive ACK disabled pending vendor changes and real hardware testing.

`POST /api/ingest/telemetry` accepts `device_id`, optional integer `battery` 0–100 and bounded `firmware_version`. Zero is a valid reading; missing fields preserve existing values, and unknown devices cannot be created.

## History and support

- Existing owner read routes remain, with immutable `owner_id` scoping. Former owners can read their own recorded observations after a transfer; new owners cannot see them. User lists are bounded to 100/500 records as before.
- A device's current epoch scopes caregiver reads. The legacy `caregiver_id` field alone grants no access.
- `POST /api/caregiver/claim-device` now creates a seven-day in-app invitation for an existing registered recipient in the canonical PostgreSQL `User` table and returns 202 `awaiting_acceptance`. Legacy MongoDB profile mirrors are not an identity authority. It sends no external message and gives no access until accepted.
- `POST /api/caregiver/invitations/:invitation_id/accept` requires the intended recipient's session and a current matching epoch; accepted scope is only `observations:read`.
- `DELETE /api/user/devices/:device_id/caregiver` revokes both the grant and pending invitation. Already-authorized requests may finish; future reads are denied.
- No caregiver endpoint can lock/unlock a vial, change medication or log a dose.
- `DELETE /api/user/devices/:device_id/events` returns 405 because raw evidence is append-only. This does not substitute for a separate account-data retention/deletion policy.

## Verification and remaining gates

Run `pnpm test` for validation, authentication, real HTTP boundaries and isolated controller/service tests. Those tests simulate storage and cannot prove MongoDB transactions or index behavior.

For disposable local databases only, set `VIAL_TEST_MONGODB_URI` and/or `VIAL_TEST_DATABASE_URL` with database names beginning `farda_test_`, then run `pnpm test:integration`. Mongo tests exercise actual unique indexes, concurrent retries/claims, abort rollback, ownership transfer, former-owner history and stale caregiver denial. They drop that test Mongo database. PostgreSQL tests create/drop an isolated schema and verify exact quoted session-table mapping, expiration and revocation. Never point them at a live/customer database.

Local implementation verification: 22 isolated/HTTP tests passed, and the session integration test passed against disposable PostgreSQL-compatible PGlite. That integration exposed and fixed raw PostgreSQL timestamp parsing in a non-UTC host timezone; the query now explicitly interprets Prisma's UTC timestamp-without-timezone values as UTC. Expiry/revocation were verified with a Los Angeles database timezone and a Tokyo host timezone. The MongoDB suite remains skipped: the workspace could not start the downloaded MongoDB binary (operation not permitted). CI/disposable replica-set execution remains required before claiming database race validation. Full OTP-created-session interoperability across both running APIs also remains a gate. A local disposable PGlite harness may use `template1` only with explicit `VIAL_TEST_ALLOW_TEMPLATE1=1`; this test still creates/drops only its randomly named isolated schema.

Hardware gates: vendor firmware source/reproducible build, signed/verified possession challenge, encrypted BLE/TLS and key delivery/storage, individual key rotation, canonical identity, immutable event sequence/boot identity, ownership reset and range-specific ACK, clock validity, sensor/calibration accuracy, electrical/mechanical access and power-loss behavior. No backend patch proves these capabilities.
