# Farda build integration — October 16, 2026

The build source is `claude/enterprise-code-review-s359w1`. This ledger distinguishes merged software from service activation; it does not record a production deployment.

## Integrated software

- Today/Calendar visual and interaction polish (#118), refill navigation intelligence (#119), guided multi-photo prescription capture and account-switch protection (#120), private Family Circle flows (#121), and request lifecycle/coalescing improvements (#122).
- Transaction-safe medication creation (#124), bounded reminder delivery with durable uncertain-outcome handling (#123), and accessible navy authentication/OTP flows (#125).
- Non-root API containers, separate migration/index preparation jobs, liveness/readiness and staging/rollback guidance (#126).
- Background reconciliation of existing Photon requests, fenced leases, backoff, and PHI-free operator signals; no automatic resubmission (#127).
- Protected manual signed AAB/IPA workflow, source/provenance and signing checks; no store upload (#128).
- Fail-closed Stripe, RevenueCat, legal/support and Photon readiness validation (#129). Approved prices remain Essentials free, Plus $14.99/month or $149.99/year, Family $24.99/month or $249.99/year; hardware is separate.
- Authenticated encrypted Live Activity token registration and bounded APNs start/update delivery (#130), integrated with the reminder and pharmacy worker lifecycle. APNs acceptance is not device-display evidence.

## Verification

The integrated local backend typecheck passes; 359 tests pass, and 52 PostgreSQL cases are reserved for native-database CI. The full Flutter suite passes 341 tests. Flutter analysis passes with existing informational lints and no errors or warnings. CI additionally runs migrated disposable PostgreSQL, transactional MongoDB, Android debug packaging, an unsigned iOS/Live Activity simulator build, and prototype transitions.

Final PR and post-merge CI results must be checked on their actual commit SHA; local counts do not substitute for those results. Existing rendered fixtures and scoped Figma comparisons are documented in `prototypes/consumer-v2/VISUAL_PARITY.md` and `docs/design/`; neither establishes whole-app pixel identity or physical-device behavior.

## External activation inputs

| Input | What it unlocks |
| --- | --- |
| Intended hosting account, staging API origins and host secret store | Deploy containers, restore/rehearse migrations, configure service URLs, exercise authenticated end-to-end journeys |
| Restricted Stripe runtime key and webhook signing secret | Sandbox checkout, renewals, cancellation and replay/failure verification |
| RevenueCat project plus Apple/Google app/product/entitlement and notification setup | Native sandbox purchase, pending, refund, expiration, restore and account-switch testing |
| Photon organization sandbox credentials and authorized test prescription mapping | Eligible reviewed orders and status reconciliation; a label photo alone is not an electronic prescription |
| Apple signing/APNs inputs and Android signing inputs | Signed archives and remote delivery validation through the protected release workflow |
| Supported phones and physical vial | Native delivery/accessibility and hardware reliability evidence |

Use `BILLING_PROVIDER_ACTIVATION.md`, `NATIVE_BILLING_HANDOFF.md`, `deploy/README.md`, and `farda-app/docs/NATIVE_RELEASE.md` for exact configuration contracts. Secrets belong in the hosting/signing secret store.

## Known software boundaries

Remote Live Activities currently implement starts and due updates. Cross-device terminal `end` pushes after confirmation, cancellation, snooze or window expiry are not implemented; local foreground end handling and server token revocation are implemented. Stale presentation asks users to open the app. Ordinary notification fallback, family background push, broader recurrence rules, and firmware-dependent possession/ACK behavior remain separate features. Do not describe them as working because CI or APNs submission succeeds.

Only an explicit authenticated dose-status action records a dose as taken. Calls, AI output, pharmacy status, Live Activity events and vial movement do not.
