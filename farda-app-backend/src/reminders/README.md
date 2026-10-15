# Routine reminders and refill planning

This module implements the requested 10 minutes before / due / 10 minutes after rhythm on the canonical Dose ID. Apply the consumer-core migration before the reminder/refill migration. Calling and the worker are disabled by default. No live calls were made during development.

## Integration

Mount createVoiceWebhookRouter(), createReminderRouter() and createRefillRouter() under /api. The consumer routers enforce isAuthenticated themselves. The voice webhook router instead requires the Twilio SDK signature, configured AccountSid, exact canonical public URL, form content type, attempt ID, recipient number and CallSid correlation.

Call startReminderWorker(reminderService) only from the process lifecycle. It returns an asynchronous stop function: await it before disconnecting the database so any in-flight dispatch can finish its durable commit. It performs a bounded poll every 15 seconds when FARDA_REMINDER_WORKER_ENABLED=true. At scale, replace the 1,000-occurrence/100-intent poll with paginated partitioned jobs; monitor backlog before exceeding these bounds.

Inside canonical explicit dose-status and schedule-change transactions, call cancelOccurrenceReminders(tx, doseId, reason). For schedule changes the helper accepts an array of occurrence IDs and updates their intents in a bounded number of queries. Dispatch also rechecks live status so missing/late cancellation hooks cannot authorize a resolved entry. Snooze writes the same canonical revision and DoseCorrection audit stream.

## Enablement configuration

| Variable | Meaning |
| --- | --- |
| FARDA_REMINDER_WORKER_ENABLED | Must equal true to start polling. |
| FARDA_VOICE_ENABLED | Must equal true to permit provider calls. |
| TWILIO_ACCOUNT_SID / TWILIO_AUTH_TOKEN | Server credentials; never send to the app. |
| FARDA_TWILIO_VOICE_FROM | Explicit Twilio calling number in E.164. OTP sender configuration does not enable calls. |
| FARDA_PUBLIC_BASE_URL | Canonical HTTPS origin only, for example https://api.example.com. No path or forwarded-host inference. |
| FARDA_VOICE_ALLOWED_PREFIXES | Explicit comma-separated dialing prefixes, for example +1. A dialing prefix may cover multiple countries; this is not a legal market-approval system. |
| FARDA_VOICE_MAX_CALLS_PER_HOUR | Global attempt cap, default 20, hard maximum 100. |

Before a consented pilot, provision caller identity, validate the real public callback URL/proxy, review market requirements and monitor carrier delivery. A verified number alone is not call consent. The app must display the returned wording and submit callConsent:true and consentVersion:voice-v1 when enabling calls. New numbers require a new consent record. Disable/press 9 withdraws active consent and cancels pending calls.

## Consumer API

All paths below are relative to /api and use the authenticated session, never a supplied user ID.

| Method / path | Request and behavior |
| --- | --- |
| GET /reminders/preferences | preferences, phoneVerified, capabilities, consent wording/version, cadence. |
| PUT /reminders/preferences | callsEnabled, liveActivitiesEnabled, timeZone (IANA), quietHoursStart/End (HH:mm), optional explicit callConsent/consentVersion. |
| POST /reminders/occurrences/:id/plan | Idempotently create intents for an owned occurrence. |
| GET /reminders/occurrences/:id | occurrenceId, scheduledFor, status, takenAt, snoozedUntil, updatedAt, revision, windowEndsAt, callAt, intents and cadence. |
| POST /reminders/occurrences/:id/snooze | minutes (5–30), optional expected revision. Only an unconfirmed active occurrence may be snoozed. |
| GET /refills | User-labelled plans; pharmacyConnected:false; receiptReconciled and receipt summary (id/quantity/delta/createdAt). |
| POST /refills | prescriptionId, kind (refill/renewal/transfer/new), optional plannedFor ISO timestamp. Reuses an active same-kind plan. |
| PUT /refills/:id/status | status: contacted/ready/received/cancelled. These are user reports, not pharmacy acknowledgement. |
| GET /inventory/:prescriptionId | Last reconciled quantity/source/freshness/revision; estimate:null. |
| PUT /inventory/:prescriptionId | quantity, observedAt ISO timestamp, idempotencyKey; revision required when a count exists. |
| POST /refills/:id/receipt | quantity, inventoryRevision, alreadyIncluded, idempotencyKey. Requires received status and prior count. |

Supply is an explicit count/receipt ledger. It is not decremented when a dose is logged, does not infer consumption from a sensor and does not report invented days remaining. Counts older than seven days are marked stale. If a count was made after the receipt, it cannot blindly add that receipt again: reconcile whether it was already included. A refill receipt has a unique ledger entry independent of a retry's request key. Receipt status alone never changes quantity. No pharmacy ordering, eligibility or fulfillment integration is claimed.

## Delivery guarantees and limits

- One intent per occurrence/channel/stage and one voice attempt per intent. Reservation uses a serializable transaction plus global/account advisory locks, unique indexes and serializable conflict retries.
- Recheck occurrence, verified number, current consent, allowed dialing prefix, quiet hours and caps before reservation; recheck them immediately before dispatch. Defaults are quiet 21:00–08:00 in the selected timezone, maximum two attempts per account/local day and one per occurrence. Failed or uncertain attempts consume the budget.
- A voice intent becomes due at +10 minutes and expires five minutes later. Worker delay cannot create a surprise call long after the intended time. The overall UI reminder window ends at +60 minutes; neither window changes prescription directions.
- Snooze suppresses the occurrence's voice call permanently in this first version. Native notifications can resume; no late replacement call is implied. Cancellation does not resurrect an old intent if consent is enabled again.
- A process crash or provider timeout may occur after acceptance. Such attempts stay uncertain and are never blindly retried. Signed callbacks can reconcile the provider SID/status. Unknown outcomes without a callback/SID require operational review; no automatic retry is implemented.
- A confirmation racing a provider request can still allow a brief ring. The worker and post-dispatch recheck make best-effort call termination, and the voice endpoint suppresses the script after cancellation. This is not a distributed instantaneous-cancellation guarantee.
- Generic reminder plays only when synchronous answering-machine detection says human. Machine/unknown/fax hangs up; detection is imperfect. No recording, medication name, PIN prompt, or health-record mutation is included. Press 1 directs the person to an authenticated app check-in; press 9 opts out. A call callback never means taken.
- Live Activity intents persist on the same occurrence. liveActivityDeliveryEnabled:false is intentional: APNs token registration, background start/update delivery and multi-device delivery retries are not implemented by this module. The native foreground bridge is a separate implementation.
- Account deletion cascades consent, intents, attempts and refill/inventory records through database foreign keys. Production retention, encrypted backups, monitoring and access policy still need operational configuration.

## Validation

Unit/service/HTTP tests cover cadence, DST quiet hours, consent, duplicate reservation, cancellation races, provider uncertainty, signature validation/correlation, callback replay/order, session boundaries, inventory revisions and deduplicated receipt reconciliation. The memory test store injects races and failures; it does not prove PostgreSQL locking. Gated tests in tests/reminders-postgres.test.ts run against a disposable TEST_DATABASE_URL only and validate actual schema constraints, concurrent reservations/receipts, persisted snooze/audit and cascade cleanup. No default production DATABASE_URL is used by those tests.

The local PGlite server supports one database connection rather than native multi-session concurrency. Set TEST_DATABASE_SINGLE_CONNECTION=true for that runner: persistence/replay/foreign-key cases still execute, and the two concurrent-transaction cases are explicitly skipped. Those concurrency cases require native PostgreSQL in CI; no claim of native concurrency validation follows from the local PGlite result.

Provider references: [Twilio Call resource](https://www.twilio.com/docs/voice/api/call-resource), [webhook security](https://www.twilio.com/docs/usage/webhooks/webhooks-security). Real carrier delivery and native device behavior are not established by passing local tests.
