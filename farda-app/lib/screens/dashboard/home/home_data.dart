import 'package:farda/application/calender/model/dose_time_model.dart';

/// Pure-Dart data mapping for the Home screen.
///
/// These helpers turn the raw provider data (currently
/// [CalenderProvider.doseTimeModel]) into the view-model shapes the Home UI
/// needs: dose cards, the pill-progress counts, and the chart series. They are
/// deliberately free of Flutter/widget/plugin imports so they can be unit
/// tested under `flutter test` without platform channels.
///
/// Home used to hard-code "Terry Roberts", the pill counts (480/740/1000/1220),
/// two fabricated dose cards, and a fake 4-point chart curve. None of that real
/// data exists yet beyond the configured dose windows, so the rule here is:
/// derive what we honestly can from real data and otherwise expose an empty
/// state the UI renders as a "No data yet" placeholder — never a fabricated
/// value.

/// A single dose window ready for display on Home.
class HomeDose {
  /// The configured name of the dose window, e.g. "First dose".
  final String name;

  /// The dose window start, formatted for display (e.g. "8:00 AM").
  /// Empty when the source time was missing or unparseable.
  final String time;

  const HomeDose({required this.name, required this.time});
}

/// Formats a `HH:mm:ss` (or `HH:mm`) 24-hour time string into a friendly
/// 12-hour clock like "8:00 AM". Returns an empty string when [raw] is null,
/// blank, or not parseable, so callers can fall back to a placeholder rather
/// than crash on bad data.
String formatDoseTime(String? raw) {
  if (raw == null) return '';
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';

  final parts = trimmed.split(':');
  if (parts.length < 2) return '';

  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return '';
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return '';

  final period = hour < 12 ? 'AM' : 'PM';
  var displayHour = hour % 12;
  if (displayHour == 0) displayHour = 12;
  final mm = minute.toString().padLeft(2, '0');
  return '$displayHour:$mm $period';
}

/// Maps the provider's configured dose windows into displayable [HomeDose]s,
/// sorted by start time. Entries with no usable name are skipped. Returns an
/// empty list when there are no dose windows, which the UI renders as an empty
/// state instead of fabricated "First/Second dose" cards.
List<HomeDose> dosesFromCalender(List<DoseTimeModel> doses) {
  final mapped = <_SortableDose>[];
  for (final d in doses) {
    final name = (d.name ?? '').trim();
    if (name.isEmpty) continue;
    mapped.add(
      _SortableDose(
        sortKey: _minutesOfDay(d.startTime),
        dose: HomeDose(name: name, time: formatDoseTime(d.startTime)),
      ),
    );
  }
  mapped.sort((a, b) => a.sortKey.compareTo(b.sortKey));
  return mapped.map((e) => e.dose).toList();
}

/// Real pill-progress counts for Home.
///
/// There is no real consumed/remaining/target pill telemetry from the backend
/// yet (the old 480/740/1000/1220 were invented), so every count is honestly
/// zero until such a feed exists. [hasData] reports whether any real figure is
/// available, letting the UI distinguish "no data" from a genuine all-zero day.
class PillCounts {
  final int remaining;
  final int consumed;
  final int target;

  const PillCounts({
    required this.remaining,
    required this.consumed,
    required this.target,
  });

  /// The honest empty state: no pill telemetry available.
  static const PillCounts empty =
      PillCounts(remaining: 0, consumed: 0, target: 0);

  /// True once any real, non-zero figure is present.
  bool get hasData => remaining != 0 || consumed != 0 || target != 0;
}

/// Derives the pill-progress counts from the available provider data.
///
/// No real pill-count series exists yet, so this returns [PillCounts.empty]
/// (all zeros). It is kept as a seam so a future real feed can populate it
/// without the UI hard-coding numbers again.
PillCounts pillCountsFromCalender(List<DoseTimeModel> doses) {
  return PillCounts.empty;
}

/// Builds the adherence-over-time series for the Insights chart.
///
/// There is no real adherence-history series in the providers yet, so this
/// always returns an empty list. The chart treats an empty series as the
/// "No data yet" placeholder and must never invent a curve. Kept as a pure
/// seam so a real series can be plugged in here later.
List<double> adherenceSeriesFromCalender(List<DoseTimeModel> doses) {
  return const <double>[];
}

class _SortableDose {
  final int sortKey;
  final HomeDose dose;
  const _SortableDose({required this.sortKey, required this.dose});
}

/// Minutes-since-midnight for a `HH:mm[:ss]` string; unparseable/missing times
/// sort last.
int _minutesOfDay(String? raw) {
  if (raw == null) return 1 << 30;
  final parts = raw.trim().split(':');
  if (parts.length < 2) return 1 << 30;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return 1 << 30;
  return h * 60 + m;
}
