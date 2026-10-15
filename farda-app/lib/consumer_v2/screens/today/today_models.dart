import 'package:flutter/foundation.dart';

/// The user's explicit record for a single routine occurrence.
///
/// Reminder delivery and vial movement intentionally do not appear here. They
/// are observations, not confirmation that a dose was taken.
enum TodayDoseStatus { pending, confirmed, skipped }

enum TodayReminderMilestoneType { liveActivity, routineDue, callReminder }

@immutable
class TodayReminderMilestone {
  const TodayReminderMilestone({
    required this.type,
    required this.timeLabel,
    required this.label,
    required this.accessibilityHint,
  });

  final TodayReminderMilestoneType type;
  final String timeLabel;
  final String label;
  final String accessibilityHint;
}

@immutable
class TodayDoseSnapshot {
  const TodayDoseSnapshot({required this.status, required this.isSnoozed});

  final TodayDoseStatus status;
  final bool isSnoozed;
}
