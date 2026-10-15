# Farda consumer readiness review and product direction

Review date: 2026-10-14, America/Los_Angeles. Repository baseline: `261c84e` on `claude/enterprise-code-review-s359w1`.

This is the historical baseline review. Implementation and verification after that review are tracked in [OVERNIGHT_BUILD_HANDOFF.md](OVERNIGHT_BUILD_HANDOFF.md); statements below about unchanged code describe the review date.

## Recommendation

Build Farda around a specific daily question: **“Did I take it, and what do I need to do next?”** The opportunity is a calm, dependable consumer companion that becomes easier to use when the vial arrives. The current repository is a prototype, not a ship-ready connected product. The largest gaps are identity/ownership, truthful dose records, durable BLE synchronization, and app/API integration—not cosmetic polish.

Do not broaden into a general AI health assistant, automated pharmacy ordering, or a complicated analytics product yet. First make the entire journey work: verified label → user-confirmed routine → reliable reminder → vial observation or manual entry → understandable history → optional, consented support.

### Deliverables from this review

- The repository is cloned into `/workspace/scratch/0d3966dd452e/farda`.
- A separate interactive frontend concept is in `prototypes/consumer-v1/`. The portable `farda-consumer-mock.html` embeds its fonts and the existing vial render.
- Isolated evidence tests were added to both backends; prototype tests exercise its scenarios and interactions.
- Existing production app/backend/firmware logic is unchanged. No fixes, commits, pushes, deployments, real invitations, or device commands were performed.

## Scope and confidence

Reviewed Flutter screens/providers/models/API client, main Express routes/OCR/Prisma, vial ingestion/ownership/caregiver controllers, auth integration, test/CI configuration, and the supplied BLE and hardware documents. Earlier audit reports were used as leads; findings below were checked against current sources rather than accepted wholesale.

The firmware delivery contains a `.bin` and documents, **not firmware source or a reproducible build**. There is no hardware here. Firmware behavior, sensing accuracy, power-loss access, link encryption, certificate verification, secure-boot/eFuse state, and electrical/mechanical safety are not validated by this review. Earlier binary-audit statements about encryption or TLS are investigation leads, not proof of the shipped configuration. The supplied binary SHA-256 is `0fa338f54495a34d0cb7a6a61b554dbbf6dec48d176cebfbe448a4fc671c925f`.

No production services, databases, payment systems, or customer records were contacted. Tests use mocked storage or local sample data. No legal/regulatory classification or clinical-safety conclusion is made here; consumer positioning does not eliminate the need to assess intended claims and use.

## Prioritized engineering findings

P0 = blocks any real-user pilot with medication data or physical control. P1 = required for a dependable consumer beta. P2 = product/maintainability improvements after the basic journey works. Severity describes the reviewed code, not a verified exploit against a deployed environment.

### P0 1 — Prescription and dose endpoints have no user authorization

**Evidence:** `farda-app-backend/src/routes/apiRouter.ts:105–125` mounts extract/save/read/dose-record routes without `isAuthenticated`. In `OcrRoutes.ts`, save trusts `body.userId`, reads trust `params.userId`, and dose updates trust `params.doseId`. The separate authenticated `POST /prescriptions` does not protect these routes.

**Impact:** the exposed application routes permit caller-selected prescription reads/writes and dose updates without an authenticated principal. OCR extraction is also publicly callable at the application layer and can incur provider cost. An external gateway, if one exists, was not inspected and must not substitute for object ownership checks.

**Verification:** isolated real-handler tests reproduce unauthenticated save/read and arbitrary dose mutation. Router registration confirms no relevant route guard.

**Required change:** authenticate the whole sensitive route group, derive identity from the session, enforce ownership in each query, and rate/size-limit expensive actions. Test anonymous rejection, expired sessions, user-A-versus-user-B access, revoked caregiver access, and disallowed fields. Do not merely add an authentication check while keeping caller-controlled ownership.

### P0 2 — OCR is instructed to invent dosage details

**Evidence:** `src/services/OcrService.ts:66–67` asks the model to infer/reconstruct missing instructions using medical knowledge and estimate missing quantity. Output is parsed as JSON and mapped into a prescription without field-level provenance or a verified-plan transition.

**Impact:** a plausible invented instruction can become authoritative-looking product content. The fact that this is called OCR does not make generated instructions extracted facts.

**Required change:** extract only visible text, preserve unknown fields as unknown, retain evidence/crops where appropriate, and validate a strict schema. Require an editable review step and explicit confirmation before creating an active reminder plan. Unreadable directions must block automatic activation, not trigger a medical guess. Test blurred, cropped, multiple-label, contradictory, and instruction-like text in images.

### P0 3 — BLE sync can delete the only copy of events

**Evidence:** `farda-app/lib/screens/connect_onboard/screen_setup_vial.dart:101–134` parses logs then calls `sendAckCommand` with no database write, durable local save, or upload. The supplied BLE protocol states that `0x31` acknowledgement deletes the device log. `triggerLogSync` has no caller elsewhere in `lib/`, so this is an unsafe dormant helper, not a functioning synchronization pipeline.

**Impact:** connecting this helper as written risks irrevocable loss of adherence evidence. It also decodes each BLE chunk independently, uses a final `]` as framing, does not bound the buffer, and does not retain/cancel its stream subscription.

**Required change:** move BLE into a persistent service, with secure binding, explicit protocol state, bounded byte reassembly, timeouts, cancellation, reconnect behavior, and durable receipt. Safest initial sequence: receive → validate → persist idempotently on the server → confirm commit → ACK. If offline ACK is supported, require a durable encrypted phone inbox with restart recovery and a documented uninstall/loss tradeoff. A durable local receipt is not the same as cloud backup. Firmware should ultimately support immutable sequence IDs and batch/offset acknowledgements so an ACK cannot delete events appended during sync.

### P0 4 — Device trust is not tied to an individual vial

**Evidence:** `smart-vial-backend/middleware/authDevice.js` checks one fleet-wide `x-api-key`; `config/config.js:18` supplies a public fallback when the environment value is absent. The authenticated key is not bound to the submitted `device_id`. `ingestion.controller.js` can provision an unknown device through telemetry. In the app, `_connectToDevice` returns a BLE remote identifier after discovery, without a secure-bind sequence or a verified server claim. The documented command set includes lock, unbind, target-changing, and delete operations.

**Impact:** possession of the shared ingestion key grants broad impersonation capability. Knowing a device identifier is not evidence of possessing its hardware. A successful BLE connection is not successful onboarding or authorization.

**Required change:** fail startup when required secrets are absent; use per-device, rotatable credentials and bind authenticated identity to the allowed device. Agree one firmware/server authentication contract. Pair using a physical possession proof plus an encrypted authenticated link; verify the canonical device identity instead of using a platform BLE address as a cross-platform product ID. Protect admin-key enrollment, debug commands, replays, and transfers. These changes require vendor firmware participation and real-device verification.

## P1 findings

| Finding | Current evidence and consequence | Required correction |
| --- | --- | --- |
| 5. App and API contract drift | `farda-app/lib/app_const/app_urls.dart:2–8` uses `dosetime/`, `my-prescriptions/`, `mood/`, and `dose-notes/`. The supplied main API exposes OCR user/dose routes instead. `PrescriptionProvider.getMyPrescriptionApi` expects a list while the backend returns a single object. `env.dart` falls back to an unrelated cleartext LAN host. | Select the canonical API, version its schemas, remove the production HTTP fallback, and run an app-to-API contract test from login through history. A different legacy server may exist; it is not in this checkout. |
| 6. Mood edits fabricate dose-taking | `OcrRoutes.ts:411–418` sets `takenAt` to now even for a mood-only or note-only request. Real-handler test reproduced it. The record cannot distinguish a sensor inference from a user report. | Separate dose-status, notes, and mood operations. Record actor, source, observed time, received time, corrections, and evidence. Never infer ingestion from a mood update. |
| 7. User edits and pairing results are discarded | `screen_prescription.dart` provides Rx/store/quantity controllers, but `PrescriptionProvider.submitPrescriptionApi` submits the original OCR model; DOB has no controller. Setup navigation at `screen_prescription.dart:224–225` ignores the returned value. `calender_repo.dart` saves the literal note `dsfasd`. | Use one validated form state, round-trip edited fields, consume pairing results, and preserve drafts on failure. Remove DOB collection unless there is an actual purpose and data flow. Test edits rather than only initial OCR values. |
| 8. Schedule editing destroys history and ignores user intent | `PrescriptionModel.toSubmit` sends neither frequency nor duration; API defaults are one dose/day for 30 days. Server schedules fixed hours in its own local timezone, starting at the fill date. `OcrRoutes.ts:271–276` deletes **all** untaken entries, not only future ones; delete/recreate is not transactional. Zero-day plans are accepted and clear entries. These behaviors were reproduced with mocked DB handlers. | Store a user-confirmed, timezone-aware schedule with versions and effective dates. Bound integer inputs. Preserve past/confirmed records, transact future changes, prevent duplicate occurrences, and test DST, travel, PRN, tapering, paused plans, and partial failures. Unsupported schedules should be explicit—not approximated. |
| 9. Device-claim conflicts are treated as success | `PrescriptionRoutes.ts:36–44` ignores every upstream 409, even though the vial controller explicitly uses 409 for a device claimed by **another** user. Evidence test confirms the foreign ID is then written into the prescription. | Fail the operation unless an authenticated ownership check proves the same user owns the device. Make claiming atomic; define rollback/recovery if the second database write fails. |
| 10. Ownership transfer leaks relationships and history | `app.api.controller.js:208–220` unclaims a device without clearing `caregiver_id`. The added test reproduces the stale caregiver. Events are identified by device ID, not an ownership epoch; device event readers select by device ID. | Transfer must revoke old caregiver access and credentials, start a new ownership epoch, and scope history to the owner at observation time. Test returns, replacements, resales, account deletion, and concurrent claims. Do not erase a former owner’s records as a shortcut. |
| 11. Vial auth does not implement the mobile bearer contract | `middleware/verifyUserToken.js` calls Better Auth `getSession` with forwarded headers but configures no bearer plugin. The installed library’s session route reads a signed cookie; its bearer plugin performs the header-to-cookie conversion. Flutter sends a bearer token, not that cookie. Main API uses a different direct session-table lookup. Prisma/raw-PG auth schema mapping is also not demonstrated. | Use one versioned identity configuration and intentional mobile auth strategy across services. Test a real OTP-created session against both APIs, including expiration/revocation and table mappings. Do not rely on the misleading comment that bearer headers work automatically. Full DB integration remains untested. |
| 12. Battery and event integrity are unreliable | `ingestion.controller.js:19,27` uses `battery || ...`, so 0% becomes 100% for a new device or retains the old reading. Existing-device 0% was reproduced. Any event string is accepted; an omitted event ID is explicitly written as null. Deduplication looks up a global key before device validation; schema uniqueness is sparse. | Validate battery including zero, timestamps, event enums, and bounded payloads. Require a `(device identity, ownership/boot epoch, monotonic sequence)` dedup identity; test retries, cross-device collisions, late events, index behavior with null/missing IDs, and clock drift on a real DB. The null/index consequence is a risk to reproduce, not a verified DB result here. |
| 13. Tokens and sensitive request bodies are logged | `utilities/api_service.dart` logs request headers/bodies and response bodies; `PrecriptionRepo` prints submitted prescription data. `AuthStorage.saveSession` duplicates the bearer token into SharedPreferences despite secure-storage support. | Redact credentials and medication/personal data at the logging boundary; use secure token storage consistently; avoid PHI-bearing diagnostic screenshots and logs. Test release logging and logout/revocation/cache clearing. |
| 14. Consumer reliability systems are absent | No end-to-end device-event-to-`Dose` reconciliation was found. `Event.processed` has no processing worker in the supplied vial service. No notification delivery/scheduling implementation or offline dose outbox was found in the reviewed app. | Implement the primary journey and recovery paths before making reminder, tracking, caregiver-alert, or refill-automation promises. Treat “event stored” and “dose reconciled” as separate durable steps. |

### P2 — Finish the architecture and remove misleading polish

Home hardcodes identity, date, pill counts, and analytics; `HomeProvider` is empty. Plan says work is ongoing. Calibration/subscription/mood flows are incomplete or not surfaced through the usual path. The router mixes tab-index navigation, ShellRoute, raw Navigator calls, and a commented auth redirect. Some providers initiate loading on first access without an authenticated-session gate. A route guard is UX protection, not a replacement for server authorization.

Retain the useful Outfit typography, existing assets, and theme components. Choose one routing/state-management approach; remove abandoned scaffolding after covering the live path. Replace hardcoded “analytics” with an honest empty state and a short source-labelled timeline. Do not show fabricated progress as live data. Multi-medication support needs a schema change: `Prescription.userId @unique` currently replaces the user’s only prescription, and OCR stores only `medicines_names[0]`.

### Build and test readiness

The original main API suite contains four helper tests. The original vial suite contains three config/JWT-library tests, not actual Better Auth or ingestion integration tests. CI runs tests but does not compile the main API or build the mobile app.

`pnpm build` in the main API fails immediately because the package calls `npm run lint` without declaring that script. A separate `pnpm exec tsc --project tsconfig.prod.json --noEmit` cannot run because TypeScript is not installed as an executable dependency. This review did **not** repair those inputs or infer that compilation would succeed after doing so.

## The consumer product to build

### The promise

“A little less to remember.” The app should help users understand their routine and their record. The vial reduces manual work; it must not be a prerequisite for getting value, a source of unexplained lockouts, or a source of false certainty.

### Everyday experience

1. **Start without the vial.** Let someone add a medication manually or scan a label, review every meaningful field, select reminder times, and log manually. Explain what becomes automatic when the vial is connected. Keep an obvious “connect later” path.
2. **Make Today the useful screen.** One upcoming routine/status and one primary action. Distinguish not yet confirmed, self-reported taken, self-reported skipped, a possible vial removal, and unavailable data. Let users correct mistakes without losing the audit trail.
3. **Connect in a guided, resumable flow.** Physical possession → secure bind → canonical identity → server claim → clock sync → calibration → verification. Explain failure in consumer language; never replace real verification with “type any vial ID.” Avoid requiring Wi-Fi on day one if BLE is the supported transport.
4. **Make history understandable.** “You confirmed at 9:05” and “Vial detected a weight change at 9:02” are different statements. Last synced and unknown periods should be visible. Avoid streaks that punish missing telemetry or imply health outcomes.
5. **Treat refills as a reconciled inventory change.** Show estimated supply with its freshness/uncertainty. Prompt before expected depletion, let users correct count, and validate refill detection. Initial scope is a reminder, not an unintegrated promise of automatic pharmacy fulfillment.
6. **Offer support without surveillance.** Owner-initiated invitations, verified recipients, acceptance, narrow scopes, a delay window, revocation, and quiet hours. Nudge the user first. Offline does not mean nonadherent. Never claim continuous emergency monitoring or grant remote medication access through a generic supporter role.

### What should remain core

Reliable reminders, manual logging, corrections, medication access, and access to/export of a user’s records. Monetization can later explore additional convenience or household features, but withholding core reliability or medication access would undermine the product’s promise. Pricing and willingness to pay need discovery, not assumptions from the repository.

### What to defer

Open-ended medication/dosing chat, inferred medical directions, multi-pill mixing in one vial, fully automated refills, remote lock controls, caregiver escalation before consent/reliability is proven, and decorative analytics without defensible data. Mood can be optional journaling, not the centerpiece of adherence.

## App and firmware contract

The current docs describe request-sync `0x30`, deletion ACK `0x31`, bind `0x12`, reconnect login `0xA4`, calibration `0x20/0x21/0x22`, time `0x32`, and interval controls `0xB4/0xB5`. Documented hardware behaviors include timed re-lock, solenoid cooldown, an emergency-button hold, and load-cell voltage/creep limitations. They explain the intended operation, but do not prove field behavior.

Choose a primary v1 transport deliberately. **Recommendation:** BLE → phone → main API, if supported by verified mobile background behavior, with honest freshness and manual fallbacks. Treat direct Wi-Fi ingestion as a separate optional path until credentials, TLS, schemas, and deduplication are aligned. Do not promise that iOS will keep an arbitrary BLE/background loop alive indefinitely.

| Contract area | Required agreement before integration |
| --- | --- |
| Identity | Canonical immutable device ID, separate platform BLE identifier, proof of possession, ownership epoch, credential rotation and reset rules. |
| Framing | Exact UUIDs and roles, negotiated payload limits, byte framing/length/version, partial UTF-8/chunk handling, ACK/NAK, retry/timeout rules. Do not discover by substring and choose arbitrary writable/notifiable characteristics. |
| Events | Firmware event taxonomy, signed count-change direction, raw sensor/calibration context, battery, sequence/boot epoch, observation time, clock quality, schema version. |
| Delivery | Idempotent durable receipt, explicit commit boundary, batch ACK semantics, replay/duplicate handling, crash recovery, and no deletion of newer unsynced events. |
| Scheduling | User timezone, schedule version, clock drift, DST/travel rules, supported intervals, and whether multiple daily times are actually representable by the device. Never silently approximate app schedules with a single firmware interval. |
| Interpretation | Separate physical observation, inferred removal, and user-reported ingestion. Preserve ambiguous/multiple/out-of-window changes for review. |
| Physical access | Verified behavior with dead battery, missing phone, broken BLE, stuck mechanism, cooldown, and emergency access; no cloud or subscription dependency for safe access. |
| Updates | Source, toolchain lock, configuration/partition table, signed reproducible builds, supported OTA/recovery/rollback strategy, manufacturing image and identity provisioning. Support is not established by the current binary. |

Suggested application model: `Medication`, `ScheduleVersion`, `DoseOccurrence`, `Device`, `OwnershipEpoch`, `RawDeviceEvent`, `DoseObservation`, `UserCorrection`, `ShareGrant`, `NotificationAttempt`, and a durable sync inbox/outbox. Keep ingestion append-only and reconcile in a retryable worker. Do not overwrite the original observation when a user corrects its interpretation. This is a proposed target, not an implemented schema migration.

## Work to finish before the hardware arrives

Sequence these as milestones, not a date commitment. Progress depends on staffing, vendor source access, and what the hardware tests reveal.

### Milestone 1 — Establish a trustworthy software baseline

- Obtain the firmware source and full vendor handoff listed below.
- Close P0 auth/OCR/data-loss/device-trust gaps and stop emitting sensitive logs.
- Pick one API contract and identity model; make a clean install, build, migrations, and seeded synthetic-user run reproducible.
- Build one complete manual journey in Flutter with deliberate empty/error/loading/offline states.
- Turn the evidence tests into safety assertions as each bug is fixed; do not leave tests that celebrate unsafe behavior as the release gate.

**Exit:** two synthetic users cannot read or mutate one another’s records; a reviewed medication and edited reminder round-trip correctly; mood edits do not change dose status; failed writes preserve history and drafts.

### Milestone 2 — Exercise the device boundary without a device

- Create a versioned protocol codec and a fake BLE transport independent of screens.
- Replay recorded/synthetic sessions for ordinary removal, multiple pills, uncertain readings, refills, low/zero battery, stale clocks, disconnect during each step, split packets, duplicates, and reordered batches.
- Verify receive/persist/ACK ordering using crash injection, not only a happy-path stub.
- Test app notification scheduling and offline operations on real phones, with fake device signals. Label simulations clearly.

**Exit:** restart/retry does not lose or duplicate a dose observation; invalid frames cannot mark a dose taken; simulated missing telemetry stays unknown; a manual correction remains authoritative and traceable.

### Milestone 3 — Validate the consumer experience

Use the prototype with people matching the intended initial buyer/user. Include the primary medication taker rather than only a caregiver or a buyer. Have them complete tasks without coaching: add/review a label, edit a reminder, understand an unconfirmed signal, correct a record, connect later, and revoke sharing. Ask what they think the vial proves and what they expect when offline. Misunderstanding is a design defect, even if users like the colors.

Track task completion, hesitation/errors, successful first confirmed routine, reminder permission/delivery outcomes, unconfirmed observation rate, correction rate, sync delay, and support requests. These are proposed measures, not measured results. Set numerical targets after baseline discovery; authorization failures, silent data loss, and false ingestion claims are release blockers rather than acceptable conversion tradeoffs.

## Hardware arrival verification

| Test family | Scenarios to cover | Evidence required |
| --- | --- | --- |
| Pairing and ownership | iOS/Android, two nearby vials, multiple phones, interrupted bind, incorrect proof, recovery, ownership transfer and return. | Correct physical unit claimed exactly once; old users/credentials/scopes no longer have access. |
| Sync durability | No internet, killed app, phone restart, BLE loss, partial/corrupt data, upload failure, duplicate batches, events created during ACK. | Raw observations preserved exactly once across every failure boundary; deletion only after the agreed durable commit. |
| Sensing | Empty/low/full vial, pill size/weight variance, multiple removals, refill, movement/tilt, elapsed time/creep, charge state, temperature, mechanical variation across units. | Logged ground-truth comparisons, false-positive/negative behavior and uncertainty bounds; no invented accuracy percentage. |
| Access and power | Low battery, 0%, unplugging, no phone/network, power-cycle while locked, cooldown, emergency control, jam/recovery. | Verified physical behavior and customer instructions; a powered emergency button must not be assumed to solve a dead battery. |
| Time and reminders | Bad/reset clock, DST/timezone travel, delayed sync, phone locked, reboot, revoked notification permission, unsupported schedules. | Correct schedule semantics, honest status, and tested fallback communication. |
| Security and manufacturing | Link security, replay, unauthorized admin/erase/unlock, target redirection, TLS validation, eFuse/provisioning state, update failure. | Vendor source/configuration plus on-unit tests; do not infer enabled security from linked library symbols. |
| Privacy and support | Vial replacement, shared household, lost phone, caregiver revoke/reassign, deletion/export, diagnostics. | No history crossover, clear permissions, redacted support artifacts, and documented recovery. |

### Vendor handoff to request now

Complete firmware source/history and rights to maintain it; exact SDK/toolchain and dependencies; partition table and build configuration; matching bootloader/application images and checksums; flash offsets and reproducible commands; schematics/BOM/pinout and battery/lock behavior; canonical protocol with realistic captures; provisioning and per-device key lifecycle; secure boot/flash-encryption configuration and verification; update/rollback/recovery plan; calibration procedure, raw sensing experiments, thresholds and limitations; manufacturing tests, serialisation, and acceptance criteria. The current docs’ 4 MB flash setting must match the delivered module and actual flashing layout.

## Frontend concept and verification

The concept keeps the existing product render and Outfit font, with warm ivory, forest green, sage, larger text, and fewer competing actions. It has five views and five switchable device scenarios. Clickable behaviors include explicit dose confirmation/skip/undo, sample snooze, routine edits, a blocked unreadable-label review, simulated setup, history-source filters, and sample sharing/revocation.

It is intentionally **not connected to Flutter, BLE, APIs, notifications, pharmacies, or real recipients**. The proposed QR security and calibration interaction are design requirements to validate with the vendor, not implemented firmware features. Core consumer safeguards shaped the mock: no hardware gate, source-labelled entries, no automatic ingestion claim, visible stale/unknown data, and no remote lock control.

| Check performed | Result and limit |
| --- | --- |
| Frozen dependency installation for both APIs, scripts disabled | Passed; lockfiles unchanged. No migration or external service action. |
| Original suites before additions | Main API 4/4, vial API 3/3 passed. Narrow helper/config coverage only. |
| Main API with added review tests | 14/14 passed: 4 original, 6 defect-characterization cases, 4 schedule-count sanity cases. Correct frequency counts were confirmed; there is no off-by-one frequency-table finding. |
| Vial API with added review tests | 7/7 passed: 3 original, 4 defect-characterization cases. Mocked persistence, not live MongoDB integration. |
| Prototype tests | 11/11 passed; five views × five scenarios render into a DOM stub, transitions/escaping/assets/standalone packaging tested. Not a browser-rendering test. |
| Main API production build | Failed: missing `lint` script; independent compiler check blocked by missing `tsc`. |
| Flutter runtime/build/tests | Not run; Flutter executable unavailable. Source review only. |
| Browser visual/accessibility QA | Not run; required browser-control capability unavailable. Inspect in a real browser before treating the design as visually verified. |
| Hardware, databases, deployed environment | Not tested or contacted. No release-readiness certification. |

## Best next implementation slice

Do not start by implementing every new screen. Deliver **one medication, one user, one vial, one day, end to end**, with honest offline/manual fallbacks and secure ownership. Then implement history/corrections and refill reconciliation; add consented support only after the underlying status is dependable. Expand medications and convenience features after that vertical slice is proven. That is the shortest path from a promising prototype to a consumer product people can trust.
