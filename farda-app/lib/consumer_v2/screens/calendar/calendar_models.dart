import 'package:flutter/foundation.dart';

/// Filters available on the consumer calendar.
enum ConsumerCalendarFilter { all, routines, refills }

extension ConsumerCalendarFilterLabel on ConsumerCalendarFilter {
  String get label => switch (this) {
    ConsumerCalendarFilter.all => 'All',
    ConsumerCalendarFilter.routines => 'Routines',
    ConsumerCalendarFilter.refills => 'Refills',
  };
}

/// The kind of item shown in the selected-day agenda.
enum ConsumerCalendarEventType { routine, refill }

/// Calendar record state. Scheduled items remain separate from saved entries;
/// unconfirmed is reserved for a past entry whose outcome remains unknown.
enum ConsumerCalendarEventStatus {
  planned,
  pending,
  snoozed,
  recorded,
  skipped,
  unconfirmed,
}

/// Visual marker represented in the month grid and its legend.
enum ConsumerCalendarMarker {
  recorded,
  skipped,
  snoozed,
  unconfirmed,
  scheduled,
  refill,
}

/// Presentation model for one calendar item.
///
/// The feature intentionally accepts presentation-ready copy. This keeps the
/// screen independent from medication, pharmacy, and persistence services and
/// prevents it from inferring medical state from a reminder or hardware event.
@immutable
class ConsumerCalendarEvent {
  const ConsumerCalendarEvent({
    required this.id,
    required this.date,
    required this.type,
    required this.status,
    required this.eyebrow,
    required this.title,
    required this.description,
    this.routineName,
    this.actionLabel,
  });

  final String id;
  final DateTime date;
  final ConsumerCalendarEventType type;
  final ConsumerCalendarEventStatus status;
  final String eyebrow;
  final String title;
  final String description;

  /// The actual prescription label, separate from its day-specific status.
  final String? routineName;
  final String? actionLabel;

  ConsumerCalendarMarker? get marker {
    if (type == ConsumerCalendarEventType.refill) {
      return ConsumerCalendarMarker.refill;
    }

    return switch (status) {
      ConsumerCalendarEventStatus.recorded => ConsumerCalendarMarker.recorded,
      ConsumerCalendarEventStatus.skipped => ConsumerCalendarMarker.skipped,
      ConsumerCalendarEventStatus.snoozed => ConsumerCalendarMarker.snoozed,
      ConsumerCalendarEventStatus.unconfirmed =>
        ConsumerCalendarMarker.unconfirmed,
      ConsumerCalendarEventStatus.planned ||
      ConsumerCalendarEventStatus.pending => ConsumerCalendarMarker.scheduled,
    };
  }

  bool isVisibleFor(ConsumerCalendarFilter filter) => switch (filter) {
    ConsumerCalendarFilter.all => true,
    ConsumerCalendarFilter.routines =>
      type == ConsumerCalendarEventType.routine,
    ConsumerCalendarFilter.refills => type == ConsumerCalendarEventType.refill,
  };
}

DateTime calendarDay(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime calendarMonth(DateTime value) => DateTime(value.year, value.month);

bool isSameCalendarDay(DateTime first, DateTime second) =>
    first.year == second.year &&
    first.month == second.month &&
    first.day == second.day;
