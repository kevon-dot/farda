# Farda consumer build handoff

Implementation date: October 15, 2026. Baseline: `261c84e`. Review branch: `codex/consumer-overnight-build`.

This build implements the consumer software foundation described in the [upgrade plan](CONSUMER_UPGRADE_PLAN.md). It is a review build. Pharmacy fulfillment, physical vial validation, and signed iPhone/Apple push testing are separate release gates.

## Product direction

Keep Farda's lowercase branding, Outfit typography, depth, and reassuring tone. The new consumer experience uses navy `#142C55`, deep navy `#0B1D3C`, warm ivory, rounded surfaces, and a companion character. Today, Calendar, Refills, and You are the primary destinations. Manual routines work without the vial.

The requested reminder rhythm uses one occurrence ID across every channel:

| Moment | Experience | Record behavior |
| --- | --- | --- |
| 10 minutes before | Private heads-up and Live Activity | No dose confirmation |
| Scheduled time | Active routine and check-in | User can record, snooze, or leave it unconfirmed |
| 10 minutes after | Consented reminder call when eligible | Answering, delivery callbacks, and vial movement never mean taken |
| Explicit confirmation or cancellation | Update the same record and quiet its reminders | Corrections remain visible in history |

The timing is a reminder preference, not a clinical dosing window or a change to label directions. Calls and background push delivery require server configuration and stay disabled by default.

## Gap-by-gap implementation map

| Original gap | Better behavior in this build | Remaining proof or dependency |
| --- | --- | --- |
| 1. Missing prescription/dose authorization | Session-derived identity and owner-scoped reads/writes, including legacy aliases and OCR | Deployment authorization smoke test |
| 2. OCR invents directions | Extract-only output, unknown values, explicit label review before a schedule | Real label-image evaluation and provider configuration |
| 3. BLE can erase the only copy | Protected account-scoped outbox, bounded framing, exact committed receipts; deletion ACK stays off | Vendor event identity and selective ACK contract; physical interruption tests |
| 4. Shared device credentials | Individually provisioned credentials; no fleet fallback or telemetry enrollment | Manufacturing provisioning and trustworthy possession proof |
| 5. Mobile/API contracts disagree | Canonical consumer APIs, typed app models/adapters, explicit environment roots | Staging login-to-history device test |
| 6. Notes/mood confirm a dose | Separate note, mood, and explicit status commands; revisions and correction history | Pilot review of language and correction UX |
| 7. Drafts and values disappear | Reviewed manual drafts, errors remain recoverable, stable create retry IDs | On-device interruption and accessibility checks |
| 8. Schedule edits erase history | Versioned IANA-timezone daily schedules, retained cancelled occurrences, transactional future changes | Native PostgreSQL concurrency gate; broader recurrence types remain unsupported |
| 9. Foreign vial claims are ignored | Atomic owner checks and expiring, user-bound claim grants | Hardware-backed possession proof |
| 10. Device transfer leaks relationships | Ownership epochs, revoked credentials/sharing, observation-time owner history | Real transfer/replacement exercise |
| 11. OTP/session contracts differ | Honest OTP delivery failure, canonical session lookup/revocation, UTC-safe shared session interpretation | Configured provider and staging end-to-end login |
| 12. Zero and duplicate events are mishandled | Strict event schemas, preserved zero values, scoped replay identities, append-only observations | Native MongoDB replica-set CI and real firmware payloads |
| 13. Sensitive logging and duplicate token storage | Redacted errors, secure session storage, protected outbox, account isolation and invalidation; Android backup disabled | Release log inspection, retention/deletion operations, device backup tests |
| 14. No shared reminder lifecycle | Durable intents/attempts, consent, quiet hours, caps, cancellation and provider correlation | Configured Twilio/Apple delivery and real-device validation |
| 15. One prescription per user | Multiple medications and independent schedules; idempotent creation | Existing-data migration rehearsal with backups |
| 16. Fake metrics and unfinished navigation | Consumer navigation, explicit demo mode, real empty/error/loading states and manual refill flow | Consumer usability testing and native visual QA |
| 17. Build and integration gaps | Pinned Flutter/Android tools, frozen JS installs, compiled API, database tests and CI build jobs | See verification ledger below; never infer a passing CI run from workflow files |
| 18. Unverified firmware and physical behavior | Explicit integration contract and disabled unsupported enrollment/ACK paths | Source/toolchain handoff and physical units; no software test substitutes for this |

## Review and run

- [Editable Figma file](https://www.figma.com/design/BeSPZ5VOwOOlrwKFTpMA4K) and [design-to-code handoff](../prototypes/consumer-v2/FIGMA_HANDOFF.md).
- [Standalone interactive design prototype](../prototypes/consumer-v2/farda-navy-mock.html).
- Flutter consumer implementation: `farda-app/lib/features/consumer/`.
- Native Live Activity implementation and provisioning notes: [ios/LIVE_ACTIVITIES.md](../farda-app/ios/LIVE_ACTIVITIES.md).
- Main API contracts: [CONSUMER_API.md](../farda-app-backend/docs/CONSUMER_API.md).
- Reminder and refill contracts: [reminders/README.md](../farda-app-backend/src/reminders/README.md).
- Device trust and observation contracts: [VIAL_CONTRACT_V1.md](../smart-vial-backend/docs/VIAL_CONTRACT_V1.md).
- Mobile outbox/transport limitations: [device_sync/README.md](../farda-app/lib/services/device_sync/README.md).

Use Flutter **3.47.7** and Java **17**. Copy `farda-app/.env.example` to `.env.development`, `.env.staging`, and `.env.production`, then configure the intended HTTPS `/api` roots. App configuration contains public service URLs, never Twilio, OpenAI, database, or Apple credentials.

```sh
cd farda-app
flutter pub get --enforce-lockfile
flutter analyze --no-fatal-infos
flutter test
flutter run --dart-define=FARDA_DEMO=true
```

Demo mode is explicit, labelled, resettable, and separate from the authenticated repository. Omitting `FARDA_DEMO` uses the real sign-in/manual-routine path. The review APK is a debug demo build, not an app-store release.

For the main API, install the frozen lockfile, configure a disposable database, run Prisma generation/migrations, compile, and run tests. Do not apply migrations to an existing environment before a backup and migration rehearsal. Existing ambiguous legacy `takenAt` values are preserved without silently treating old note/mood writes as explicit confirmations.

## Refill station boundaries

The refill station plans a refill, renewal, transfer, or new prescription; tracks user-reported contact/readiness/receipt; records explicit stock counts; and reconciles receipts through a revisioned, deduplicated ledger. It does not claim pharmacy acknowledgement, place orders, verify eligibility, change directions, or infer consumption from a vial movement. A saved count is a last-reported count, not a guaranteed current supply estimate.

## Verification ledger

Integration verification is in progress. This section will be finalized with the actual commands, results, and any unrun gates before handoff.

The local database runner uses PostgreSQL 17.5 compiled to WebAssembly (PGlite). Persistence, migrations, constraints, and session behavior can be exercised there. Native concurrent-transaction cases are explicitly skipped only when `TEST_DATABASE_SINGLE_CONNECTION=true`; CI leaves it unset and uses native PostgreSQL 16. Native MongoDB could not start in the local workspace; its replica-set integration suite runs in CI.

The Flutter SDK initially contained truncated extracted engine/snapshot files. These were repaired from the checksum-verified official archive, after which the test engine ran. The initial crashes are not application-test results.

## Before a consumer pilot

1. Configure staging endpoints, reviewed migration/backup procedures, provider credentials, verified caller identity, and Apple provisioning. Keep transport flags off until those environments are ready.
2. Exercise consent, quiet hours, delivery delays, revocation, account switching, denied permissions, offline recovery, correction races, and multi-device cancellation on real phones.
3. Verify the Live Activity on supported iPhones, including locked/terminated-app states, token rotation, stale/ended displays, and the compressed native layout.
4. Run the vial contract against real firmware and physical units, including power loss, empty battery, sensing/calibration, transfer, and safe medication access without a phone or network.
5. Arrange an actual pharmacy partner before representing fulfillment as connected. A physical refill dock requires a separate hardware and operations design.

No production database migration, real reminder call, pharmacy request, firmware flash, or production deployment was performed for this build.
