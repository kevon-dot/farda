import 'dart:async';

import 'package:farda/application/authentication/storage/session_store.dart';
import 'package:farda/services/live_activity_registration.dart';
import 'package:farda/services/live_activity_service.dart';
import 'package:farda/utilities/secure_store.dart';
import 'package:flutter_test/flutter_test.dart';

class MemorySecureStore implements SecureStore {
  final values = <String, String>{};
  @override
  Future<void> delete(String key) async => values.remove(key);
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<Map<String, String>> readAll() async => Map.of(values);
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class RegistrationRepository implements LiveActivityRegistrationRepository {
  final calls = <Map<String, String>>[];
  Completer<void>? gate;
  @override
  Future<void> registerPushToStartToken({
    required String installationId,
    required String token,
  }) async {
    calls.add({
      'type': 'start',
      'installationId': installationId,
      'token': token,
    });
    await gate?.future;
  }

  @override
  Future<void> registerActivityToken({
    required String installationId,
    required String activityId,
    required String occurrenceId,
    required String token,
  }) async {
    calls.add({
      'type': 'activity',
      'installationId': installationId,
      'activityId': activityId,
      'occurrenceId': occurrenceId,
      'token': token,
    });
  }

  @override
  Future<void> revokeLiveActivityInstallation(String installationId) async {
    calls.add({'type': 'revoke', 'installationId': installationId});
  }
}

void main() {
  const installationId = '123e4567-e89b-42d3-a456-426614174000';
  final startToken = List.filled(32, 'ab').join();
  final activityToken = List.filled(32, 'cd').join();
  late MemorySecureStore store;
  late SessionStore sessions;
  late RegistrationRepository repository;
  late LiveActivityTokenRegistrar registrar;

  setUp(() async {
    store = MemorySecureStore();
    sessions = SessionStore(store, purgeLegacyPreferences: () async {});
    await sessions.save(const StoredSession(token: 'session', userId: 'owner'));
    repository = RegistrationRepository();
    registrar = LiveActivityTokenRegistrar(
      repository: repository,
      sessions: sessions,
      createInstallationId: () => installationId,
    );
  });

  test(
    'registers both token kinds under one protected installation identity',
    () async {
      await registrar.handle(
        LiveActivityEvent({'type': 'pushToStartToken', 'token': startToken}),
      );
      await registrar.handle(
        LiveActivityEvent({
          'type': 'pushToken',
          'activityId': 'activity-1',
          'occurrenceId': 'dose-1',
          'token': activityToken,
        }),
      );
      expect(repository.calls, [
        {
          'type': 'start',
          'installationId': installationId,
          'token': startToken,
        },
        {
          'type': 'activity',
          'installationId': installationId,
          'activityId': 'activity-1',
          'occurrenceId': 'dose-1',
          'token': activityToken,
        },
      ]);
      expect(
        store.values['farda.private.live_activity_installation.v1'],
        installationId,
      );
    },
  );

  test('serializes rotations and revokes the current installation', () async {
    repository.gate = Completer<void>();
    final first = registrar.handle(
      LiveActivityEvent({'type': 'pushToStartToken', 'token': startToken}),
    );
    final second = registrar.handle(
      LiveActivityEvent({
        'type': 'pushToken',
        'activityId': 'activity-1',
        'occurrenceId': 'dose-1',
        'token': activityToken,
      }),
    );
    await Future<void>.delayed(Duration.zero);
    expect(repository.calls.map((call) => call['type']), ['start']);
    repository.gate!.complete();
    await Future.wait([first, second]);
    await registrar.revoke();
    expect(repository.calls.map((call) => call['type']), [
      'start',
      'activity',
      'revoke',
    ]);
  });

  test('account replacement purges the old installation identity', () async {
    const nextInstallationId = '223e4567-e89b-42d3-a456-426614174000';
    var generation = 0;
    registrar = LiveActivityTokenRegistrar(
      repository: repository,
      sessions: sessions,
      createInstallationId:
          () => generation++ == 0 ? installationId : nextInstallationId,
    );
    await registrar.handle(
      LiveActivityEvent({'type': 'pushToStartToken', 'token': startToken}),
    );
    await sessions.save(
      const StoredSession(token: 'session-b', userId: 'other'),
    );
    await registrar.handle(
      LiveActivityEvent({'type': 'pushToStartToken', 'token': startToken}),
    );
    expect(repository.calls.map((call) => call['installationId']), [
      installationId,
      nextInstallationId,
    ]);
    expect(
      store.values['farda.private.live_activity_installation.v1'],
      nextInstallationId,
    );
  });

  test(
    'rejects malformed native values before an authenticated request',
    () async {
      await expectLater(
        registrar.handle(
          LiveActivityEvent({
            'type': 'pushToStartToken',
            'token': 'not-a-token',
          }),
        ),
        throwsFormatException,
      );
      expect(repository.calls, isEmpty);
    },
  );
}
