import 'package:flutter/foundation.dart';

/// Filters available on the consumer calendar.
enum ConsumerCalendarFilter {
  all,
  routines,
  refills,
}

extension ConsumerCalendarFilterLabel on ConsumerCalendarFilter {
  String get label => switch (this) {
        ConsumerCalendarFilter.all => 'All',
        ConsumerCalendarFilter.routines => 'Routines',
        ConsumerCalendarFilter.refills => 'Refills',
      };
}

/// The kind of item shown in the selected-day agenda.
enum ConsumerCalendarEventType {
  routine,
  refill,
}

/// Calendar record state. Planned and pending events have no date marker;
/// unconfirmed is reserved for a past entry whose outcome remains unknown.
enum ConsumerCalendarEventStatus {
  planned,
  pending,
  recorded,
  unconfirmed,
}

/// Visual marker represented in the month grid and its legend.
enum ConsumerCalendarMarker {
  recorded,
  unconfirmed,
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
    this.actionLabel,
  });

  final String id;
  final DateTime date;
  final ConsumerCalendarEventType type;
  final ConsumerCalendarEventStatus status;
  final String eyebrow;
  final String title;
  final String description;
  final String? actionLabel;

  ConsumerCalendarMarker? get marker {
    if (type == ConsumerCalendarEventType.refill) {
      return ConsumerCalendarMarker.refill;
    }

    return switch (status) {
      ConsumerCalendarEventStatus.recorded =>
        ConsumerCalendarMarker.recorded,
      ConsumerCalendarEventStatus.unconfirmed =>
        ConsumerCalendarMarker.unconfirmed,
      ConsumerCalendarEventStatus.planned ||
      ConsumerCalendarEventStatus.pending => null,
    };
  }

  bool isVisibleFor(ConsumerCalendarFilter filter) => switch (filter) {
        ConsumerCalendarFilter.all => true,
        ConsumerCalendarFilter.routines =>
          type == ConsumerCalendarEventType.routine,
        ConsumerCalendarFilter.refills =>
          type == ConsumerCalendarEventType.refill,
      };
}

DateTime calendarDay(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime calendarMonth(DateTime value) => DateTime(value.year, value.month);

bool isSameCalendarDay(DateTime first, DateTime second) =>
    first.year == second.year &&
    first.month == second.month &&
    first.day == second.day;
