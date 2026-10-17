# Prescription capture polish

Build-stage update, October 17, 2026. Branch: `codex/prescription-capture-polish`.

## Changed behavior

- The dedicated camera flow now explains corrective actions for blur (steady and pause), glare (tilt away from the light), and distance (move back until text is sharp). The framing outline explicitly makes no automated quality claim. Existing four-view overlap guidance, full-image capture, retake/zoom, and manual fallback remain.
- Capture explains that photo extraction and saving need a connection. Manual entry stays available without a camera or extraction request; this is an in-memory draft, not a persisted offline queue.
- Scanned entry names required fields that remain blank, announces the notice to assistive technology, and updates the notice as the user types. Missing directions stay blank and block continuation. Complete scan results still require human checking and final confirmation. No medication instructions or reminder times are inferred.
- Label text fields disable keyboard autocorrection and suggestions to avoid silently changing medication names or directions.
- Duplicate scan taps are disabled. Late photo/extraction results cannot restore an expired or abandoned capture. Observed account-session expiry clears capture photos and unsaved prescription fields and presents a close/sign-in-again state. Reminder picker completions cannot restore values after that expiry.
- Existing retry idempotency and explicit review-before-save behavior are retained.

## Editable Figma

File: https://www.figma.com/design/BeSPZ5VOwOOlrwKFTpMA4K

New section: `172:1268`, **14 · Prescription capture — clarity & session safety**, positioned at x=4700, y=2600 below the refill section. Existing screens were left intact.

| Frame | Node |
| --- | --- |
| Capture 01 · Introduction & connection guidance | `172:1269` |
| Capture 02 · Long-label camera & quality help | `172:1288` |
| Capture 03 · Missing directions — manual confirmation | `172:1308` |
| Capture 04 · Session ended — draft cleared | `172:1329` |

The section contains 38 native editable text layers and seven existing button instances. It reuses Outfit, existing semantic variables, prescription layouts, and the navy/mint brand. Camera content is illustrative. Figma composition and post-fix screenshots were inspected; text fits and controls do not overlap. Native Flutter and Figma spacing is not a pixel-identical claim. All created and subsequently updated node IDs are in `prescription-capture-figma-nodes.json`.

## Verification

- All 14 focused prescription/capture tests passed. They cover intact long directions, missing OCR fields, confirmation, retries, duplicate scan prevention, late asynchronous results, session expiry, and manual fallback during extraction.
- All four screenshot tests passed. They render at 390 px and 320 px with 1.3× text, export camera guidance/fallback, missing directions and session-ended states, and refresh the capture introduction/review evidence. Narrow-screen renders were visually inspected.
- Final full Flutter suite: **308 passed**. Focused analyzer: **no issues** in the five edited Dart files. Full analyzer: **51 pre-existing info-level findings** outside changed files, with no error/warning findings. `git diff --check` passed. A capture-test scroll helper now waits for scrolling to settle before tapping, which fixed a timing failure introduced by the taller connection guidance.

Run from `farda-app` with the Flutter SDK configured and ignored `.env.*` files populated from `.env.example`:

```sh
flutter test --no-pub
flutter analyze --no-pub
flutter test --no-pub --update-goldens --dart-define=UPDATE_VISUALS=true \
  test/visual_qa/capture_polish_screenshots_test.dart \
  test/visual_qa/label_capture_screenshots_test.dart
```

The screenshot tests require `FLUTTER_ROOT` for the bundled Material Icons font.

## External gates

Physical iOS/Android camera permission/lifecycle behavior, actual blur/glare/focus and long curved labels, real OCR accuracy, configured authenticated API connectivity, provider/image retention policy, and signed release validation still require device/service evidence. This change does not implement automatic blur/glare scoring, persist an offline draft, or claim a production deployment.

## Account-switch follow-up

Both onboarding and capture now bind their lifetime to the opening `AuthStorage.sessionRevision`, in addition to observing expiry. An A→B account change irreversibly clears A's draft/photos and increments the operation generation even if the same `ConsumerController` subsequently loads B successfully and reports `sessionExpired == false`.

Two integration regressions type A's name/directions, start real capture extraction, advance the auth revision, successfully reload the same controller, and resolve OCR with either a late success or `sessionChanged` error. They verify blanked text controllers, cleared photos, no restored draft, no save control, and no writes after closing capture. The follow-up's 16 focused tests pass and focused analysis is clean; the 308-test full-suite result above predates these two added regressions.
