// GTM-521 — pure-Dart unit tests for the EMA ground-truth wiring.
//
// These import only pure helpers (the EMA answer enum + body builder and the
// Vial URL builders) — no widgets, plugins, or platform channels — so they run
// fast and reliably under `flutter test` in CI.

import 'package:flutter_test/flutter_test.dart';

import 'package:farda/app_const/app_urls.dart';
import 'package:farda/application/device/model/ema_response.dart';

void main() {
  group('EmaAnswer wire values mirror GROUND_TRUTH in the Vial backend', () {
    test('taken / not_taken / unsure', () {
      expect(EmaAnswer.taken.wireValue, 'taken');
      expect(EmaAnswer.notTaken.wireValue, 'not_taken');
      expect(EmaAnswer.unsure.wireValue, 'unsure');
    });
  });

  group('EmaResponse.toBody', () {
    test('includes the self-report, dose link, and a stable idempotency key', () {
      const r = EmaResponse(
        deviceId: 'vial-1',
        answer: EmaAnswer.taken,
        doseEventId: 'dose_42',
      );
      final body = r.toBody();
      expect(body['self_reported_taken'], 'taken');
      expect(body['dose_event_id'], 'dose_42');
      expect(body['idempotency_key'], 'ema_vial-1_dose_42_taken');
    });

    test('omits dose_event_id when not known', () {
      const r = EmaResponse(deviceId: 'vial-1', answer: EmaAnswer.notTaken);
      final body = r.toBody();
      expect(body.containsKey('dose_event_id'), isFalse);
      expect(body['self_reported_taken'], 'not_taken');
      expect(body['idempotency_key'], 'ema_vial-1_na_not_taken');
    });

    test('idempotency key is stable for the same device + dose + answer', () {
      const a = EmaResponse(
          deviceId: 'vial-1', answer: EmaAnswer.taken, doseEventId: 'd1');
      const b = EmaResponse(
          deviceId: 'vial-1', answer: EmaAnswer.taken, doseEventId: 'd1');
      expect(a.idempotencyKey, b.idempotencyKey);
    });
  });

  group('VialUrls — ground-truth paths mirror the Vial Express routes', () {
    test('ema + pill-count paths', () {
      expect(VialUrls.emaResponses('vial-1'),
          'api/user/devices/vial-1/ema-responses');
      expect(VialUrls.pillCountCheckpoints('vial-1'),
          'api/user/devices/vial-1/pill-count-checkpoints');
    });

    test('device ids are URL-encoded', () {
      expect(VialUrls.emaResponses('a b'),
          'api/user/devices/a%20b/ema-responses');
    });
  });
}
