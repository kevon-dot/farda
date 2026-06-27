// Pure-Dart unit tests for the refill prediction helper + event-payload builder
// (GTM-541). These import only model/repo files (no widgets, plugins, or
// platform channels) so they run fast and reliably under `flutter test` in CI,
// matching `test/models_test.dart`.

import 'package:flutter_test/flutter_test.dart';

import 'package:farda/application/refill/model/refill_model.dart';
import 'package:farda/application/refill/repo/refill_repo.dart';

void main() {
  group('RefillCalc.predict — days-left / refill-due', () {
    final now = DateTime(2026, 6, 27);

    test('computes days-left, depletion and refill-due from qty + rate', () {
      final r = RefillCalc.predict(
        initialQty: 30,
        dosesTaken: 0,
        dailyRate: 1,
        now: now,
      );
      expect(r.remaining, 30);
      expect(r.source, RemainingSource.estimated);
      expect(r.daysLeft, 30);
      // depletion = now + 30 days = 2026-07-27
      expect(r.predictedDepletion, DateTime(2026, 7, 27));
      // refill-due = depletion - 7 = 2026-07-20
      expect(r.refillDue, DateTime(2026, 7, 20));
      expect(r.isRefillDue, isFalse);
    });

    test('subtracts doses taken from initial qty', () {
      final r = RefillCalc.predict(
        initialQty: 30,
        dosesTaken: 10,
        dailyRate: 2,
        now: now,
      );
      expect(r.remaining, 20);
      expect(r.daysLeft, 10); // 20 / 2
    });

    test('flags isRefillDue when refill-due is today/past (low supply)', () {
      final r = RefillCalc.predict(
        initialQty: 5,
        dosesTaken: 0,
        dailyRate: 1,
        now: now,
      );
      // 5 days left, depletion now+5; refill-due now+5-7 = now-2 (past)
      expect(r.daysLeft, 5);
      expect(r.isRefillDue, isTrue);
    });

    test('prefers a measured (weight-sensor) reading over the qty estimate', () {
      final r = RefillCalc.predict(
        initialQty: 30,
        dosesTaken: 0,
        dailyRate: 1,
        measuredRemaining: 12,
        now: now,
      );
      expect(r.remaining, 12);
      expect(r.source, RemainingSource.measured);
      expect(r.daysLeft, 12);
    });

    test('clamps remaining at 0 and reports due when depleted', () {
      final r = RefillCalc.predict(
        initialQty: 10,
        dosesTaken: 25,
        dailyRate: 1,
        now: now,
      );
      expect(r.remaining, 0);
      expect(r.isRefillDue, isTrue);
    });

    test('returns nulls when qty is unknown', () {
      final r = RefillCalc.predict(
        initialQty: null,
        dosesTaken: 0,
        dailyRate: 1,
        now: now,
      );
      expect(r.remaining, isNull);
      expect(r.daysLeft, isNull);
      expect(r.predictedDepletion, isNull);
      expect(r.refillDue, isNull);
    });

    test('returns nulls when the daily rate is unknown (<= 0)', () {
      final r = RefillCalc.predict(
        initialQty: 30,
        dosesTaken: 0,
        dailyRate: 0,
        now: now,
      );
      expect(r.remaining, 30);
      expect(r.daysLeft, isNull);
      expect(r.predictedDepletion, isNull);
    });
  });

  group('RefillCalc.buildEventPayload', () {
    test('builds a REQUESTED payload with wire-cased type + iso timestamps', () {
      final due = DateTime.utc(2026, 7, 20);
      final occurred = DateTime.utc(2026, 6, 27, 12);
      final payload = RefillCalc.buildEventPayload(
        eventType: RefillEventType.requested,
        prescriptionId: 'rx-1',
        outcome: 'manual',
        refillDueDate: due,
        occurredAt: occurred,
        metadata: {'daysLeft': 5},
      );
      expect(payload['eventType'], 'REQUESTED');
      expect(payload['prescriptionId'], 'rx-1');
      expect(payload['outcome'], 'manual');
      expect(payload['channel'], 'MANUAL');
      expect(payload['refillDueDate'], due.toIso8601String());
      expect(payload['occurredAt'], occurred.toIso8601String());
      expect(payload['metadata'], {'daysLeft': 5});
    });

    test('omits null optional fields', () {
      final payload = RefillCalc.buildEventPayload(
        eventType: RefillEventType.completed,
      );
      expect(payload['eventType'], 'COMPLETED');
      expect(payload.containsKey('prescriptionId'), isFalse);
      expect(payload.containsKey('outcome'), isFalse);
      expect(payload.containsKey('refillDueDate'), isFalse);
      expect(payload.containsKey('metadata'), isFalse);
      // occurredAt is always present.
      expect(payload.containsKey('occurredAt'), isTrue);
    });
  });

  group('RefillModel.fromJson + RefillRepo.parseRefills', () {
    test('maps the backend prediction shape', () {
      final model = RefillModel.fromJson({
        'prescriptionId': 'rx-1',
        'rxNumber': 'RX-100',
        'medicineName': 'Lisinopril',
        'remaining': 25,
        'remainingSource': 'estimated',
        'dailyRate': 1,
        'daysLeft': 25,
        'predictedDepletion': '2026-07-22',
        'refillDue': '2026-07-15',
        'isRefillDue': false,
      });
      expect(model.prescriptionId, 'rx-1');
      expect(model.medicineName, 'Lisinopril');
      expect(model.remaining, 25);
      expect(model.remainingSource, RemainingSource.estimated);
      expect(model.daysLeft, 25);
      expect(model.hasForecast, isTrue);
      expect(model.isRefillDue, isFalse);
    });

    test('parseRefills reads the refills list and skips non-maps', () {
      final list = RefillRepo.parseRefills({
        'refills': [
          {'prescriptionId': 'rx-1', 'isRefillDue': true},
          'garbage',
          {'prescriptionId': 'rx-2'},
        ],
      });
      expect(list.length, 2);
      expect(list.first.prescriptionId, 'rx-1');
      expect(list.first.isRefillDue, isTrue);
    });

    test('hasForecast is false when daysLeft/refillDue are missing', () {
      final model = RefillModel.fromJson({'prescriptionId': 'rx-3'});
      expect(model.hasForecast, isFalse);
      expect(model.remaining, isNull);
    });
  });

  group('RefillMetrics.fromJson', () {
    test('maps adherence counts + completion rate', () {
      final m = RefillMetrics.fromJson({
        'requested': 4,
        'completed': 3,
        'delayed': 1,
        'completionRate': 0.75,
      });
      expect(m.requested, 4);
      expect(m.completed, 3);
      expect(m.delayed, 1);
      expect(m.completionRate, 0.75);
    });

    test('tolerates a null completion rate', () {
      final m = RefillMetrics.fromJson({'requested': 0});
      expect(m.requested, 0);
      expect(m.completionRate, isNull);
    });
  });
}
