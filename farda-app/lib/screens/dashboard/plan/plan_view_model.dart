import 'package:farda/application/calender/model/dose_time_model.dart';

/// A single, display-ready entry in the user's dose schedule / adherence plan.
///
/// Pure value type derived from real provider data (dose times +
/// prescription medicines) so it can be unit-tested without widgets, plugins
/// or platform channels.
class PlanScheduleItem {
  /// Label for the dose window (e.g. "Morning").
  final String name;

  /// Start time as a normalised "HH:mm" string (24-hour). Empty when unknown.
  final String time;

  /// Minutes past midnight for the start time, used purely for ordering.
  /// `-1` when the start time is missing/unparseable so such entries sort last.
  final int minutesOfDay;

  /// The medicine taken in this window, when a prescription is available.
  final String? medicineName;

  const PlanScheduleItem({
    required this.name,
    required this.time,
    required this.minutesOfDay,
    this.medicineName,
  });
}

/// Derives the user's daily dose plan from the (otherwise UI-bound) provider
/// models. Kept free of Flutter imports so it is cheap to test in CI.
class PlanViewModel {
  /// Builds an ordered schedule from the raw dose-time models.
  ///
  /// - Entries are sorted by start time (earliest first).
  /// - Entries with a missing/blank name are dropped.
  /// - [medicineName] (the medicine the user is adhering to, typically the
  ///   first medicine of their active prescription) is attached to every dose
  ///   window when provided.
  static List<PlanScheduleItem> scheduleFromDoses(
    List<DoseTimeModel> doses, {
    String? medicineName,
  }) {
    final med = (medicineName ?? '').trim();
    final attachedMedicine = med.isEmpty ? null : med;

    final items = <PlanScheduleItem>[];
    for (final dose in doses) {
      final name = (dose.name ?? '').trim();
      if (name.isEmpty) continue;

      final normalised = normaliseTime(dose.startTime);
      items.add(
        PlanScheduleItem(
          name: name,
          time: normalised,
          minutesOfDay: minutesOfDay(dose.startTime),
          medicineName: attachedMedicine,
        ),
      );
    }

    items.sort((a, b) {
      // Unknown times (-1) sort to the bottom; otherwise by time of day, then
      // by name for a stable, predictable order.
      final am = a.minutesOfDay == -1 ? 1 << 30 : a.minutesOfDay;
      final bm = b.minutesOfDay == -1 ? 1 << 30 : b.minutesOfDay;
      final byTime = am.compareTo(bm);
      return byTime != 0 ? byTime : a.name.compareTo(b.name);
    });

    return items;
  }

  /// `true` when there is nothing to show (no scheduled dose windows).
  static bool isEmpty(List<DoseTimeModel> doses) =>
      scheduleFromDoses(doses).isEmpty;

  /// Converts a backend time string ("HH:mm:ss" or "HH:mm") to "HH:mm".
  /// Returns an empty string when the input is null/blank/unparseable.
  static String normaliseTime(String? raw) {
    final mins = minutesOfDay(raw);
    if (mins < 0) return '';
    final h = (mins ~/ 60).toString().padLeft(2, '0');
    final m = (mins % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// Minutes past midnight for a "HH:mm[:ss]" string, or `-1` when invalid.
  static int minutesOfDay(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return -1;
    final parts = value.split(':');
    if (parts.length < 2) return -1;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return -1;
    if (h < 0 || h > 23 || m < 0 || m > 59) return -1;
    return h * 60 + m;
  }
}
