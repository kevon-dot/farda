# Farda consumer v2 — frontend completion and production handoff

Updated October 15, 2026.

[Editable Figma file](https://www.figma.com/design/BeSPZ5VOwOOlrwKFTpMA4K?node-id=9-225) · [Prototype](https://www.figma.com/proto/BeSPZ5VOwOOlrwKFTpMA4K?node-id=2-9&starting-point-node-id=2%3A9)

## Completed in this frontend pass

The Figma handoff is complete and was read back from the design file. It has 17 editable 390 × 844 screens, shared variables and components, Outfit styles, and connected prototype flows. Today, Calendar, Refills, You, Routine, Reminders, Vial, Circle, Live Activity states, reminder-call states, explicit confirmation, refill handoff, and snooze are represented.

The production Flutter project now has a consumer-v2 implementation under `farda-app/lib/consumer_v2/`:

- A four-tab `FardaConsumerShell` for Today, Calendar, Refills, and You.
- Compatibility routing from the existing `/dashboard` entry point, nested tab URLs, and redirects for the previous `/home`, `/plan`, `/calendar`, and `/more` paths.
- A shared navy/ivory theme layer and the repository-owned companion artwork.
- Today with date selection, an explicit two-step dose confirmation, snooze, skipped/correction flows, and reminder-milestone previews.
- Calendar with month/date navigation, filters, status markers, agenda cards, empty states, and accessibility semantics.
- Refills with supply estimates, pharmacy handoff preparation, user-managed status, receipt, and explicit inventory reconciliation.
- You with local flows for Routine, Reminder Preferences, Vial, Circle, Live Activity, and reminder-call previews.
- A pure-Dart reminder-occurrence state machine covering the 8:50 heads-up, 9:00 due state, and optional 9:10 call. It enforces consent, verification, quiet hours, one call attempt, idempotency, and explicit confirmation.
- Widget/domain tests for the shell, Today, Calendar, Refills, and reminders.

The frontend is deliberately honest about its boundary. It does not place calls, schedule notifications, contact a pharmacy, send invitations, connect a vial, start a Live Activity, or persist a dose. Those actions remain local previews until the integrations below are implemented.

## Invariants the production services must preserve

1. Only an explicit user confirmation may change a routine occurrence to `taken`.
2. Answering a call, opening a notification, and vial movement are observations, never ingestion confirmation.
3. Snooze changes reminder delivery only. It must not change prescription directions, the routine schedule, or the dose record.
4. A reminder call requires both a verified phone number and separate, revocable call consent. OTP verification alone is not consent.
5. An occurrence may create at most one reminder-call attempt. Retries caused by webhook or worker delivery must be idempotent.
6. Explicit confirmation cancels all remaining delivery for that occurrence, including a pending snooze follow-up.
7. Refill handoff is not an order, pharmacy acceptance, insurance approval, or receipt. Inventory changes only after the user records receipt and confirms the actual count.
8. Routine edits affect future occurrences. Existing occurrences and their audit trails remain immutable.

The reference implementation for reminder transitions is in `farda-app/lib/consumer_v2/reminders/`.

## Remaining work

### P0 — data contract and persistence

Create one authenticated, ownership-checked API contract for the mobile app. The current Flutter repositories call legacy `dosetime/`, `mood/`, and `my-prescriptions/` shapes, while the included main API exposes prescription OCR routes such as `/api/prescriptions/ocr/user/:userId/doses`.

The current Prisma `Dose` record only has `scheduledFor`, `takenAt`, `mood`, and `note`. It cannot safely represent consumer-v2 behavior. Add, at minimum:

- Stable routine and occurrence IDs, timezone, scheduled wall-clock time, and schedule revision.
- Occurrence status (`unconfirmed`, `taken`, `skipped`) without inferring `missed` from missing data.
- Confirmation source, confirmation ID, actor, timestamp, correction history, and audit entries.
- Reminder consent/preferences, quiet hours, delivery/call state, snooze state, call-attempt count, and idempotency keys.
- Refill planning, handoff, user-entered receipt, count reconciliation, and pharmacy-contact state.
- Vial observations stored separately from user-confirmed routine records.
- Optional Circle grants with narrow, revocable permissions and an audit trail.

Recommended mobile-facing operations:

- Read routines and occurrences for a bounded date range.
- Explicitly confirm, skip, correct, or snooze one occurrence with an idempotency key.
- Read/update reminder preferences and consent.
- Read/update refill planning and reconciliation state.
- Read/update device connection status and ingest observations without updating the dose record.
- Read/create/revoke Circle grants.

Persist the reducer state and its delivery intents atomically, using an outbox or equivalent. Do not let a background worker write `taken` directly.

### P0 — security and privacy

- Require authentication and resource ownership for every prescription, routine, occurrence, refill, Circle, and device operation.
- Redact authorization headers, medication data, phone numbers, and response bodies from `farda-app/lib/utilities/api_service.dart` logging before connecting the new UI.
- Validate Twilio webhook signatures and authorize any private phone check-in before accepting a confirmation.
- Encrypt sensitive data at rest and define retention/deletion rules for reminder delivery and call metadata.
- Resolve the existing security findings in `reviews/` before production or clinical use.

### P0 — Flutter application integration

Replace each screen's sample/local state with repositories and a shared occurrence controller while keeping presentation callbacks explicit.

- Hydrate Today and Calendar from the same occurrence records.
- Map loading, empty, offline, stale, conflict, and retry states.
- Use optimistic UI only where a failed write can be rolled back safely.
- Apply timezone and daylight-saving changes to future delivery without rewriting past occurrences.
- Wire Routine label review to the existing prescription flow without treating OCR output as approved instructions.
- Connect the Vial screen to the existing BLE setup/calibration flow; keep movement observational.
- Persist You preferences and Circle grants only after authenticated APIs exist.

### P1 — notifications and scheduling

Implement a timezone-aware scheduler for heads-up, due, snooze, and cancellation events. It must restore schedules after reboot/app update, handle permission denial, and use occurrence-scoped identifiers so confirmation cancels exactly the intended notifications.

The app needs production copy and behavior for notification permission, denied state, OS settings, timezone changes, stale content, and notification tap routing.

### P1 — Twilio reminder calls

The repository currently uses Twilio Verify for sign-in; reminder calls are a separate feature and consent surface.

- Store versioned call consent independently of phone verification.
- Queue one optional call only when the occurrence is still unconfirmed at the configured delay and outside quiet hours.
- Cancel queued delivery on confirmation, snooze, opt-out, or routine cancellation.
- Make job delivery and status webhooks idempotent.
- Answering or completing the call must leave the occurrence unconfirmed.
- If private phone confirmation is retained, require a reviewed authentication method and a final explicit confirmation step.
- Implement opt-out, error, carrier, retry, and compliance handling with legal review.

### P1 — iOS Live Activities

Add an ActivityKit/WidgetKit extension, entitlements, App Group if required, push-token registration, server start/update/end support, and lifecycle handling. Map the existing preview states to `before`, `due`, `snoozed`, `stale`, `confirmed`, and `off`.

Use privacy-safe Lock Screen content by default. Expiration, denied permission, device restart, late pushes, and explicit confirmation must end or update the correct activity. The Flutter preview is visual reference only.

### P1 — vial and refill integrations

- Define a versioned BLE event envelope with device ID, event ID, timestamp, quality/confidence, and firmware version.
- Deduplicate device events and expose offline/uncertain readings without changing the occurrence record.
- Test pairing, calibration, reconnect, low battery, unavailable permissions, and firmware mismatch on real hardware.
- Choose a refill operating model. Until a regulated partner/API exists, keep the UI as a pharmacy-contact handoff and never describe it as an order.

## Verification and release gates

The app pins Flutter `3.41.3` in `.fvmrc`. In a Flutter-capable environment, run:

```bash
cd farda-app
cp .env.example .env.development
cp .env.example .env.staging
cp .env.example .env.production
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
cd ..
node --test prototypes/consumer-v2/mock.test.mjs
git diff --check
```

Before release, also complete:

- iPhone SE/small Android, standard phone, large phone, tablet, and rotation checks.
- Dynamic Type/text scaling, VoiceOver/TalkBack, contrast, focus order, reduced motion, and 44–48 point touch targets.
- Golden or screenshot comparisons for the 17 Figma states.
- Offline, slow, failed, duplicate, and conflicting-write tests.
- Timezone/DST, quiet-hours boundary, notification permission, and one-call-limit tests.
- Real-device BLE and iOS Live Activity lifecycle tests.
- Security, privacy, legal/compliance, and clinical-safety review appropriate to the intended product claims.

## Definition of done for the next owner

The remaining integration is complete when the four Flutter tabs use one authenticated source of truth; every state-changing request is idempotent and audited; notification, call, Live Activity, refill, Circle, and vial behavior preserves the invariants above; the full Flutter suite passes; and the release gates are documented with device evidence.
