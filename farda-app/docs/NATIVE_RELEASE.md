# Native release gates

The manual `Native release archives` workflow builds signed Android and iOS
artifacts. It does not upload an artifact to either store. It accepts only a
full commit SHA that is already an ancestor of the repository default branch,
then checks out that same SHA in both build jobs.

Configure a protected GitHub environment named `native-release`. Require the
appropriate reviewer policy for that environment and provide these external
settings. No signing value belongs in the repository.

## Environment variables

| GitHub environment variable | Purpose |
| --- | --- |
| `FARDA_BASE_API_URL` | Non-placeholder production HTTPS main API root |
| `FARDA_VIAL_API_URL` | Non-placeholder production HTTPS vial API root |
| `FARDA_ANDROID_APPLICATION_ID` | Approved Play application ID |
| `FARDA_ANDROID_CERT_SHA256` | SHA-256 fingerprint of the approved Play upload certificate |
| `FARDA_IOS_APP_BUNDLE_ID` | Approved Runner bundle ID |
| `FARDA_IOS_EXTENSION_BUNDLE_ID` | Approved Live Activity extension ID, beneath the app bundle ID |
| `FARDA_IOS_TEAM_ID` | Ten-character Apple developer team ID |
| `FARDA_IOS_APP_PROFILE` | Exact name of the app distribution provisioning profile |
| `FARDA_IOS_EXTENSION_PROFILE` | Exact name of the extension distribution provisioning profile |
| `FARDA_IOS_EXPORT_METHOD` | `app-store-connect`, `ad-hoc`, or `enterprise` |
| `FARDA_IOS_CERT_SHA256` | SHA-256 fingerprint of the Apple distribution certificate present in both profiles |

## Environment secrets

| GitHub environment secret | Purpose |
| --- | --- |
| `FARDA_ANDROID_KEYSTORE_BASE64` | Base64-encoded Play upload keystore |
| `FARDA_ANDROID_KEYSTORE_PASSWORD` | Upload keystore password |
| `FARDA_ANDROID_KEY_ALIAS` | Upload key alias |
| `FARDA_ANDROID_KEY_PASSWORD` | Upload key password |
| `FARDA_IOS_CERTIFICATE_BASE64` | Base64-encoded Apple distribution `.p12` |
| `FARDA_IOS_CERTIFICATE_PASSWORD` | Distribution certificate password |
| `FARDA_IOS_APP_PROFILE_BASE64` | Base64-encoded app distribution profile |
| `FARDA_IOS_EXTENSION_PROFILE_BASE64` | Base64-encoded extension distribution profile |

## Gate behavior

Run the workflow with an exact merged commit, a store version such as `1.2.0`,
an Android version code no greater than `2100000000`, and an Apple bundle
version with one to three numeric components. Store versions contain exactly
three numeric components; prerelease suffixes and ambiguous leading zeroes are
rejected. Android release configuration refuses a
placeholder application ID, missing keystore fields, an invalid commit, or a
build number that differs from Flutter's `versionCode`. The workflow verifies
the AAB JAR signature against the approved certificate fingerprint and checks
the provenance marker embedded in the bundle manifest.

iOS Release builds take bundle IDs, team, and profile names from an
ephemeral ignored `ReleaseSigning.xcconfig`. Release builds fail when those
values, the exact commit, or the build number are absent. Export options are
generated from validated external inputs with manual signing. The Runner
release entitlement requires production APNs, and the selected app profile
must grant it.

Before uploading the artifacts, the workflow verifies both code signatures,
the app and extension bundle IDs, build/version values, exact commit stored in
both Info plists, team/application entitlements, and the app's production APNs
entitlement. It extracts the signing leaf from the P12, exported app, and
exported extension, requires all three SHA-256 fingerprints to match the
approved certificate, and records the measured fingerprints. It records
artifact SHA-256 values in JSON evidence files and
retains the AAB, IPA, signed Xcode archive (including dSYMs), and evidence for
14 days.

All workflow actions are pinned to reviewed commit SHAs. Signing secrets are
available only to the individual keystore import or native build step that
needs them; subsequent verification and artifact upload steps receive no
signing secret environment variables.

The workflow deliberately stops after artifact creation. Store upload,
notarization, phased release, and production deployment remain separate
operator actions.

For local static validation that needs no credentials, run:

```bash
cd farda-app
python3 ios/scripts/validate_live_activity_project.py
python3 ios/scripts/test_configure_release.py
```
