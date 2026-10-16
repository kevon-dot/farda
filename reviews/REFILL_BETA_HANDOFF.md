# Refill and beta handoff

Status checked 2026-10-16 on `codex/membership-family-alerts`. This is a software-readiness record, not evidence of a live pharmacy connection or a signed beta.

## Refill provider

The Photon adapter, review/submit/reconciliation service, trusted-link provisioning command, migration, routes, and mocked contract tests are present. The adapter is disabled by default, uses fixed Neutron sandbox and Photon production endpoints, never retries an uncertain `createOrder`, and requires a server-side patient/prescription/pharmacy mapping. Its request shapes were compared with Photon's official authentication, Clinical API, place-order, and order-event documentation on 2026-10-16.

The focused refill suite passes: 58 tests across provider, orchestration, provisioning, and routes. TypeScript production type-checking also passes. These tests use synthetic provider responses and do not prove partner authorization or sandbox interoperability.

This checkout has no `PHOTON_CLIENT_ID`, `PHOTON_CLIENT_SECRET`, `FARDA_REFILL_PROVIDER_ENABLED`, or `FARDA_REFILL_PROVIDER_ENVIRONMENT` value in its process environment. Therefore no authenticated sandbox read was possible and no order was submitted. Before enabling a sandbox pilot:

1. Obtain Neutron machine-to-machine credentials and confirm the organization may read patients, prescriptions, pharmacies, and orders and may create refill orders.
2. Supply credentials through the deployment secret store, set the provider environment to `sandbox`, and keep provider enablement off during the read-only check.
3. Create an approved synthetic Photon patient, active refillable prescription, pharmacy, and complete address. Record their IDs outside source control.
4. Run `scripts/provision-refill-link.ts` first without `--apply`; compare the returned medication, directions, pharmacy, and address with the fixture. Apply the link only after operator review.
5. Exercise review and status reads. A `createOrder` test requires explicit approval for that fixture because even Neutron mutations may create workflow records. Preserve any `unknown` result for reconciliation; do not repeat it as a new request.

Production remains blocked on Photon production access, compliance and operations approval, a production secret store, verified webhook/reconciliation operations, monitoring, and a real patient/pharmacy pilot. OCR labels and local Rx numbers cannot be converted into Photon prescriptions by this integration.

## Signed beta

Current CI defines two review artifacts. `farda-android-review` contains a debug APK built with demo mode. The newly added `farda-ios-simulator-review` packages the unsigned simulator `Runner.app` as `farda-simulator.zip`. The iOS artifact is pending a successful CI run and has not been generated or installed as part of this handoff. Neither artifact is a signed beta or a physical-device build. There is no signed-release, TestFlight, Play internal-testing, GitHub Release, or external distribution workflow.

After a successful CI run, install the iOS review build on a Mac simulator as follows:

1. Download and expand the `farda-ios-simulator-review` artifact from that exact GitHub Actions run.
2. Start an iOS Simulator and confirm it is booted with `xcrun simctl list devices booted`.
3. In the expanded artifact directory, unpack the app with `ditto -x -k farda-simulator.zip .`.
4. Install it with `xcrun simctl install booted Runner.app`, then launch it from the simulator. This cannot be installed on an iPhone and provides no signing, APNs, or physical-device evidence.

The Android review artifact is separate: download and expand `farda-android-review` from a successful run, enable USB debugging on a review device or start an Android emulator, and install its `app-debug.apk` with `adb install -r app-debug.apk`. The APK uses the CI demo build flag and debug signing. Do not upload it to a store or describe it as a production, signed-beta, or live-backend build.

The current process environment contains none of the Android signing variables documented by the Gradle build and no App Store Connect key, iOS certificate, or provisioning-profile variables. Android release builds already fail closed when the approved application ID or keystore inputs are missing. iOS still uses `com.example.farda` identifiers for Runner, tests, and the Live Activity extension and has no recorded development team or export configuration.

To produce a reviewable signed beta, the release owner must provide:

- approved Android application ID, upload keystore and passwords, Play Console application/internal-testing access, and the beta API configuration;
- Apple team, final Runner and Live Activity bundle IDs, matching distribution certificate and profiles, App Store Connect API access, production APNs setup, and an export options policy;
- a protected release environment and explicit workflow trigger that builds signed AAB/IPA artifacts, verifies certificate/profile/bundle identifiers and entitlements, uploads to the selected beta channels, and records commit SHA and build numbers;
- physical-device smoke evidence for authentication, Today/Calendar/Refills, offline and duplicate actions, permission denial, account switching, Live Activities, and the approved synthetic pharmacy flow.

Until those inputs and device results exist, the software can be described as CI-tested review software. It cannot be described as a signed beta or a live pharmacy integration.
