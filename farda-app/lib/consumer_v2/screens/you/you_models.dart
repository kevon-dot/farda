import 'package:flutter/foundation.dart';

/// Screens that make up the self-contained consumer-v2 "You" experience.
///
/// These are presentation destinations, not application routes. The feature
/// keeps navigation local until the app shell is ready to wire real routes.
enum FardaYouDestination {
  overview,
  routine,
  reminders,
  vial,
  circle,
  liveActivity,
  callPreview,
}

enum FardaLivePreviewState {
  before,
  due,
  snoozed,
  stale,
  confirmed,
  off,
}

enum FardaCallPreviewStage {
  ringing,
  answered,
  checkIn,
  confirm,
  ended,
}

/// Stable keys for feature-level navigation and interaction tests.
abstract final class FardaYouKeys {
  static const routineLink = Key('you_routine_link');
  static const remindersLink = Key('you_reminders_link');
  static const vialLink = Key('you_vial_link');
  static const circleLink = Key('you_circle_link');
  static const liveActivityLink = Key('you_live_activity_link');
  static const callPreviewLink = Key('you_call_preview_link');
  static const companionToggle = Key('you_companion_toggle');
  static const privacyToggle = Key('you_privacy_toggle');
  static const callToggle = Key('you_call_toggle');
  static const liveActivityToggle = Key('you_live_activity_toggle');
  static const confirmSampleEntry = Key('you_confirm_sample_entry');
}
