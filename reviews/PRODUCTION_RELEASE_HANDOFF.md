# Farda production release handoff

Updated October 15, 2026 against the repository default branch at `5d8f763530d3d5e0af2482e964c2ddc2866611a2`. This is a release procedure and evidence ledger, not a record of a production deployment.

## Current evidence

- PRs [#104](https://github.com/kevon-dot/farda/pull/104), [#105](https://github.com/kevon-dot/farda/pull/105), [#107](https://github.com/kevon-dot/farda/pull/107), [#108](https://github.com/kevon-dot/farda/pull/108), and [#109](https://github.com/kevon-dot/farda/pull/109) are merged into the repository default branch, `claude/enterprise-code-review-s359w1`. `main` has not received these consumer merges. Confirm the intended release source before promotion.
- [#109 exact-head CI run 38808953437](https://github.com/kevon-dot/farda/actions/runs/38808953437) passed all five jobs before merge. Recheck postmerge CI for `5d8f763530d3d5e0af2482e964c2ddc2866611a2` before selecting a release commit. CI uses disposable PostgreSQL and MongoDB, a debug review APK, and an unsigned iOS simulator build. It does not prove deployment or signed device builds.
- The manual `.github/workflows/native-release.yml` workflow now builds and verifies signed AAB/IPA archives only after protected external signing inputs are configured. It does not upload to either store. No production URL, host, database instance, signing team, or store account is recorded in this repository.
- The default branch's Figma-matched `/consumer/v2` four-tab experience reads authenticated Today, Calendar, Refills, and You data. Saved sessions and OTP completion route to `/consumer/v2/today`; the four tabs include direct refill progress and quiet-hours controls. `/dashboard` still exposes established account tools. Validate the merged routes and account flows on a signed device before a pilot. Native Circle and some previews remain outside authenticated release scope.

## Release decisions and evidence to record

| Gate | Required input and evidence | State on October 15 |
| --- | --- | --- |
| Source and target | Approved release commit, target branch, deployment platform, production and staging URLs, accountable operator | Unknown; GitHub default and `main` differ |
| PostgreSQL | Verified point-in-time backup and restore into an isolated staging database; migration log, before/after checks and rollback procedure | CI only uses an empty disposable database |
| MongoDB | Verified snapshot and isolated restore; index/startup validation, ownership and event history spot checks | CI only uses a disposable replica set |
| Providers | Production Twilio Verify, optional consented Voice, OpenAI OCR, HTTPS callback origin and APNs credentials/configuration verified in staging | Placeholder configuration; worker and voice disabled by default |
| Mobile signing | Approved Android application ID, upload key and certificate fingerprint; Apple team, app/extension bundle IDs, profiles and APNs entitlement; signed archive metadata | Android build used debug signing; iOS build was unsigned simulator |
| Device acceptance | Signed builds on supported iPhone/Android devices; OTP, routine persistence, offline/retry, notification and Live Activity lifecycle, BLE/physical vial, accessibility evidence | No real-device evidence in repository |
| Live verification | Release SHA, deployment ID and environment URL; authenticated end-to-end smoke results, logs/metrics and rollback owner | No deployment record or production URL |

## Database backup and migration rehearsal

1. Identify the actual PostgreSQL and MongoDB environments and their backup owners. Capture current schema/migration state, database versions, sizes, and a backup timestamp. Do not put connection strings or snapshots in GitHub artifacts.
2. Take a consistent PostgreSQL backup and MongoDB snapshot using the provider's supported point-in-time mechanism. Restore **both** into isolated, access-restricted rehearsal databases. Demonstrate a read of representative users, prescriptions, doses, sessions, devices, and observations from the restores. Record the restore duration and checksums or provider snapshot IDs privately.
3. Run `pnpm install --frozen-lockfile --ignore-scripts` and `pnpm exec prisma generate` in `farda-app-backend`. Set `DATABASE_URL` to the **rehearsal** PostgreSQL URL and run `pnpm exec prisma migrate status`, then `pnpm exec prisma migrate deploy`. Do not use `prisma db push` or reset on an existing database.
4. Compare pre/post row counts and sampled relationships. In particular, inspect the `Prescription_userId_key` drop, any pre-existing `Dose` table, legacy `takenAt` values (they must remain unverified), schedule versions, reminder intents, consent, and refill/inventory tables. Re-run `prisma migrate status` and the authenticated API smoke tests against rehearsal only.
5. Point a staging vial API at the restored MongoDB replica set and the same restored PostgreSQL identity store. Confirm startup/index creation, existing owner and epoch data, session revocation, duplicate event receipts, and former-owner history. Existing ambiguous observations must stay quarantined; never infer their owner from current device ownership.
6. Rehearse rollback by restoring into a **new** isolated database and switching a staging service to it. Record the downtime, data-loss window, and cutover/rollback decision. Only then schedule the production migration with a fresh verified backup and a named operator.

## Provider and mobile configuration

- Keep `.env` files and credentials in the deployment secret store. Main API requires a production `DATABASE_URL`, HTTPS `BETTER_AUTH_URL`, and a secret of at least 32 characters. The vial API requires a transactional MongoDB replica set, the **same** PostgreSQL identity database, and explicit `CORS_ORIGINS`. Set the Flutter `BASE_API_URL` and `VIAL_API_URL` to the intended HTTPS `/api` roots. Verify sign-in through both APIs and never bundle server secrets in Flutter assets.
- Configure Twilio Verify for real OTP delivery and OpenAI for OCR in staging. A successful OCR extraction still requires human label review. Voice calls additionally require explicit consent, a verified number, `FARDA_TWILIO_VOICE_FROM`, signed callback validation and approved operating policy. Keep `FARDA_REMINDER_WORKER_ENABLED=false` and `FARDA_VOICE_ENABLED=false` until those checks and monitoring are complete. See `farda-app-backend/src/reminders/README.md`.
- Set a real Android application ID and the signing environment variables documented below in an isolated signing runner. Verify the release bundle's signing certificate fingerprint against the approved Play Console upload certificate. Never use the debug APK from CI as a release artifact.
- Set real iOS Runner and Live Activity extension bundle IDs, Apple team/profiles and production APNs entitlement. Archive and export a signed device build; inspect embedded extension signing and entitlements. Remote Live Activity delivery requires server APNs key/topic and authenticated token registration, which are not implemented by the native bridge alone. See `farda-app/ios/LIVE_ACTIVITIES.md`.

Android release builds require `FARDA_ANDROID_APPLICATION_ID`, `FARDA_ANDROID_KEYSTORE_PATH`, `FARDA_ANDROID_KEYSTORE_PASSWORD`, `FARDA_ANDROID_KEY_ALIAS`, `FARDA_ANDROID_KEY_PASSWORD`, `FARDA_RELEASE_COMMIT`, and `FARDA_BUILD_NUMBER`. The keystore path must name a readable file, the commit must be an exact lowercase SHA, and the positive build number must match Flutter's version code without exceeding Play's `2100000000` limit. The iOS workflow uses a separately validated Apple bundle version. Supply the approved HTTPS API roots through the app's configuration; do not copy the committed placeholder `.env.example` into a store build. The release Gradle configuration refuses placeholder IDs or missing/mismatched inputs. See [`farda-app/docs/NATIVE_RELEASE.md`](../farda-app/docs/NATIVE_RELEASE.md) for the protected workflow inputs and artifact verification gates.

## Real-device acceptance and go-live proof

On signed builds, record device/OS versions and pass/fail evidence for login/session revocation, a manual routine across Today and Calendar, explicit taken/skip/correction, snooze and quiet hours, refill receipt/count reconciliation, offline and duplicate writes, timezone/DST, permission denial, and account switching. For calls, confirm one consented attempt and cancellation on confirmation/opt-out; answering never marks a dose taken. For iPhone, verify lock-screen Live Activities while suspended, stale/ended state and token rotation. For the vial, use physical hardware to test pairing, calibration, power loss, transfer and immutable event receipts. Record accessibility checks on small and large screens.

After deployment, capture the environment URL, deployment ID, SHA, migration IDs, signed app versions, smoke-test timestamps, and monitoring/rollback owner. Verify the actual live URL and authenticated flows before calling it production. If the intended release is a mobile pilot, state the enrolled distribution channel and physical-device installation evidence instead of treating a GitHub merge as a release.
