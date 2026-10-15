# Farda native Live Activities

Implemented from Figma `BeSPZ5VOwOOlrwKFTpMA4K`, active screen `2:38`, on 2026-10-15. The app keeps its Flutter UI; `FardaLiveActivity` is a real SwiftUI/WidgetKit app extension embedded by Runner.

## What is included

- Private Lock Screen and compact, expanded, minimal Dynamic Island presentations.
- Heads-up at −10 minutes, due, snoozed, confirmed, cancelled and stale content.
- Outfit fonts, navy/cream tokens with dark variants, and the exact lock/arrow vector source used by the committed Figma construction script.
- ActivityKit start/update/end, revision ordering, duplicate reconciliation, permission state, foreground-start guard and restart observation.
- Rotating per-activity tokens and iOS 17.2+ push-to-start tokens exposed through the Dart event stream. No tokens are logged or sent to an endpoint by this bridge.
- Deep links that open the matching authenticated occurrence. Neither a link, a call, a device observation nor an ActivityKit event records ingestion.

The Figma Lock Screen card was approximately 330 points tall. Apple documents possible truncation above 160 points, so the native version compresses the same hierarchy and actions into a compact layout with 44-point links. System wallpaper, clock, status bar and phone-call UI belong to iOS. The native layout still needs simulator and physical-device review, including large text and Always-On display.

## Flutter integration

`LiveActivityService` owns `farda/live_activity` and `farda/live_activity_events`. `ConsumerLiveActivityCoordinator` provides foreground boundary timing and reconciliation without depending on consumer model classes.

```dart
final coordinator = ConsumerLiveActivityCoordinator(
  service: LiveActivityService(),
  onOpenRoutine: (id, action) async {
    // Fetch id under the signed-in account; navigate to explicit confirmation
    // or snooze selection. Never execute a record mutation from this callback.
  },
  onError: (_) { /* Keep manual routine UI available. */ },
)..attach();

await coordinator.reconcile(
  occurrences: unresolvedOccurrences.map((record) => LiveRoutineActivity(
    occurrenceId: record.id,
    dueAt: record.scheduledFor,
    windowEndsAt: record.windowEndsAt,
    updatedAt: record.updatedAt,
    revision: record.revision,
    phase: LiveRoutinePhase.due, // Recomputed from the clock by coordinator.
    callAt: record.callAt,
    snoozedUntil: record.snoozedUntil,
  )),
  enabled: preferences.liveActivitiesEnabled,
);
// After an explicit, accepted user confirmation:
await coordinator.resolve(id,
  outcome: LiveRoutineOutcome.confirmed, revision: acceptedRevision);
// On account logout, end the native surfaces and revoke server tokens.
await coordinator.signOut();
await coordinator.dispose();
```

Supply the complete unresolved snapshot for the current account only after a successful fetch. A fetch error must not masquerade as an empty snapshot. The coordinator ends orphaned activities, so a partial page is not a safe input. Future occurrences may be present; only those between `scheduledFor − 10 minutes` and `windowEndsAt` are shown. The current product window is one hour after the routine time; it is a reminder duration, not prescription guidance.

The bridge returns `supported:false` on non-iOS and iOS below 16.2. Permission denial returns `enabled:false`. These cases must leave ordinary reminders and manual entry available. A user-dismissed or resolved occurrence is not recreated for 48 hours; it has its own persistent suppression marker. A new occurrence uses a different ID. Turning reminders off ends active surfaces; re-enabling during that same occurrence does not resurrect the dismissed surface.

## Native channel contract

| Method/event | Shape |
| --- | --- |
| `availability` | `{supported, enabled, supportsPushToStart, backgroundDeliveryConfigured:false}` |
| `upsert` | `{occurrenceId, dueAt, windowEndsAt, updatedAt, revision, phase, callAt?, snoozedUntil?, requestPushToken:false}` |
| `end` | `{occurrenceId, outcome:confirmed\|cancelled, revision}` |
| `endAll` | End all local activities, including on logout |
| `activeActivities` | `[{activityId, occurrenceId, state, revision, phase}]` |
| `consumePendingOpen` | Optional cold-start `openRoutine` event; stream subscription normally flushes it |
| `openRoutine` | `{type, occurrenceId, action:view\|checkIn\|snooze}` |
| `pushToken` | `{type, activityId, occurrenceId, token}`; replace prior token for that activity |
| `pushToStartToken` | `{type, token}`; replace prior token for that installation |
| `lifecycle` | `{type, activityId, occurrenceId, state, revision, phase}` |
| `authorization` | `{type, enabled}` |

Channel timestamps are Unix **milliseconds**. Native `ContentState` and APNs `content-state` timestamps are Unix **seconds**, using numeric values rather than a custom `Date` encoder. Static attributes contain only `occurrenceId`; the APNs `attributes-type` is `FardaRoutineAttributes`. The shared content fields are `phase`, `revision`, `dueAt`, `windowEndsAt`, `updatedAt`, optional `callAt` and `snoozedUntil`.

## Background delivery and provisioning

The foreground coordinator is not a background scheduler. Without an APNs sender and token-registration adapter, the app cannot promise a Live Activity appears at −10 minutes while suspended. A countdown can continue, but changing heads-up into due requires a native update or APNs; the heads-up becomes stale at the due boundary if it receives neither. Snoozed content becomes stale at its resume boundary. Stale copy asks the user to open Farda rather than claiming an up-to-date status.

For app-initiated starts this implementation uses the iOS 16.2 ActivityContent APIs. Background push-to-start uses the observed iOS 17.2+ token. Older supported devices can receive per-activity updates after an activity has been started from the app. Later scheduling APIs are not used here.

Before enabling remote delivery:

1. Set real Runner and extension bundle identifiers with a shared prefix and select the same signing team. The repository still uses `com.example.farda` and `com.example.farda.LiveActivity`.
2. Enable Push Notifications for the Runner App ID, regenerate provisioning profiles, and add the correctly signed `aps-environment` entitlement for development or production. Local Live Activities do not require adding a fabricated ActivityKit entitlement.
3. Configure server APNs key ID, team ID, private key, environment, and topic `<Runner bundle ID>.push-type.liveactivity`. Keep keys server-side.
4. Authenticated registration binds an installation's current push-to-start token, and each activity token, to the owning user and consent. Rotate/invalidate prior tokens; revoke on logout, opt-out, end or APNs token rejection.
5. Set `requestPushToken:true` only after that path is configured. Enable remote start/update capability in both server capability responses and app configuration after end-to-end validation; the native availability response is deliberately false in this base implementation.
6. Durable workers recheck occurrence status, schedule version, consent, expiry and snooze immediately before delivery. End notifications must cancel a displayed reminder after confirmation. Never retry an ambiguous remote start as if no activity was created.

Exact APNs delivery is not guaranteed. Do not infer that a dose was taken, that a call was answered, or that an activity was seen from an accepted push. Ordinary notification fallback is a separate integration and is not implemented by this extension.

## Verification

Linux checks:

```sh
python ios/scripts/validate_live_activity_project.py
flutter test test/live_activity_service_test.dart
dart analyze lib/services/live_activity_service.dart lib/services/consumer_live_activity_coordinator.dart test/live_activity_service_test.dart
```

The project validator checks OpenStep syntax, object references, target dependency/embedding, source and resource membership, deployment targets, plists, fonts and vector files. It is not a Swift compiler. Flutter tests cover private payloads, time boundaries, snooze, unsupported/denied states, explicit endings, foreground transitions, orphan cleanup and an update/confirmation race.

Initial verification result: project validation passed and targeted Dart analysis reported no issues. The Flutter test shell segfaulted while loading the suite in this container, including a retry under the shared SDK lock; no test cases executed in that attempt. The four RunnerTests require the macOS gate below. Do not treat either suite as passed until it runs successfully in a supported environment.

Required macOS/device gate: `flutter build ios --no-codesign` with Xcode 15.2+ (or the supported Xcode required by the selected Flutter version), then RunnerTests on iOS 16.2+ and physical-device checks for enabled/denied permissions, cold-start links, screen lock, suspended/killed app, stale updates, push token rotation, terminal cancellation, two simultaneous routines, large text, dark mode and Dynamic Island/without-Island devices. Xcode and ActivityKit runtime tests could not be run in this Linux workspace.

## Sources

- [Apple: displaying live data with Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities) — lifecycle, permissions, stale content and size constraints.
- [Apple: ActivityKit push notifications](https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications) — token updates, push-to-start and APNs payloads.
- [Apple: Dynamic Island](https://developer.apple.com/documentation/widgetkit/dynamicisland) — native regions and app deep links.
- [Apple: adding custom fonts](https://developer.apple.com/documentation/uikit/adding-a-custom-font-to-your-app) — bundled Outfit resources.

Figma's temporary asset download endpoint returned a network gateway error in this environment. The lock/arrow files were reproduced byte-for-byte in geometry from the already committed source used to create those exact Figma vectors (`prototypes/consumer-v2/figma-ui-helpers.js`); only the root size follows the 14-point native slot and the fill is template-tinted. No screenshot is used as UI.
