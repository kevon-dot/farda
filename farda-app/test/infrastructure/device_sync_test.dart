import 'dart:async';
import 'dart:convert';

import 'package:farda/application/authentication/storage/session_store.dart';
import 'package:farda/utilities/api_configuration.dart';
import 'package:farda/services/device_sync/ble_sync_codec.dart';
import 'package:farda/services/device_sync/ble_sync_service.dart';
import 'package:farda/services/device_sync/device_observation.dart';
import 'package:farda/services/device_sync/device_outbox.dart';
import 'package:farda/services/device_sync/http_observation_uploader.dart';
import 'package:farda/utilities/diagnostics_policy.dart';
import 'package:farda/utilities/secure_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class MemorySecureStore implements SecureStore {
  final Map<String, String> data = {};
  bool failWrite = false;
  bool failDelete = false;
  final List<String> operations = [];
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async {
    if (failWrite) throw StateError('Simulated secure storage failure');
    data[key] = value;
    operations.add('write:$key');
  }

  @override
  Future<void> delete(String key) async {
    if (failDelete) throw StateError('Simulated secure storage failure');
    data.remove(key);
    operations.add('delete:$key');
  }

  @override
  Future<Map<String, String>> readAll() async => Map.of(data);
}

Map<String, dynamic> eventJson({int sequence = 1, int battery = 0}) => {
  'device_id': 'vial-1',
  'event_id': 'event-$sequence',
  'ownership_epoch': 'epoch-1',
  'boot_id': 'boot-1',
  'sequence': sequence,
  'event': 'PILL_CHANGE',
  'timestamp': 1780000000,
  'payload': <String, dynamic>{'battery': battery, 'change': 1, 'count': 19},
};
DeviceObservation event({int sequence = 1}) =>
    DeviceObservation.fromJson(eventJson(sequence: sequence));
DeviceReceipt receipt(DeviceObservation event, {String status = 'stored'}) =>
    DeviceReceipt({
      'status': status,
      'evidence_type': 'vial_observation',
      'receipt': {
        'committed': true,
        'device_id': event.deviceId,
        'event_id': event.eventId,
        'ownership_epoch': event.ownershipEpoch,
        'boot_id': event.bootId,
        'sequence': event.sequence,
      },
    });

class FakeUploader implements ObservationUploader {
  Object? error;
  DeviceReceipt? response;
  int uploads = 0;
  @override
  Future<DeviceReceipt> upload(
    String userId,
    DeviceObservation observation,
  ) async {
    uploads++;
    if (error != null) throw error!;
    return response ?? receipt(observation);
  }
}

class FakeBleTransport implements BleSyncTransport {
  final controller = StreamController<List<int>>.broadcast();
  final List<List<int>> commands = [];
  final List<bool> notificationStates = [];
  List<int>? frame;
  @override
  Stream<List<int>> get notifications => controller.stream;
  @override
  Future<void> setNotifications(bool enabled) async {
    notificationStates.add(enabled);
  }

  @override
  Future<void> write(List<int> value) async {
    commands.add(value);
    if (frame != null) {
      final split = frame!.length ~/ 2;
      controller.add(frame!.sublist(0, split));
      controller.add(frame!.sublist(split));
    }
  }
}

void main() {
  late MemorySecureStore storage;
  late SessionStore sessions;
  late DeviceOutbox outbox;
  setUp(() async {
    storage = MemorySecureStore();
    sessions = SessionStore(storage, purgeLegacyPreferences: () async {});
    await sessions.save(
      const StoredSession(token: 'token-a', userId: 'user-a'),
    );
    outbox = DeviceOutbox(sessions);
  });

  group('secure account lifecycle', () {
    test('private views are notified before logout storage cleanup completes', () async {
      var revisions = 0;
      final tracked = SessionStore(storage, purgeLegacyPreferences: () async {},
        onSessionChanged: () => revisions++);
      await tracked.save(const StoredSession(token: 'fresh', userId: 'user-a'));
      final before = revisions;
      final clearing = tracked.clear();
      expect(revisions, greaterThan(before));
      await clearing;
      expect(await tracked.read(), isNull);
    });

    test('a stale token rejection does not invalidate the new account view', () async {
      var revisions = 0;
      final tracked = SessionStore(storage, purgeLegacyPreferences: () async {},
        onSessionChanged: () => revisions++);
      await tracked.save(const StoredSession(token: 'new-token', userId: 'user-b'));
      final before = revisions;
      expect(await tracked.invalidateToken('token-a'), isFalse);
      expect(revisions, before);
      expect((await tracked.read())?.userId, 'user-b');
      expect(await tracked.invalidateToken('new-token'), isTrue);
      expect(revisions, greaterThan(before));
    });

    test('legacy credentials are not used as a session', () async {
      var purged = false;
      final legacy = SessionStore(
        MemorySecureStore(),
        purgeLegacyPreferences: () async {
          purged = true;
        },
      );
      expect(await legacy.read(), isNull);
      expect(purged, isTrue);
    });
    test(
      'token renewal retains pending events, account switch purges them',
      () async {
        await outbox.enqueue('user-a', [event()]);
        await sessions.save(
          const StoredSession(token: 'renewed', userId: 'user-a'),
        );
        expect((await outbox.pending('user-a')).length, 1);
        await sessions.save(
          const StoredSession(token: 'token-b', userId: 'user-b'),
        );
        expect((await sessions.read())?.userId, 'user-b');
        expect(
          storage.data.keys.where(
            (key) => key.startsWith(SessionStore.privatePrefix),
          ),
          isEmpty,
        );
        await expectLater(outbox.pending('user-a'), throwsStateError);
      },
    );
    test(
      'logout blocks reads even when secure storage cleanup fails',
      () async {
        storage.failDelete = true;
        await expectLater(sessions.clear(), throwsStateError);
        expect(await sessions.read(), isNull);
        final restarted = SessionStore(
          storage,
          purgeLegacyPreferences: () async {},
        );
        expect(await restarted.read(), isNull);
      },
    );
    test(
      'incomplete session is rejected without discarding current account',
      () async {
        await expectLater(
          sessions.save(const StoredSession(token: '', userId: 'user-a')),
          throwsArgumentError,
        );
        expect((await sessions.read())?.token, 'token-a');
      },
    );
    test(
      'private write racing logout is purged before logout returns',
      () async {
        final started = Completer<void>();
        final continueWrite = Completer<void>();
        final writing = sessions.forUser('user-a', (store) async {
          started.complete();
          await continueWrite.future;
          await store.write('${SessionStore.privatePrefix}draft', 'private');
        });
        await started.future;
        final clearing = sessions.clear();
        continueWrite.complete();
        await writing;
        await clearing;
        expect(storage.data, {SessionStore.revokedKey: '1'});
      },
    );
    test(
      'corrupt session clears private state rather than guessing identity',
      () async {
        storage.data[SessionStore.sessionKey] = '{broken';
        storage.data['${SessionStore.privatePrefix}draft'] = 'private';
        expect(await sessions.read(), isNull);
        expect(storage.data, {SessionStore.revokedKey: '1'});
      },
    );
  });

  group('durable observation outbox', () {
    test('restart preserves observations and zero battery', () async {
      await outbox.enqueue('user-a', [event()]);
      final reopened = DeviceOutbox(
        SessionStore(storage, purgeLegacyPreferences: () async {}),
      );
      final pending = await reopened.pending('user-a');
      expect(pending.single.payload['battery'], 0);
      expect(pending.single.event, 'PILL_CHANGE');
      expect(pending.single.toJson().containsKey('taken'), isFalse);
    });
    test(
      'replay deduplicates stable identities; conflicting contents fail closed',
      () async {
        await outbox.enqueue('user-a', [event(), event()]);
        expect((await outbox.pending('user-a')).length, 1);
        final conflict = DeviceObservation.fromJson(
          eventJson()..['timestamp'] = 1780000001,
        );
        await expectLater(
          outbox.enqueue('user-a', [conflict]),
          throwsStateError,
        );
        expect((await outbox.pending('user-a')).single.timestamp, 1780000000);
      },
    );
    test(
      'same event ID in different vials is not a cross-device collision',
      () async {
        final second = DeviceObservation.fromJson(
          eventJson()..['device_id'] = 'vial-2',
        );
        await outbox.enqueue('user-a', [event(), second]);
        expect((await outbox.pending('user-a')).length, 2);
      },
    );
    test('observation snapshots cannot be mutated after validation', () {
      final source = eventJson();
      final observation = DeviceObservation.fromJson(source);
      (source['payload'] as Map)['battery'] = 50;
      expect(observation.payload['battery'], 0);
      expect(() => observation.payload['battery'] = 50, throwsUnsupportedError);
    });
    test(
      'future device clocks are rejected before durable admission',
      () async {
        final outbox = DeviceOutbox(
          sessions,
          clock:
              () => DateTime.fromMillisecondsSinceEpoch(
                1780000000000,
                isUtc: true,
              ),
        );
        final future = DeviceObservation.fromJson(
          eventJson()..['timestamp'] = 1780000301,
        );
        await expectLater(
          outbox.enqueue('user-a', [future]),
          throwsFormatException,
        );
        expect(await outbox.pending('user-a'), isEmpty);
        final boundary = DeviceObservation.fromJson(
          eventJson()..['timestamp'] = 1780000300,
        );
        await outbox.enqueue('user-a', [boundary]);
        expect((await outbox.pending('user-a')).length, 1);
      },
    );
    test('payload keys match the server schema before storage', () {
      for (final key in ['api_key', 'apiKey', 'bad.key', '_hidden', 'a' * 65]) {
        expect(
          () =>
              DeviceObservation.fromJson(eventJson()..['payload'] = {key: 'x'}),
          throwsFormatException,
        );
      }
    });
    test('queue capacity never evicts oldest evidence', () async {
      final tiny = DeviceOutbox(sessions, maxEntries: 1);
      await tiny.enqueue('user-a', [event()]);
      await expectLater(
        tiny.enqueue('user-a', [event(sequence: 2)]),
        throwsStateError,
      );
      expect((await tiny.pending('user-a')).single.sequence, 1);
    });
    test(
      'storage failure does not report persistence or replace existing data',
      () async {
        await outbox.enqueue('user-a', [event()]);
        storage.failWrite = true;
        await expectLater(
          outbox.enqueue('user-a', [event(sequence: 2)]),
          throwsStateError,
        );
        expect((await outbox.pending('user-a')).length, 1);
      },
    );
    test('every receipt identity and committed flag must match', () async {
      await outbox.enqueue('user-a', [event()]);
      for (final field in [
        'device_id',
        'event_id',
        'ownership_epoch',
        'boot_id',
        'sequence',
        'committed',
      ]) {
        final value = receipt(event()).json;
        (value['receipt'] as Map)[field] = 'wrong';
        await expectLater(
          outbox.acceptReceipt('user-a', event(), DeviceReceipt(value)),
          throwsStateError,
        );
      }
      expect((await outbox.pending('user-a')).length, 1);
    });
    test(
      'network failure retains data; duplicate server commit then removes it',
      () async {
        await outbox.enqueue('user-a', [event()]);
        final uploader = FakeUploader()..error = TimeoutException('offline');
        await expectLater(
          DeviceOutboxSync(outbox, uploader).flush('user-a'),
          throwsA(isA<TimeoutException>()),
        );
        expect((await outbox.pending('user-a')).length, 1);
        uploader.error = null;
        uploader.response = receipt(event(), status: 'duplicate');
        expect(await DeviceOutboxSync(outbox, uploader).flush('user-a'), 1);
        expect(await outbox.pending('user-a'), isEmpty);
      },
    );
    test(
      'crash-equivalent failure after server commit safely replays receipt',
      () async {
        await outbox.enqueue('user-a', [event()]);
        storage.failWrite = true;
        await expectLater(
          outbox.acceptReceipt('user-a', event(), receipt(event())),
          throwsStateError,
        );
        storage.failWrite = false;
        expect((await outbox.pending('user-a')).length, 1);
        await outbox.acceptReceipt(
          'user-a',
          event(),
          receipt(event(), status: 'duplicate'),
        );
        expect(await outbox.pending('user-a'), isEmpty);
      },
    );
    test('corrupt outbox is surfaced and never silently reset', () async {
      const key = '${SessionStore.privatePrefix}device_outbox.v1.user-a';
      storage.data[key] = 'broken';
      await expectLater(outbox.pending('user-a'), throwsFormatException);
      expect(storage.data[key], 'broken');
    });
  });

  group('BLE frame boundaries', () {
    test(
      'handles split prefix and UTF-8 without decoding partial characters',
      () {
        final source = eventJson();
        (source['payload'] as Map)['label'] = 'café';
        final bytes = utf8.encode('SYNC_DATA${jsonEncode([source])}');
        final codec = BleSyncCodec();
        List<Map<String, dynamic>>? result;
        for (final byte in bytes) {
          result = codec.add([byte], now: DateTime.utc(2026));
        }
        expect(result?.single['payload']['label'], 'café');
      },
    );
    test('ignores brackets inside JSON strings and rejects trailing data', () {
      final codec = BleSyncCodec();
      final bytes = utf8.encode('SYNC_DATA[{"text":"a]b\\"[c"}]');
      expect(
        codec.add(bytes, now: DateTime.utc(2026))?.single['text'],
        'a]b"[c',
      );
      expect(
        () => BleSyncCodec().add(
          utf8.encode('SYNC_DATA[]garbage'),
          now: DateTime.utc(2026),
        ),
        throwsFormatException,
      );
    });
    test(
      'bounds frame size, event count, malformed UTF-8 and elapsed time',
      () {
        final now = DateTime.utc(2026);
        expect(
          () =>
              BleSyncCodec(maxBytes: 8).add(utf8.encode('SYNC_DATA'), now: now),
          throwsFormatException,
        );
        expect(
          () => BleSyncCodec(
            maxEvents: 0,
          ).add(utf8.encode('SYNC_DATA[{}]'), now: now),
          throwsFormatException,
        );
        expect(
          () => BleSyncCodec().add([
            ...utf8.encode('SYNC_DATA[{"v":"'),
            255,
            ...utf8.encode('"}]'),
          ], now: now),
          throwsFormatException,
        );
        final slow = BleSyncCodec();
        slow.add(utf8.encode('SYNC_'), now: now);
        expect(
          () => slow.add(
            utf8.encode('DATA[]'),
            now: now.add(const Duration(seconds: 11)),
          ),
          throwsFormatException,
        );
      },
    );
    test('legacy firmware cannot invent stable IDs or medication status', () {
      expect(
        () => DeviceObservation.fromJson({
          'ts': 1780000000,
          'evnt': 'PILL_CHANGE',
          'chng': 1,
        }),
        throwsFormatException,
      );
      expect(
        () => DeviceObservation.fromJson(eventJson()..['event'] = 'taken'),
        throwsFormatException,
      );
      expect(
        () => DeviceObservation.fromJson(
          eventJson()..['payload'] = {'auth_key': 'secret'},
        ),
        throwsFormatException,
      );
    });
  });

  group('BLE sync lifecycle', () {
    test(
      'successful durable server receipt still never sends destructive ACK',
      () async {
        final ble =
            FakeBleTransport()
              ..frame = utf8.encode('SYNC_DATA${jsonEncode([eventJson()])}');
        final service = BleSyncService(
          transport: ble,
          outbox: outbox,
          sync: DeviceOutboxSync(outbox, FakeUploader()),
        );
        final result = await service.receive(
          userId: 'user-a',
          deviceId: 'vial-1',
          ownershipEpoch: 'epoch-1',
          claimedAt: DateTime.fromMillisecondsSinceEpoch(
            1770000000000,
            isUtc: true,
          ),
          authKey: List.filled(32, 7),
        );
        expect(result.persisted, 1);
        expect(result.serverCommitted, 1);
        expect(result.deviceDeletionAcknowledged, isFalse);
        expect(ble.commands.map((command) => command.first), [0x30]);
        expect(ble.notificationStates, [true, false]);
        expect(ble.controller.hasListener, isFalse);
        await ble.controller.close();
      },
    );
    test('upload failure keeps evidence locally and on device', () async {
      final ble =
          FakeBleTransport()
            ..frame = utf8.encode('SYNC_DATA${jsonEncode([eventJson()])}');
      final uploader = FakeUploader()..error = StateError('offline');
      final service = BleSyncService(
        transport: ble,
        outbox: outbox,
        sync: DeviceOutboxSync(outbox, uploader),
      );
      await expectLater(
        service.receive(
          userId: 'user-a',
          deviceId: 'vial-1',
          ownershipEpoch: 'epoch-1',
          claimedAt: DateTime.fromMillisecondsSinceEpoch(
            1770000000000,
            isUtc: true,
          ),
          authKey: List.filled(32, 7),
        ),
        throwsStateError,
      );
      expect((await outbox.pending('user-a')).length, 1);
      expect(ble.commands.map((command) => command.first), [0x30]);
      await ble.controller.close();
    });
    test(
      'wrong device is rejected before persistence and transport is cleaned up',
      () async {
        final ble =
            FakeBleTransport()
              ..frame = utf8.encode('SYNC_DATA${jsonEncode([eventJson()])}');
        final service = BleSyncService(
          transport: ble,
          outbox: outbox,
          sync: DeviceOutboxSync(outbox, FakeUploader()),
        );
        await expectLater(
          service.receive(
            userId: 'user-a',
            deviceId: 'other',
            ownershipEpoch: 'epoch-1',
            claimedAt: DateTime.fromMillisecondsSinceEpoch(
              1770000000000,
              isUtc: true,
            ),
            authKey: List.filled(32, 7),
          ),
          throwsFormatException,
        );
        expect(await outbox.pending('user-a'), isEmpty);
        expect(ble.controller.hasListener, isFalse);
        await ble.controller.close();
      },
    );
    test(
      'pre-ownership observations stay on device and never enter outbox',
      () async {
        final ble =
            FakeBleTransport()
              ..frame = utf8.encode('SYNC_DATA${jsonEncode([eventJson()])}');
        final service = BleSyncService(
          transport: ble,
          outbox: outbox,
          sync: DeviceOutboxSync(outbox, FakeUploader()),
        );
        await expectLater(
          service.receive(
            userId: 'user-a',
            deviceId: 'vial-1',
            ownershipEpoch: 'epoch-1',
            claimedAt: DateTime.fromMillisecondsSinceEpoch(
              1780000001000,
              isUtc: true,
            ),
            authKey: List.filled(32, 7),
          ),
          throwsFormatException,
        );
        expect(await outbox.pending('user-a'), isEmpty);
        expect(ble.commands.map((command) => command.first), [0x30]);
        await ble.controller.close();
      },
    );
    test(
      'no notifications causes bounded timeout, not a retained subscription',
      () async {
        final ble = FakeBleTransport();
        final service = BleSyncService(
          transport: ble,
          outbox: outbox,
          sync: DeviceOutboxSync(outbox, FakeUploader()),
          timeout: const Duration(milliseconds: 20),
        );
        await expectLater(
          service.receive(
            userId: 'user-a',
            deviceId: 'vial-1',
            ownershipEpoch: 'epoch-1',
            claimedAt: DateTime.fromMillisecondsSinceEpoch(
              1770000000000,
              isUtc: true,
            ),
            authKey: List.filled(32, 7),
          ),
          throwsA(isA<TimeoutException>()),
        );
        expect(ble.controller.hasListener, isFalse);
        expect(ble.notificationStates.last, isFalse);
        await ble.controller.close();
      },
    );
  });

  group('API boundaries', () {
    test(
      'roots require explicit HTTPS and endpoints cannot escape the origin',
      () {
        expect(
          canonicalApiRoot('https://api.example.test/api/'),
          'https://api.example.test/api',
        );
        for (final root in [
          '',
          'http://api.example.test/api',
          'https://a:b@host/api',
          'https://host/api?token=x',
          'https://host/v1',
        ]) {
          expect(() => canonicalApiRoot(root), throwsStateError);
        }
        for (final endpoint in [
          'https://other.test/api',
          '../private',
          '%2e%2e/private',
          'doses?token=x',
        ]) {
          expect(
            () => apiUri('https://host/api', endpoint),
            throwsArgumentError,
          );
        }
        expect(
          apiUri('https://host/api/', '/doses').toString(),
          'https://host/api/doses',
        );
      },
    );
    test('diagnostics suppress health text, credentials and exceptions', () {
      expect(DiagnosticsPolicy.safeEvent('network_timeout'), 'network_timeout');
      for (final value in [
        'Authorization: Bearer secret',
        'patient: medication',
        {'token': 'secret'},
        'https://api.test?phone=123',
      ]) {
        expect(DiagnosticsPolicy.safeEvent(value), 'diagnostic_redacted');
      }
    });
    test(
      'HTTP upload uses current bearer, refuses redirects and checks receipt',
      () async {
        final client = MockClient((request) async {
          expect(
            request.url.toString(),
            'https://vial.example.test/api/user/devices/vial-1/observations',
          );
          expect(request.headers['Authorization'], 'Bearer token-a');
          expect(request.followRedirects, isFalse);
          expect(jsonDecode(request.body)['event'], 'PILL_CHANGE');
          return http.Response(jsonEncode(receipt(event()).json), 201);
        });
        final uploader = HttpObservationUploader(
          client: client,
          apiRoot: 'https://vial.example.test/api',
          sessions: sessions,
        );
        expect(
          (await uploader.upload('user-a', event())).commits(event()),
          isTrue,
        );
        client.close();
      },
    );
    test('late 401 cannot clear a newer account', () async {
      final client = MockClient((request) async {
        await sessions.save(
          const StoredSession(token: 'token-b', userId: 'user-b'),
        );
        return http.Response('{}', 401);
      });
      final uploader = HttpObservationUploader(
        client: client,
        apiRoot: 'https://vial.example.test/api',
        sessions: sessions,
      );
      await expectLater(uploader.upload('user-a', event()), throwsStateError);
      expect((await sessions.read())?.userId, 'user-b');
      client.close();
    });
  });
}
