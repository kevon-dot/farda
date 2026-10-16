# Farda — consumer upgrade plan

October 14, 2026, America/Los_Angeles. Based on baseline commit 261c84e, the code review, supplied screenshot and requested navy/character direction.

This document records the design and acceptance criteria. See [OVERNIGHT_BUILD_HANDOFF.md](OVERNIGHT_BUILD_HANDOFF.md) for implementation status and [the editable Figma handoff](../prototypes/consumer-v2/FIGMA_HANDOFF.md) for native design nodes and code references.

## October 15 build update

Astra refined the native Figma scenes and Flutter now shares their exact exported artwork. Actual rendered screen comparisons cover the primary tabs, narrow/large-text layouts and secondary account flows. See [the visual verification record](../prototypes/consumer-v2/VISUAL_PARITY.md) for evidence and deliberate data-driven differences. Build PR validation and native/device release gates remain distinct.

### Approved Calendar follow-up

The user approved a more expressive Calendar on October 15: week-first navigation, expandable month, a state-aware companion, an obvious Today shortcut and a quieter daily timeline. Astra updated the matching editable Figma frames, including four supporting states, and signed off on the final Flutter renders. Saved-as-skipped and snoozed entries remain distinct from taken entries. Calendar fetches complete weeks around month edges so adjacent-month dates do not appear empty merely because their records were omitted. The full Flutter suite passes 176 tests and nine Calendar captures were refreshed. Replacement CI and build-branch merge are tracked on PR #111; release deployment remains separate.

### Approved prescription onboarding and refill assistant

Implemented October 15: dedicated camera viewfinder; up to four overlapping photos for one long/curved label; enlarged photo review, retake/remove and user-confirmed text coverage; authenticated multi-image OCR with safe manual fallback. Manual entry uses small steps with intact directions and explicit label review. Daily reminders are optional; no daily reminders creates no schedule. Today, Refills and Your routine expose direct Add medication entry points. Refill requests are editable and copyable, with no pharmacy submission claim. Astra added 16 matching editable Figma states; 28 new Flutter screenshots cover 390px and 320px/1.3 text. All 233 Flutter tests passed. See [the focused handoff](../prototypes/consumer-v2/PRESCRIPTION_ONBOARDING_HANDOFF.md). Device camera/OCR evaluation and pharmacy partner integration remain release work.

### October 16 refill agent follow-up

The refill API build is implemented on `codex/refill-agent`: documented Photon connector, trusted prescription links, explicit reviewed submission, durable duplicate protection and separate provider status. Flutter adds the connection card and optional AI question routing; inventory reads are batched. Astra added matching editable Figma states. Local backend validation passes 204 tests; database and native build validation runs in CI. Live sending remains disabled pending partner configuration and sandbox verification. See [the implementation and operator handoff](../prototypes/consumer-v2/REFILL_AGENT_HANDOFF.md) for the current scope and remaining release gates.

## The product to build

Keep the lowercase Farda wordmark, Outfit typography, soft surfaces and reassuring voice. Move to rich navy and make the app feel like a useful daily companion: **Today, an interactive Calendar, a Refill station, and Your space**.

The vial improves the experience but is not required to start. The character adds warmth without becoming an adherence score. Reliable reminders, honest status and easy correction are part of the design, not hidden engineering concerns.

The new mock is at prototypes/consumer-v2/farda-navy-mock.html. It is self-contained HTML with nine views, original character artwork and synthetic data. It does not replace the Flutter app or repair the production backends. V1 is preserved.

## The requested reminder UX

The user's clarification takes precedence over the earlier proposed 20-minute delay. The new default is:

| Time for a 9:00 routine | Experience | Main action |
| --- | --- | --- |
| 8:50 — 10 minutes before | A Live Activity appears: “A little heads-up.” Countdown to the routine in the Lock Screen and Dynamic Island | Open routine; review what's coming |
| 9:00 — scheduled time | The card becomes an active reminder: “Your routine is ready.” A notification can accompany the state change | Log or snooze |
| 9:10 — 10 minutes into the reminder window | An opted-in reminder call follows if still unconfirmed and not snoozed | Answer the reminder; optionally update the record |
| After confirmation or cancellation | A brief acknowledgement, then quiet | View/correct the record in the app |

This interprets “10 minutes within the window” as 10 minutes after the scheduled reminder time. It is a configurable reminder cadence, not a change to prescription directions or a clinical grace period.

Make the flow proactive and legible: show the upcoming call time before it happens. Let users choose calls, snooze, quiet hours and turn them off. Do not ask for a second opt-in every morning once a valid preference is in place.

In the mock, tap **8:50 → 9:00 → 9:10** to move through the sequence. After enabling demo calls, the last step opens the simulated incoming call. The countdown is a design state, not a real running scheduler.

## Every gap, and what good looks like

P0: stop before exposing real users, sensitive data or device control. P1: complete before a credible consumer pilot. These are engineering priorities, not regulatory classifications.

| # | Current gap | The better product/engineering behavior | Concrete change and proof |
| --- | --- | --- | --- |
| 1 · P0 | Prescription/dose routes trust supplied identity without the necessary guards | “My routine” means only my authorized records | Guard OCR/save/read/update routes; derive identity from session; check record ownership in DB queries; bound uploads and abuse. Prove User A cannot read, enumerate or mutate User B's data. |
| 2 · P0 | OCR reconstructs missing instructions/quantity | A scan saves typing; it never invents directions | Extract-only schema with source/provenance and unknown fields; require label review before activation. Cropped/ambiguous/injected labels must not generate a plan. Mock blocks an unreadable directions field. |
| 3 · P0 | BLE deletion ACK can precede durable receipt | Restarting or losing internet cannot erase the only observation | Persistent transport service, bounded byte framing, lifecycle/timeouts, idempotent server commit before ACK. Offline ACK needs a durable encrypted inbox and explicit loss tradeoff. Require firmware batch/sequence ACK semantics; crash-test each boundary. |
| 4 · P0 | Shared fleet key and weak device enrollment | Claim the specific physical vial the person possesses | Per-device rotatable credentials, authenticated identity binding, protected enrollment and physical proof; no fallback secret or telemetry auto-provisioning. Test replay, neighboring vials and foreign IDs. Requires firmware/manufacturing cooperation. |
| 5 · P1 | Flutter routes/response shapes disagree with API | One working login-to-history journey | Canonical versioned API schemas, validated/generated client types, intentional environments and HTTPS. Run real app-to-API contract tests. |
| 6 · P1 | Mood/note edits can mark a dose taken | Notes, observations and self-reports remain different facts | Separate status/note/mood commands; record actor, source, occurrence and timestamps. Preserve corrections. A note update, weight change or connected call must not silently change dose status. |
| 7 · P1 | Form edits, pairing result and real note text are lost | The reviewed values survive save, retry and reopening | One validated draft/form model; explicit mapping to request; consume verified pairing results; preserve failed drafts; remove placeholder notes and unnecessary DOB collection. Round-trip every field. |
| 8 · P1 | Client omits schedule intent; edits delete untaken history | Future reminder edits leave the past intact | Versioned schedules with IANA timezone, effective date, explicit recurrence and UTC occurrences; transact future changes, validate bounds and preserve history. Test DST, travel, PRN/unsupported schedules, zero-day inputs and failed writes. |
| 9 · P1 | Foreign device-claim conflicts are ignored | “Already yours” differs from “belongs to someone else” | Atomic claim plus authenticated ownership check; durable recovery across databases. Test concurrent claims and timeout/retry after partial success. |
| 10 · P1 | Unclaim leaves caregiver/history relationships behind | Hardware transfer does not transfer health history | Ownership epochs, credential rotation, revoked grants/caches/jobs and history scoped to the owner at observation time. Keep former-owner records under that account. Test resale, returns and replacements. |
| 11 · P1 | Session handling differs between services; OTP failure is swallowed | One intentional mobile authentication contract and honest recovery | Align auth versions/adapters and bearer/cookie strategy; verify DB mappings; propagate delivery failures; rate-limit OTP. Prove a real synthetic session works across both APIs and revokes everywhere. |
| 12 · P1 | Zero battery, arbitrary event types and missing IDs corrupt meaning | Zero, unknown and stale are different states | Explicit null handling; strict event schemas; authenticated device + ownership/boot epoch + monotonic sequence deduplication. Test 0%, duplicate/reordered batches, collisions and actual DB null/index behavior. |
| 13 · P1 | Tokens and health data appear in logs/insecure duplicate storage | Diagnose reliability without exposing prescriptions or credentials | Boundary redaction, secure token storage, protected local caches, retention/export/deletion rules and logout/account-switch purge. Inspect release logs and cached access after revocation. |
| 14 · P1 | No complete event-to-dose/reminder reliability loop | Every channel supports the same occurrence and cancellation policy | Append-only observations, retryable reconciliation, durable phone outbox, reminder intents and per-channel attempts. Test restart, delayed sync, denied permissions and late/duplicate callbacks. |
| 15 · P1 | One prescription per user; only first extracted medicine stored | Multiple independent medications, with optional devices | Separate Medication, Prescription, Schedule and DeviceAssignment; migrate safely; one medication per physical vial. Adding a medication must not overwrite another. |
| 16 · P1/P2 | Hardcoded identity/counts/curves and incomplete navigation | Useful real, empty, stale, offline and error states | Four primary tabs; session-gated loading; one navigation/state approach; complete manual journey. Remove fabricated production metrics and orphan scaffolding after covering live paths. |
| 17 · P1 | Tests do not establish a reproducible build or integration | A clean machine builds and exercises the shipped journey | Repair missing build script/dependency inputs; pin toolchains; compile API and Flutter; run real DB authorization tests and synthetic-device E2E. Convert unsafe-behavior evidence tests into safety assertions when fixing code. |
| 18 · Release gate | Firmware binary/docs do not prove real hardware behavior | A versioned, measured hardware/software contract with safe recovery | Obtain source/toolchain/partition/provisioning/update handoff. Validate access with no phone/network/power, sensing/calibration, low battery, sync durability and transfer on real units. A powered emergency button does not establish dead-battery access. |

### Code entry points

The earlier CONSUMER_READINESS_REVIEW.md contains the detailed evidence and line references. The implementation owners should begin here:

- Main API: src/routes/apiRouter.ts, OcrRoutes.ts, PrescriptionRoutes.ts, services/OcrService.ts, src/auth.ts and prisma/schema.prisma.
- Vial service: middleware/authDevice.js, verifyUserToken.js, config, ingestion controller, app.api.controller.js and event models/queries.
- Flutter: app_urls.dart, env.dart, screen_prescription.dart, PrescriptionProvider/PrescriptionModel, calender_repo.dart, screen_setup_vial.dart, api_service.dart and AuthStorage.
- Firmware/vendor: sync/delete ACK semantics, per-device provisioning, canonical identity, safe access, calibration and reproducible builds.

Important correction retained: the server produces the correct occurrence counts for requested frequencies 1–4. The schedule defect is omitted client intent/defaults and unsafe history/time handling, not a frequency off-by-one.

## Visual direction: warm navy, more depth, more personality

| Element | Direction |
| --- | --- |
| Main navy | #142C55 for typography, main actions and selection |
| Deep navy | #0B1D3C for high-depth surfaces |
| Supporting blue | #365C99 for restrained interactive emphasis |
| Pale blue | #E9EEF7 for soft surfaces |
| Warm ivory | #F6F5F0 for the canvas |
| Muted text | #58677D; verify against each actual background |
| Attention | #80500E on #F8ECD8; reserve for practical action, not moral judgment |
| Typography | Existing Outfit; clear hierarchy, generous line height, real text scaling |
| Depth | Ivory canvas → raised white cards → one navy focal card; consistent soft shadows |
| Motion | Brief acknowledgement/transition motion; reduced-motion alternative; no constant distraction |

### Characters

Use one recognizable Farda companion in three poses: welcome, calendar/planning and quiet. The transparent artwork is already integrated into the new mock.

Keep it at welcoming, planning and reassurance moments. Do not make it sad, sick or disappointed when a record is absent. Avoid dose-taking rewards, streak pressure and leaderboards. Functional errors and urgent access instructions need clarity, not decoration. Make the character optional and keep actions readable without it.

The full sprite sheet is suitable for this concept. Production needs optimized sizes or a controlled animation rig; native Live Activities should not carry the full large sheet.

### Interactive calendar

- Tap dates, move months, jump to Today and filter routine/refill events.
- Distinguish self-reported, skipped, planned, ambiguous and unavailable records using text/shape as well as color.
- A blank day is not proof of nonadherence. A refill planning date is not a promised pickup date.
- Day details should support audited corrections. Future reminder editing is a separate versioned schedule action.
- Show timezone and preview changes before saving; ask about travel behavior.
- Provide an agenda/list alternative at large text sizes. Verify screen-reader order, focus, large text and touch targets on devices.

### Other consumer improvements worth building

1. Start without hardware; let a person establish a useful routine immediately.
2. Ask permissions at the moment of benefit: notifications with a reminder, Bluetooth with pairing, calls in call setup.
3. Make manual label entry equal to scanning. Camera/network failure must not trap onboarding.
4. Preserve drafts and explain the exact next recovery action after failure.
5. Give Today one next action, not a wall of analytics.
6. Source-label records briefly; put detailed timestamps and provenance one tap away.
7. Keep last sync and reading freshness visible. “Connected” alone is insufficient.
8. Make correction and undo normal, not a support request.
9. Group routine reminders only when each medication's confirmation remains explicit.
10. Coalesce notification noise across the account, not separately for every medication.
11. Provide redacted diagnostic exports for support; avoid prescription screenshots in generic analytics.
12. Keep basic reminders, corrections, records and medication access out of a lockout/paywall mechanic.
13. Treat the medication taker as the owner; a purchaser/caregiver does not automatically get access.
14. Distinguish delivery requested, permission denied, unreachable and user action.
15. Make the app engaging by reducing effort, not maximizing screen time.

## Refill station: how to ship it

Working interpretation: a digital prescription refill hub. A physical dock is a separate concept, below.

### V1: useful without pretending to be a pharmacy

| Step | Consumer experience | Evidence needed |
| --- | --- | --- |
| Plan | “About 6 days from your last count” | Count/source/freshness and a supported schedule; otherwise no precise estimate |
| Handoff | “Continue with your pharmacy” | Verified official app, website or phone destination |
| Contacted | “You marked: contacted pharmacy” | Explicit user update, not pharmacy acceptance |
| Reviewed/ready | Partner-confirmed status, or “You reported: ready” | Correlated partner update or clearly labelled self-report |
| Received | “You confirmed receipt” | Receipt update; inventory not yet silently changed |
| Add supply | Confirm medication and actual quantity | Deduplicated receipt ledger entry |
| Load vial | Separate medication/vial/count verification | Validated loading and sensor/calibration flow |

Keep total supply, vial-loaded supply, estimates and verified counts separate. Do not double-count a phone entry and subsequent sensor sync. PRN/variable schedules, stale counts and ambiguous changes may not support a days-left estimate. Pharmacy lead times are estimates, not guarantees.

Model refill, renewal, transfer and new prescription separately. Unverified OCR must not decide eligibility. If no refills remain or the prescription is unsupported, route to the pharmacy/prescriber; do not advise altered dosing or automatic substitution.

### Integration sequence

1. Now: stock awareness, refill planning reminders, official pharmacy handoff and user-labelled progress.
2. Contracted partner pilot: patient matching/authorization, request IDs, idempotency, acknowledgement/status webhooks, cancellation and operational ownership.
3. Broader coverage: expand only after actual partner access, geography, security and pharmacy/prescriber responsibilities are established.

Surescripts describes pharmacy-to-prescriber renewal requests and fulfillment messages. This supports the professional workflow; it does not establish an unrestricted consumer “refill any prescription” API for Farda. See the [official E-Prescribing overview](https://surescripts.com/products/e-prescribing).

### If the station is physical

Explore a guided charging/refill dock before an automatic dispensing machine: identify the correct vial, provide stable positioning, guide a verified count/calibration and charge. These are proposed functions, not capabilities proven by the existing hardware.

Validate medication compatibility, wrong-medication prevention, contamination/cleaning, access/child requirements, loading errors, calibration repeatability, power loss and manufacturability. Mechanical design needs a separate requirements and safety review. Do not mix medications or imply the dock autonomously dispenses safely.

## Twilio calls: make the UX real

The repo's Twilio Verify integration handles OTP, not routine calls. Add Programmable Voice on the server behind the occurrence/reminder policy.

### Experience

- Separate call opt-in from phone verification. Allow the person to hear a preview and deliberately place a production test call.
- Default to the requested 10-minute follow-up. Show its time in the active reminder UI. Respect quiet hours and account-level limits.
- Start with a short reviewed script, not an open-ended medical voice agent.
- Example: “Hi, this is your automated Farda reminder. Your routine is ready when you are. Open Farda to check in. To stop reminder calls, press 9.”
- For reminder-only calls, do not force PIN entry just to hear that generic message. Only require identity verification if the user chooses to access details or update their record.
- Optional logging: press 1 to enter a private check-in; verify reminder PIN or hand off securely to the app; then explicitly confirm “I already took it.” Press 2 to snooze after recipient verification; 9 stops calls immediately.
- No recording; voicemail off by default, or separately opted-in generic copy only. No medication name on a shared phone/voicemail by default.
- Do not require repeated consent every morning. Give obvious, immediate preference controls.

The incoming-call layout is illustrative system UI: the phone/carrier controls caller presentation. Farda cannot guarantee the character/caller name is displayed or bypass silent mode/spam filtering.

Twilio's [Call resource](https://www.twilio.com/docs/voice/api/call-resource) supports outbound calling and lifecycle callbacks. A completed connection can be voicemail or an IVR; callbacks can arrive out of order. Keep communication status separate from the routine record. [Gather](https://www.twilio.com/docs/voice/twiml/gather) supports keypad input for a fixed-script flow.

### Required backend work

1. Versioned consent with number, purpose, scope, wording, time and withdrawal; reverify number changes.
2. Durable reminder intent per occurrence/schedule version/channel, plus an attempt ledger.
3. Transactionally reserve an attempt; recheck consent, quiet hours, routine state and caps immediately before dispatch.
4. Store provider correlation/CallSid. Treat a timeout after possible provider acceptance as uncertain dispatch; reconcile rather than blindly creating another call.
5. Validate callbacks with the Twilio SDK and correct public URL/body; strictly correlate the attempt and make replay/out-of-order events harmless. [Webhook security](https://www.twilio.com/docs/usage/webhooks/webhooks-security).
6. If supporting PIN-based updates, secure the verifier, rate-limit attempts, expire session context and reject late updates after cancellation/correction.
7. Logging, snoozing, pause, withdrawal and schedule changes cancel pending intents. Terminating an already starting call is best-effort, not an instantaneous guarantee.
8. Offline app confirmations can reach the server late; disclose that remote reminders may continue until sync.
9. Country allowlist, rate/budget caps, carrier delivery monitoring and consented pilot tests.
10. No automatic supporter calls merely because a user did not answer.

Proposed limits to validate: one call per occurrence and two per account/day; quiet hours 9 PM–8 AM in the user's configured timezone. These are design hypotheses, not medical timing or legal-compliance claims.

Twilio requires compliance with applicable communications rules, including consent and opt-out. Obtain qualified launch-market review for automated calling, health-data handling and relevant contracts; these controls are not a blanket legal/HIPAA determination. [Twilio AUP](https://www.twilio.com/en-us/legal/aup).

## Live Activities implementation

The requested UX is a short routine window with a countdown, active state and optional call follow-up. Keep names private by default, expose stale state and end promptly after resolution.

| Surface | Content and interaction |
| --- | --- |
| Lock Screen before | “A little heads-up” + countdown + routine time |
| Lock Screen active | Clear routine status + Open & log + snooze; upcoming call time when enabled |
| Compact Island | Small Farda mark + countdown/status |
| Expanded Island | More context and a matching routine deep link |
| Minimal Island, production follow-up | Recognizable compact status, not tiny medical text |
| Stale/off | Honest stale label or ordinary-notification fallback |
| Resolved | Brief neutral acknowledgement; end activity |

Apple uses a SwiftUI/WidgetKit extension with ActivityKit lifecycle updates. The Flutter app needs native integration; an HTML/Flutter overlay is not enough. [ActivityKit overview](https://developer.apple.com/documentation/activitykit).

Standard Live Activities have finite lifetimes—up to eight active hours and up to four additional Lock Screen hours—and no direct network access from their sandbox. Design this much shorter routine experience, and validate the chosen APIs and OS support when implementing. [Displaying live data](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities).

Use supported scheduling or ActivityKit/APNs start/update mechanisms for the target OS, with token lifecycle, stale timestamps and expiry. Push budgets and platform scheduling mean exact delivery cannot be guaranteed. Keep ordinary notifications as fallback. Live Activities do not grant continuous background BLE execution. [ActivityKit pushes](https://developer.apple.com/documentation/ActivityKit/starting-and-updating-live-activities-with-activitykit-push-notifications).

Validate real devices, app-killed/restarted states, denied permission, token changes, simultaneous routines, text scaling, privacy and cancellation. Android needs its own notification/widget treatment.

## Target architecture and build order

Preserve Flutter and existing useful components. First unify contracts and ownership; avoid a speculative full-stack rewrite.

| Domain | Proposed records |
| --- | --- |
| Routine | Medication, Prescription, ScheduleVersion, DoseOccurrence |
| Evidence | RawDeviceEvent, DoseObservation, UserCorrection |
| Hardware | Device, DeviceCredential, OwnershipEpoch, CalibrationSession |
| Refills | InventoryLedgerEntry, RefillIntent, PharmacyRequest, FulfillmentEvent, VialLoadSession |
| Reminders | ReminderPreference, ChannelConsent, ReminderIntent, DeliveryAttempt, LiveActivityRegistration |
| Support | ShareGrant, ConsentEvent, AuditEvent and redacted diagnostics |

One occurrence anchors the calendar, local reminders, calls and Live Activities. Channel events never become clinical truth by themselves. Use durable inbox/outbox and idempotent consumers across systems, not one fragile synchronous request.

### A. Trustworthy foundation

Close P0s, redact sensitive logs, align auth/API, repair reproducible builds and add real DB isolation tests. Obtain vendor handoff in parallel.

Exit: user isolation, reviewed-label round-trip, history preservation and durable-before-ACK behavior.

### B. Useful app before hardware

Implement Today, label/routine review, calendar, explicit logging/correction, offline outbox and notification lifecycle in Flutter. Port navy tokens and optional companion.

Exit: a new user completes the manual journey and understands unconfirmed states without coaching.

### C. The reminder rhythm and refill hub

Implement the requested -10 / due / +10 experience, native Live Activities and fallback; pilot consented Twilio calls. Ship manual refill planning/handoff before partner fulfillment.

Exit: tested cancellation, opt-out and callback races; no handoff presented as a pharmacy acceptance; no duplicate stock receipts.

### D. Hardware integration and limited consumer pilot

Use a fake BLE transport now; validate physical access, sensing, power, sync and ownership on real units later.

Exit: evidence for supported configurations and recovery paths. No silent data loss or false ingestion claims.

### E. Pharmacy partnerships and optional dock

Expand only with actual contracted coverage and reconciled statuses. Explore the physical station after the loading/identity journey is validated.

Defer autonomous fulfillment, medical voice chat, caregiver remote locking, multi-pill mixing and decorative analytics until the core promise works.

## Verification and limitations

- The v2 mock has 27 passing Node tests for its actual model/render functions through a DOM stub, including the -10 / due / +10 cadence.
- JavaScript syntax, embedded assets and four key text-palette contrast pairs pass. This is not a complete accessibility audit.
- Browser/native visual QA was not performed because the supported browser-control environment required by the Sites skill is unavailable.
- No real scheduler, phone call, OTP, PIN security, notifications, APNs, pharmacy fulfillment, BLE, persistence or backend integration is implemented by the mock.
- Quiet hours/daily caps are UI/design specifications, not a production scheduler. The mock enforces one attempted call per sample occurrence.
- Stock is a manually reconciled sample count, not a full inventory ledger; dose logs do not decrement it automatically.
- Earlier backend evidence tests characterize defects; passing them does not mean those defects are fixed.
- No production code was replaced, no schema migration was run, and nothing was pushed or deployed.

Test with medication takers, not only buyers/caregivers. Ask them to use the calendar, understand the upcoming call, opt out, correct a log and reconcile a refill. If “contacted,” “received,” “unconfirmed” or “call completed” is misunderstood, improve the interaction before optimizing visual preference.
