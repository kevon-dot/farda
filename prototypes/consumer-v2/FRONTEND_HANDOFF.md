# Farda consumer v2 — frontend completion and production handoff

Updated October 15, 2026.

[Editable Figma file](https://www.figma.com/design/BeSPZ5VOwOOlrwKFTpMA4K?node-id=9-225) · [Prototype](https://www.figma.com/proto/BeSPZ5VOwOOlrwKFTpMA4K?node-id=2-9&starting-point-node-id=2%3A9)

Rendered comparison and current design evidence: [VISUAL_PARITY.md](VISUAL_PARITY.md).

## Completed in this frontend pass

The Figma handoff has 21 editable 390 × 844 screens: the original 17 plus four Calendar state views. It uses shared variables and components, Outfit styles, and connected prototype flows. Today, Calendar, Refills, You, Routine, Reminders, Vial, Circle, Live Activity states, reminder-call states, explicit confirmation, refill handoff, and snooze are represented.

The production Flutter project now has a consumer-v2 implementation under `farda-app/lib/consumer_v2/`:

- A four-tab `FardaConsumerShell` for Today, Calendar, Refills, and You.
- Routing under `/consumer/v2`, nested tab URLs, and redirects from the previous `/home`, `/plan`, `/calendar`, and `/more` paths. Signed-in sessions now enter Today; account tools remain reachable from the consumer flow.
- A shared navy/ivory theme layer and the repository-owned companion artwork.
- Today with date selection, an explicit two-step dose confirmation, snooze, skipped/correction flows, and reminder-milestone previews.
- Calendar with week-first navigation, expandable month, a state-aware companion, Today shortcut, distinct scheduled/snoozed/skipped/recorded markers, and a daily agenda that prioritizes unresolved entries. Complete-week fetching covers adjacent-month dates; local-date arithmetic preserves daylight-saving boundaries.
- Refills with supply estimates, pharmacy handoff preparation, user-managed status, receipt, and explicit inventory reconciliation.
- You with local flows for Routine, Reminder Preferences, Vial, Circle, Live Activity, and reminder-call previews.
- A pure-Dart reminder-occurrence state machine covering the 8:50 heads-up, 9:00 due state, and optional 9:10 call. It enforces consent, verification, quiet hours, one call attempt, idempotency, and explicit confirmation.
- Widget/domain tests for the shell, Today, Calendar, Refills, and reminders.

The standalone design widgets do not place calls, schedule notifications, contact a pharmacy, send invitations, connect a vial, or start a Live Activity. Their sample actions are local previews unless a repository is injected at the authenticated route boundary. The integration status below supersedes the original persistence boundary for Today and Calendar.

### Integration progress (October 15, 2026)

The authenticated `/consumer/v2` routes load one owned snapshot through `ConsumerApiRepository`. Today shows each occurrence for the selected day; taken, skipped, and snoozed actions wait for server confirmation, and a selected entry can open the existing correction form. Calendar renders fetched routine and refill-plan events. Refills now supports account-backed planning, user-reported progress, count edits, and receipt reconciliation, including an explicit choice about whether the received quantity is already counted. You displays saved routine and reminder preferences and saves supported channel toggles and quiet hours after server confirmation and explicit call consent. Vial, Circle, native-surface and privacy previews remain labeled local demonstrations. Empty accounts and failed loads do not fall back to sample medication. The standalone Figma widgets still support injected sample state for design tests. No live provider or hardware work is implied by this UI integration.

The earlier UI audit is recorded in [UX_AUDIT.md](UX_AUDIT.md). The latest rendered pass is recorded in [VISUAL_PARITY.md](VISUAL_PARITY.md): Flutter now shares native SVG character and scene exports with Figma. Calendar adds a larger companion welcome, separate day capsules, a prominent warm action card, compact upcoming cards, and quiet/saved/snoozed character moments. The implementation retains shared navy/ivory controls, restrained warm accents and truthful preview labels. Extra Calendar state frames complement the original 17 screens.

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

The authenticated consumer API is now present under `farda-app-backend/src/routes/apiRouter.ts`: prescriptions and schedules, bounded dose reads, explicit dose updates and history, reminder preferences/snooze, refill plans, and inventory counts/receipts. The consumer Prisma models now include dose revisions/corrections, reminder preferences/intents, and refill/inventory records. `ConsumerApiRepository` calls this contract; the old dashboard and OCR paths still coexist. The reminder service has an occurrence-scoped durable intent model and a gated worker. Read `farda-app-backend/src/reminders/README.md` for its exact behavior and limits.

Remaining integration: handle stale/conflicting writes consistently in all screens, and finish any Circle grant/device observation contract before those previews become functional. Keep vial observations separate from user-confirmed dose records. Database migration application and operational rehearsal are release work; the presence of a migration in source does not establish a migrated environment.

### P0 — security and privacy

- Require authentication and resource ownership for every prescription, routine, occurrence, refill, Circle, and device operation.
- Preserve the existing redacted `ApiService` and consumer repository logging boundaries as new screens are connected.
- Preserve signed Twilio webhook validation and the current call behavior: it never changes a dose to `taken`. Any future private phone confirmation needs a separately reviewed authentication and explicit confirmation flow.
- Encrypt sensitive data at rest and define retention/deletion rules for reminder delivery and call metadata.
- Resolve the existing security findings in `reviews/` before production or clinical use.

### P0 — Flutter application integration

Finish supported account flows while keeping presentation callbacks explicit.

- Keep all four tabs hydrated from the same authenticated account snapshot and expand the remaining local previews only behind supported account APIs.
- Map loading, empty, offline, stale, conflict, and retry states.
- Use optimistic UI only where a failed write can be rolled back safely.
- Apply timezone and daylight-saving changes to future delivery without rewriting past occurrences.
- Wire Routine label review to the existing prescription flow without treating OCR output as approved instructions.
- Connect the Vial screen to the existing BLE setup/calibration flow; keep movement observational.
- Extend You preferences and Circle grants only through authenticated APIs with explicit consent; reminder toggles and quiet hours are persisted, while Circle is still a preview.
- Visually review narrow/large-text layouts and, if those flows evolve, add separate Figma frames for the Flutter Today character variants.

### P1 — notifications and scheduling

The server reminder service models the heads-up, due, delayed call, snooze, and cancellation intent. Complete and validate native notification scheduling/delivery, reboot/app update restoration, permission denial, and occurrence-scoped cancellation on devices.

The app needs production copy and behavior for notification permission, denied state, OS settings, timezone changes, stale content, and notification tap routing.

### P1 — Twilio reminder calls

Versioned call consent, verified-number and quiet-hours gates, one-attempt limits, signed callbacks, and cancellation are implemented behind disabled-by-default server configuration. Answering a call leaves the dose unconfirmed. Remaining work is provider configuration and real carrier validation, operational monitoring, consent/compliance review, and any separately authenticated phone confirmation flow if retained. See `farda-app-backend/src/reminders/README.md` before enabling the worker or calls.

### P1 — iOS Live Activities

The repository has an ActivityKit extension and a foreground Flutter bridge with unsigned simulator CI coverage. Finish APNs/background token registration and server delivery, entitlements/signing validation, and real-device lifecycle handling. Map the preview states to `before`, `due`, `snoozed`, `stale`, `confirmed`, and `off` only when delivery is supported.

Use privacy-safe Lock Screen content by default. Expiration, denied permission, device restart, late pushes, and explicit confirmation must end or update the correct activity. The Flutter preview is visual reference only.

### P1 — vial and refill integrations

- Define a versioned BLE event envelope with device ID, event ID, timestamp, quality/confidence, and firmware version.
- Deduplicate device events and expose offline/uncertain readings without changing the occurrence record.
- Test pairing, calibration, reconnect, low battery, unavailable permissions, and firmware mismatch on real hardware.
- Choose a refill operating model. Until a regulated partner/API exists, keep the UI as a pharmacy-contact handoff and never describe it as an order.

## Verification and release gates

The app pins Flutter `3.47.7` in `.fvmrc`, matching both mobile CI jobs. In a Flutter-capable environment, run:

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

The remaining integration is complete when supported account actions across the four Flutter tabs use one authenticated source of truth; every state-changing request is idempotent and audited; notification, call, Live Activity, refill, Circle, and vial behavior preserves the invariants above; the full Flutter suite passes; and the release gates are documented with device evidence.
