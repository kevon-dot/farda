// Pure-Dart unit tests for the vial dose-log sync → parse → upload →
// buffer/retry pipeline (GTM-514).
//
// These import only pure logic (the log parser, the event model + idempotency
// key, and the offline-queue decision helpers) — no widgets, plugins, or
// platform channels — so they run fast and reliably under `flutter test` in CI.
//
// What still needs REAL HARDWARE (not covered here): the BLE bytes themselves —
// the REQUEST_SYNC write, the `SYNC_DATA[...]` notify stream, and the ACK that
// clears the device log (GTM-513). This suite validates everything downstream
// of "we have the raw buffer".

import 'package:flutter_test/flutter_test.dart';

import 'package:farda/app_const/app_urls.dart';
import 'package:farda/application/device/model/dose_log_event.dart';
import 'package:farda/application/device/sync/dose_log_parser.dart';
import 'package:farda/application/device/sync/dose_sync_queue.dart';

void main() {
  group('DoseLogParser.isComplete', () {
    test('true only for a fully-framed SYNC_DATA[...] buffer', () {
      expect(DoseLogParser.isComplete('SYNC_DATA[]'), isTrue);
      expect(DoseLogParser.isComplete('SYNC_DATA[{"event":"OPEN"}]'), isTrue);
      // Tolerates surrounding whitespace from chunked delivery.
      expect(DoseLogParser.isComplete('  SYNC_DATA[]  '), isTrue);
    });

    test('false for partial / unframed buffers', () {
      expect(DoseLogParser.isComplete('SYNC_DATA[{"event":"OP'), isFalse);
      expect(DoseLogParser.isComplete('SYNC_DA'), isFalse);
      expect(DoseLogParser.isComplete('[]'), isFalse);
      expect(DoseLogParser.isComplete(''), isFalse);
    });
  });

  group('DoseLogParser.parse → event mapping', () {
    test('maps a SYNC_DATA frame into typed events stamped with deviceId', () {
      const buffer =
          'SYNC_DATA[{"event":"open","ts":1738483200,"seq":1,"payload":{"duration":3}},'
          '{"type":"CLOSE","timestamp":1738483260,"sequence":2}]';

      final events = DoseLogParser.parse(buffer, 'vial-1');

      expect(events.length, 2);
      // event type is normalised to uppercase.
      expect(events[0].event, 'OPEN');
      expect(events[1].event, 'CLOSE');
      // deviceId (#23) is linked onto every event.
      expect(events.every((e) => e.deviceId == 'vial-1'), isTrue);
      // tolerant field naming (ts/timestamp, seq/sequence) is honoured.
      expect(events[0].timestamp, 1738483200);
      expect(events[0].sequence, 1);
      expect(events[1].timestamp, 1738483260);
      // payload passthrough.
      expect(events[0].payload['duration'], 3);
    });

    test('skips malformed rows instead of failing the whole batch', () {
      const buffer = 'SYNC_DATA[{"event":"OPEN","ts":1},'
          '{"noEventType":true},'
          '"not-an-object",'
          '{"event":"  ","ts":2}]';

      final events = DoseLogParser.parse(buffer, 'vial-1');

      // Only the single well-formed OPEN survives.
      expect(events.length, 1);
      expect(events.single.event, 'OPEN');
    });

    test('returns empty list for non-SYNC_DATA or invalid JSON, never throws', () {
      expect(DoseLogParser.parse('garbage', 'vial-1'), isEmpty);
      expect(DoseLogParser.parse('SYNC_DATA{not a list}', 'vial-1'), isEmpty);
      expect(DoseLogParser.parse('SYNC_DATA', 'vial-1'), isEmpty);
      expect(DoseLogParser.parse('SYNC_DATA[broken', 'vial-1'), isEmpty);
    });
  });

  group('DoseLogEvent — idempotency key + ingest body', () {
    test('eventId is STABLE for the same event identity (re-sync safe)', () {
      const a = DoseLogEvent(
        deviceId: 'vial-1',
        event: 'OPEN',
        timestamp: 1738483200,
        sequence: 7,
      );
      const b = DoseLogEvent(
        deviceId: 'vial-1',
        event: 'OPEN',
        timestamp: 1738483200,
        sequence: 7,
        // payload differs but identity (device/type/ts/seq) is the same -> same id.
        payload: {'duration': 99},
      );

      expect(a.eventId, b.eventId);
      expect(a.eventId, startsWith('evt_'));
    });

    test('eventId DIFFERS when identity differs (no false dedupe)', () {
      const base = DoseLogEvent(
          deviceId: 'vial-1', event: 'OPEN', timestamp: 1, sequence: 1);
      const otherDevice = DoseLogEvent(
          deviceId: 'vial-2', event: 'OPEN', timestamp: 1, sequence: 1);
      const otherType = DoseLogEvent(
          deviceId: 'vial-1', event: 'CLOSE', timestamp: 1, sequence: 1);
      const otherTs = DoseLogEvent(
          deviceId: 'vial-1', event: 'OPEN', timestamp: 2, sequence: 1);
      const otherSeq = DoseLogEvent(
          deviceId: 'vial-1', event: 'OPEN', timestamp: 1, sequence: 2);

      final ids = {
        base.eventId,
        otherDevice.eventId,
        otherType.eventId,
        otherTs.eventId,
        otherSeq.eventId,
      };
      // All five are distinct.
      expect(ids.length, 5);
    });

    test('toIngestBody is the exact Vial wire shape + carries the dedupe key', () {
      const event = DoseLogEvent(
        deviceId: 'vial-1',
        event: 'OPEN',
        timestamp: 1738483200,
        sequence: 1,
        payload: {'duration': 3},
      );

      final body = event.toIngestBody();

      expect(body['device_id'], 'vial-1');
      expect(body['event'], 'OPEN');
      expect(body['timestamp'], 1738483200);
      expect(body['event_id'], event.eventId);
      expect(body['payload'], {'duration': 3});
    });

    test('toIngestBody omits timestamp when the firmware did not stamp it', () {
      const event = DoseLogEvent(deviceId: 'vial-1', event: 'BOOT');
      final body = event.toIngestBody();
      expect(body.containsKey('timestamp'), isFalse);
      expect(body['event_id'], isNotNull);
    });

    test('queue JSON round-trips and preserves the idempotency key', () {
      const event = DoseLogEvent(
        deviceId: 'vial-1',
        event: 'TILT',
        timestamp: 5,
        sequence: 9,
        payload: {'angle': 42},
      );
      final copy = DoseLogEvent.fromQueueJson(event.toQueueJson());

      expect(copy.eventId, event.eventId);
      expect(copy.event, 'TILT');
      expect(copy.payload['angle'], 42);
    });
  });

  group('DoseSyncQueue.mergeForEnqueue — local idempotency', () {
    test('drops events already queued (dedupe by eventId)', () {
      const e1 = DoseLogEvent(deviceId: 'v', event: 'OPEN', timestamp: 1, sequence: 1);
      const e2 = DoseLogEvent(deviceId: 'v', event: 'CLOSE', timestamp: 2, sequence: 2);
      const e1Dup = DoseLogEvent(
          deviceId: 'v', event: 'OPEN', timestamp: 1, sequence: 1, payload: {'x': 1});

      final merged = DoseSyncQueue.mergeForEnqueue([e1], [e1Dup, e2]);

      // e1Dup is a duplicate of e1 -> only e2 is genuinely added.
      expect(merged.length, 2);
      expect(merged.map((e) => e.eventId).toSet(),
          {e1.eventId, e2.eventId});
    });

    test('preserves order: existing first, then new', () {
      const a = DoseLogEvent(deviceId: 'v', event: 'OPEN', timestamp: 1, sequence: 1);
      const b = DoseLogEvent(deviceId: 'v', event: 'CLOSE', timestamp: 2, sequence: 2);

      final merged = DoseSyncQueue.mergeForEnqueue([a], [b]);
      expect(merged.first.eventId, a.eventId);
      expect(merged.last.eventId, b.eventId);
    });
  });

  group('DoseSyncQueue retry decision', () {
    test('null status (offline/transport failure) -> retry', () {
      expect(DoseSyncQueue.shouldRetry(null), isTrue);
      expect(DoseSyncQueue.isDelivered(null), isFalse);
    });

    test('2xx -> delivered, not retried', () {
      for (final code in [200, 201, 204]) {
        expect(DoseSyncQueue.isDelivered(code), isTrue, reason: 'code $code');
        expect(DoseSyncQueue.shouldRetry(code), isFalse, reason: 'code $code');
      }
    });

    test('5xx / 429 (transient) -> retry, not delivered', () {
      for (final code in [429, 500, 502, 503]) {
        expect(DoseSyncQueue.shouldRetry(code), isTrue, reason: 'code $code');
        expect(DoseSyncQueue.isDelivered(code), isFalse, reason: 'code $code');
      }
    });

    test('400 (bad/unclaimed device) -> terminal: drop, do not retry', () {
      expect(DoseSyncQueue.shouldRetry(400), isFalse);
      expect(DoseSyncQueue.isDelivered(400), isTrue);
    });

    test('401/403 (auth, post-refresh) -> do not retry forever', () {
      expect(DoseSyncQueue.shouldRetry(401), isFalse);
      expect(DoseSyncQueue.shouldRetry(403), isFalse);
    });
  });

  group('DoseSyncQueue encode/decode (persistence is testable, pure)', () {
    test('round-trips a queue through JSON', () {
      const events = [
        DoseLogEvent(deviceId: 'v', event: 'OPEN', timestamp: 1, sequence: 1),
        DoseLogEvent(deviceId: 'v', event: 'CLOSE', timestamp: 2, sequence: 2),
      ];
      final decoded = DoseSyncQueue.decode(DoseSyncQueue.encode(events));

      expect(decoded.length, 2);
      expect(decoded.map((e) => e.eventId).toList(),
          events.map((e) => e.eventId).toList());
    });

    test('decode tolerates null/empty/corrupt storage', () {
      expect(DoseSyncQueue.decode(null), isEmpty);
      expect(DoseSyncQueue.decode(''), isEmpty);
      expect(DoseSyncQueue.decode('{not json'), isEmpty);
      expect(DoseSyncQueue.decode('{"obj":true}'), isEmpty);
    });
  });

  group('VialUrls.ingestDeviceEvent (GTM-514 relay path)', () {
    test('composes a device-scoped, URL-encoded ingest path', () {
      expect(VialUrls.ingestDeviceEvent('vial-1'),
          'api/user/devices/vial-1/events/ingest');
      expect(VialUrls.ingestDeviceEvent('a b'),
          'api/user/devices/a%20b/events/ingest');
    });
  });
}
