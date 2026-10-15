# Consumer API core

These endpoints run under `/api` and require the revocable mobile `Authorization: Bearer <session-token>` header unless listed as public. Account IDs come from that session, never from a request body. Responses use `{ "data": ... }` except authentication and OCR extraction. Errors are `{ "error": "consumer message", "code": "machine_code" }` with optional field details.

## Authentication

| Method and path | Body / result |
| --- | --- |
| POST `/auth/send-otp` (public) | `{phoneNumber: "+15551234567"}` → `{message: "code sent"}` only when Twilio Verify accepts the request as pending |
| POST `/auth/verify-otp` (public) | `{phoneNumber, code}` → Better Auth `{status, token, user}` |
| POST `/auth/social-login` (public) | `{provider: "google" | "apple" | "facebook", idToken}`; provider must be configured |
| GET `/auth/session` | `{data: {user: {id, name, email, phoneNumber, phoneNumberVerified}, expiresAt}}` |
| POST `/auth/sign-out` | Revokes this session in shared PostgreSQL; HTTP 204 |

The vial service must check the same Session table and expiration. A database outage is 503, not an invalid-token response. OTP and OCR limits use shared database counters, including unauthenticated IP and normalized phone scopes. Deploy behind a deliberately configured proxy; arbitrary forwarded IP headers are not trusted. Provider delivery is not guaranteed merely because a request was accepted.

Better Auth 1.4 internally swallows failures in its send hook. The public mobile send endpoint therefore awaits Twilio Verify directly. Verification uses the custom Twilio Verify hook, then Better Auth creates the session through its Prisma adapter. The Account mapping preserves `provider`/`providerAccountId` columns while filling the missing adapter fields. No SMS or real verification was sent during development tests.

## Prescriptions and schedules

| Method and path | Result |
| --- | --- |
| GET `/prescriptions` | All owned, non-archived prescriptions as `{data: []}`; each includes `schedules`, newest version first |
| POST `/prescriptions` | Creates a new independent prescription, HTTP 201 |
| PATCH `/prescriptions/:id` | Updates reviewed metadata only; never silently replaces reminders |
| POST `/prescriptions/:id/schedules` | Creates a schedule version and upcoming UTC occurrences atomically, HTTP 201 |
| DELETE `/prescriptions/:id` | Archives, ends active schedules, cancels future unconfirmed occurrences; retains history, HTTP 204 |

Example create body (all dates and medicines here are illustrative):

```json
{
  "clientRequestId": "56b98920-ad24-4a53-b5f6-102a969e94dc",
  "medicationName": "Name transcribed from the label",
  "dosageInstructions": "Exact reviewed directions",
  "labelReviewed": true,
  "rxNumber": "4821",
  "pharmacyOrDoctorName": "My pharmacy",
  "schedule": {
    "recurrence": "daily",
    "times": ["09:00"],
    "timezone": "America/Los_Angeles",
    "startDate": "2027-01-15",
    "durationDays": 30
  }
}
```

`clientRequestId`, `medicationName` and explicit `labelReviewed: true` are required. Generate one stable request ID per draft (UUID recommended, 8–100 alphanumeric/period/colon/underscore/hyphen characters). Keep that key for an unchanged retry. The user-scoped unique key and canonical request hash return the same medication and schedule on a matching retry (HTTP200, original create201); key reuse with changed content returns409 `idempotency_conflict`. A deliberate draft change needs a new key. The key/hash are not exposed in record responses. A reviewed medication may have unknown directions (`null`) but cannot activate reminders until directions are supplied and reviewed. Metadata also supports `storeNumber`, `contactDetails`, `address`, `dateFilled`, `dateExpired`; dates use valid `YYYY-MM-DD`. Unrecognized body keys are rejected, including `userId`. A non-null `deviceId` returns `pairing_required`: secure vial pairing is a separate workflow, not implicit medication creation or an ignored ownership conflict.

The schedule contract requires all five fields shown; there are no default inferred times, duration or timezone. Supported recurrence is currently **daily only**, 1–4 unique `HH:mm` times, 1–366 days. PRN, weekly, taper, interval and variable instructions must not be silently approximated. `effectiveAt` optionally sets a future ISO instant; omit it for "now". Past-effective edits and plans without upcoming occurrences are rejected. Each local day resolves separately in its IANA timezone, preserving wall-clock time across ordinary DST shifts. A requested time that falls in a DST gap or repeated hour is rejected with `ambiguous_local_time`; the app must offer an explicit alternative. No travel-timezone behavior is inferred.

Schedule edits run in serializable transactions. They never delete occurrences. Past unconfirmed records and terminal self-reports remain; only future unconfirmed rows are cancelled. A new version does not duplicate an already taken/skipped occurrence at the same time. The finite schedule ends after the requested duration; there is no silent extension. The UI should show the ending date and let the person explicitly extend their reminder plan.

## Dose records and corrections

| Method and path | Contract |
| --- | --- |
| GET `/doses?from=<ISO>&to=<ISO>` | `{data: Dose[]}` in `[from,to)`, at most 367 days per request; default past31/next62 days |
| PATCH `/doses/:id` | `{status?, takenAt?, note?, mood?, reason?, expectedRevision?}` → `{data: Dose}` |
| GET `/doses/:id/history` | Owned append-only correction records in revision order |

Dose fields include `id`, `prescriptionId`, `userId`, `scheduledFor`, `scheduleVersionId`, `status`, `takenAt`, `source`, `revision`, `note`, `mood`; list responses include prescription display name/directions. Stored status is `unconfirmed`, `taken`, `skipped` or `cancelled`. Clients may explicitly set the first three; cancelled schedule occurrences cannot be reactivated by status editing.

Updating only mood or note leaves both status and takenAt unchanged. `takenAt` is accepted only with an explicit `status: "taken"` and cannot be in the future. Setting taken without a time records now as the user's self-report. Correcting to unconfirmed or skipped clears takenAt and preserves the previous value in the audit trail. No vial signal or call outcome enters this endpoint automatically.

Send `expectedRevision` from the loaded record to avoid stale writes. A stale version returns 409; a database/transaction interruption can return 503. Re-read before retrying an uncertain write. Medication creation supports the stable request key described above. Dose edits use optimistic revisions; a retried already-committed edit with the old revision returns409 and should be reconciled from the current record.

## OCR

POST `/prescriptions/ocr/extract` accepts multipart `image` files: max4, max8MB each, JPEG/PNG/WebP only. Authentication and rate limits run before buffering. MIME signatures are checked; invalid or incomplete model output fails closed. Images remain in request memory and are not written to temporary disk. No image contents or provider errors are logged.

Output: `{source: "label_ocr", requires_review: true, pharmacy_or_doctor_name, contact_details, date_filled, date_expired, address, rx_number, store_number, medicines_names:[{medicine_name,generic_name,instructions,qty,refills_info,side_effects}]}`. Every extracted text field is nullable. Missing instructions/quantity remain unknown; no medical inference, schedule generation or refill-eligibility decision is requested. OCR is fallible and still requires human label review. Tests verify schema and extraction policy, not real-image model accuracy. `/extract-from-urls` is deliberately unsupported until an authorized asset-ingress policy exists.

Legacy `/prescriptions/ocr/save`, `/user/:userId`, `/user/:userId/doses` and `/doses/:doseId/record` paths are authenticated aliases. Save/record require the canonical reviewed and explicit-status body; old identity-selecting payloads are rejected. Legacy read paths reject a foreign userId and return the new data envelope. No public sample user CRUD remains mounted.

## Migration and verification

`20261015070000_consumer_core` removes the one-prescription-per-user uniqueness restriction without dropping records. It adds review/archive fields, schedules, revisions, corrections, adapter columns and shared rate counters. The original migration omitted Dose, so the additive migration creates it only if missing. Existing Dose rows and takenAt values are retained with `source: legacy_unverified`, `status: unconfirmed`: the old note endpoint populated takenAt without explicit confirmation, so the migration cannot honestly classify those timestamps as self-reported ingestion. Existing prescriptions require label review before new schedules are activated.

Run on an isolated database first, inspect deployed schema drift, back up production, then apply the additive migration in a reviewed release. Never reset production or delete migration history. The destructive package reset script has been replaced by explicit generate/validate/migrate scripts. No production migration was run.

Build: Node22.12+ or24, pnpm11.25 lockfile, `pnpm install --frozen-lockfile --ignore-scripts`, `DATABASE_URL=<build-or-test-url> npm run build`. Generate does not connect to the database. Production startup requires a strong `BETTER_AUTH_SECRET` and HTTPS `BETTER_AUTH_URL`. `npm start` runs compiled output with path aliases.

Unit safety tests cover auth boundaries, strict bodies, OCR unknowns, supported schedule bounds, DST, note/status separation and revision conflicts. `TEST_DATABASE_URL=<isolated-database> npm test -- --maxWorkers=1 --no-file-parallelism` additionally exercises migrations' resulting schema through real HTTP requests, two synthetic accounts, retained history, rollback, concurrent revisions, simulated provider failure, a real Better Auth session and logout. Twilio is mocked in that suite. Native PostgreSQL CI remains necessary in addition to the local PGlite/Postgres WASM check. Set `TEST_DATABASE_SINGLE_CONNECTION=true` only for a single-connection engine such as PGlite; that skips the two native concurrent-transaction tests while retaining sequential idempotency and actual constraint coverage. Run those tests without the flag against native PostgreSQL.

The integration branch must wire reminder cancellation and APNs. Main API status mutation is the authoritative occurrence state; dispatch must recheck it immediately before sending. Hardware possession, sensing accuracy, mobile background delivery, actual carrier behavior and pharmacy fulfillment remain external release gates.
