// Pure-Dart unit tests for the Plan tab view-model. Imports only the
// view-model + dose model (no widgets, plugins, or platform channels) so it
// runs fast and reliably under `flutter test` in CI.

import 'package:flutter_test/flutter_test.dart';

import 'package:farda/application/calender/model/dose_time_model.dart';
import 'package:farda/screens/dashboard/plan/plan_view_model.dart';

DoseTimeModel _dose(String name, String? start) =>
    DoseTimeModel(name: name, startTime: start);

void main() {
  group('PlanViewModel.normaliseTime', () {
    test('strips seconds from HH:mm:ss', () {
      expect(PlanViewModel.normaliseTime('08:30:00'), '08:30');
    });

    test('passes through HH:mm', () {
      expect(PlanViewModel.normaliseTime('21:05'), '21:05');
    });

    test('returns empty string for null/blank/invalid input', () {
      expect(PlanViewModel.normaliseTime(null), '');
      expect(PlanViewModel.normaliseTime('   '), '');
      expect(PlanViewModel.normaliseTime('not-a-time'), '');
      expect(PlanViewModel.normaliseTime('99:99'), '');
    });
  });

  group('PlanViewModel.minutesOfDay', () {
    test('computes minutes past midnight', () {
      expect(PlanViewModel.minutesOfDay('00:00:00'), 0);
      expect(PlanViewModel.minutesOfDay('08:30'), 8 * 60 + 30);
      expect(PlanViewModel.minutesOfDay('23:59'), 23 * 60 + 59);
    });

    test('returns -1 for invalid input', () {
      expect(PlanViewModel.minutesOfDay(null), -1);
      expect(PlanViewModel.minutesOfDay(''), -1);
      expect(PlanViewModel.minutesOfDay('24:00'), -1);
      expect(PlanViewModel.minutesOfDay('garbage'), -1);
    });
  });

  group('PlanViewModel.scheduleFromDoses', () {
    test('sorts dose windows by start time (earliest first)', () {
      final items = PlanViewModel.scheduleFromDoses([
        _dose('Evening', '20:00:00'),
        _dose('Morning', '08:00:00'),
        _dose('Midday', '12:30:00'),
      ]);

      expect(items.map((e) => e.name).toList(), [
        'Morning',
        'Midday',
        'Evening',
      ]);
      expect(items.first.time, '08:00');
    });

    test('drops entries with a missing/blank name', () {
      final items = PlanViewModel.scheduleFromDoses([
        _dose('  ', '08:00'),
        _dose('Morning', '08:00'),
      ]);

      expect(items.length, 1);
      expect(items.single.name, 'Morning');
    });

    test('places entries with unknown times last', () {
      final items = PlanViewModel.scheduleFromDoses([
        _dose('Unknown', null),
        _dose('Morning', '08:00'),
      ]);

      expect(items.map((e) => e.name).toList(), ['Morning', 'Unknown']);
      expect(items.last.time, '');
    });

    test('attaches the medicine name to every window when provided', () {
      final items = PlanViewModel.scheduleFromDoses(
        [_dose('Morning', '08:00'), _dose('Evening', '20:00')],
        medicineName: 'Amoxicillin',
      );

      expect(items.every((e) => e.medicineName == 'Amoxicillin'), isTrue);
    });

    test('leaves medicine null when blank/absent', () {
      final blank = PlanViewModel.scheduleFromDoses(
        [_dose('Morning', '08:00')],
        medicineName: '   ',
      );
      expect(blank.single.medicineName, isNull);

      final absent = PlanViewModel.scheduleFromDoses([_dose('Morning', '08:00')]);
      expect(absent.single.medicineName, isNull);
    });

    test('returns empty list and isEmpty is true when no valid doses', () {
      expect(PlanViewModel.scheduleFromDoses(const []), isEmpty);
      expect(PlanViewModel.isEmpty(const []), isTrue);
      expect(PlanViewModel.isEmpty([_dose('', '08:00')]), isTrue);
      expect(PlanViewModel.isEmpty([_dose('Morning', '08:00')]), isFalse);
    });
  });
}
