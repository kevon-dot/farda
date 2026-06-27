// Pure-Dart unit tests for the Home screen data mapping (home_data.dart).
// These import only model + pure-mapping files (no widgets, plugins, or
// platform channels) so they run fast and reliably under `flutter test`.

import 'package:flutter_test/flutter_test.dart';

import 'package:farda/application/calender/model/dose_time_model.dart';
import 'package:farda/screens/dashboard/home/home_data.dart';

DoseTimeModel _dose({String? name, String? start, String? end}) =>
    DoseTimeModel(name: name, startTime: start, endTime: end);

void main() {
  group('formatDoseTime', () {
    test('formats morning HH:mm:ss as 12-hour AM', () {
      expect(formatDoseTime('08:00:00'), '8:00 AM');
    });

    test('formats afternoon as PM', () {
      expect(formatDoseTime('14:30:00'), '2:30 PM');
    });

    test('handles midnight and noon edge cases', () {
      expect(formatDoseTime('00:00:00'), '12:00 AM');
      expect(formatDoseTime('12:00:00'), '12:00 PM');
    });

    test('accepts HH:mm without seconds', () {
      expect(formatDoseTime('09:05'), '9:05 AM');
    });

    test('returns empty string for null/blank/garbage', () {
      expect(formatDoseTime(null), '');
      expect(formatDoseTime('   '), '');
      expect(formatDoseTime('not-a-time'), '');
      expect(formatDoseTime('99:99:99'), '');
    });
  });

  group('dosesFromCalender', () {
    test('maps real dose windows, sorted by start time', () {
      final doses = dosesFromCalender([
        _dose(name: 'Evening dose', start: '20:00:00', end: '21:00:00'),
        _dose(name: 'Morning dose', start: '08:00:00', end: '09:00:00'),
      ]);

      expect(doses.length, 2);
      expect(doses.first.name, 'Morning dose');
      expect(doses.first.time, '8:00 AM');
      expect(doses.last.name, 'Evening dose');
      expect(doses.last.time, '8:00 PM');
    });

    test('skips windows with no usable name', () {
      final doses = dosesFromCalender([
        _dose(name: '', start: '08:00:00'),
        _dose(name: null, start: '09:00:00'),
        _dose(name: 'Real', start: '10:00:00'),
      ]);
      expect(doses.length, 1);
      expect(doses.first.name, 'Real');
    });

    test('returns empty list for empty input (drives the empty state)', () {
      expect(dosesFromCalender([]), isEmpty);
    });

    test('keeps a dose even when its time is unparseable, with empty time', () {
      final doses = dosesFromCalender([_dose(name: 'Mystery', start: 'x')]);
      expect(doses.length, 1);
      expect(doses.first.time, '');
    });
  });

  group('pillCountsFromCalender', () {
    test('is the honest empty state until a real feed exists', () {
      final counts = pillCountsFromCalender([
        _dose(name: 'Morning', start: '08:00:00'),
      ]);
      expect(counts.remaining, 0);
      expect(counts.consumed, 0);
      expect(counts.target, 0);
      expect(counts.hasData, isFalse);
    });

    test('PillCounts.hasData distinguishes real figures from empty', () {
      expect(PillCounts.empty.hasData, isFalse);
      expect(
        const PillCounts(remaining: 5, consumed: 0, target: 0).hasData,
        isTrue,
      );
    });
  });

  group('adherenceSeriesFromCalender -> chart empty/placeholder decision', () {
    test('returns an empty series when there is no real adherence history', () {
      final series = adherenceSeriesFromCalender([
        _dose(name: 'Morning', start: '08:00:00'),
      ]);
      expect(series, isEmpty);
      // The UI gate: a series shorter than 2 points renders "No data yet"
      // rather than a fabricated curve.
      expect(series.length >= 2, isFalse);
    });
  });
}
