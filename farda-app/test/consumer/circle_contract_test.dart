import 'dart:convert';

import 'package:farda/features/consumer/data/circle_models.dart';
import 'package:farda/features/consumer/data/consumer_api_repository.dart';
import 'package:farda/features/consumer/data/consumer_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('invite parses the one-time code and anonymous phone label', () async {
    late http.Request captured;
    final repository = ConsumerApiRepository(
      baseUrl: 'https://example.test/api',
      tokenProvider: () async => 'account-a',
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'status': 'awaiting_acceptance',
            'invitation': {
              'id': 'invite-1',
              'person': {'id': '', 'displayName': 'Phone ending 0002'},
              'permissions': {'doseStatus': true, 'reminders': false},
              'createdAt': '2026-10-16T12:00:00.000Z',
              'expiresAt': '2026-10-23T12:00:00.000Z',
              'inviteCode': 'one-time-share-code-1234567890',
            },
          }),
          202,
        );
      }),
    );

    final invitation = await repository.inviteToCircle(
      '+15550000002',
      const CirclePermissions(doseStatus: true, reminders: false),
    );

    expect(captured.method, 'POST');
    expect(captured.url.path, '/api/circle/invitations');
    expect(jsonDecode(captured.body), {
      'recipientPhone': '+15550000002',
      'permissions': {'doseStatus': true, 'reminders': false},
    });
    expect(invitation.person.displayName, 'Phone ending 0002');
    expect(invitation.inviteCode, 'one-time-share-code-1234567890');
    expect(invitation.permissions.reminders, isFalse);
    repository.dispose();
  });

  test(
    'shared list maps owner and access timestamps without private fields',
    () async {
      final repository = ConsumerApiRepository(
        baseUrl: 'https://example.test/api',
        tokenProvider: () async => 'recipient',
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'circles': [
                {
                  'owner': {'id': 'owner-1', 'displayName': 'Alex'},
                  'access': {
                    'id': 'grant-1',
                    'permissions': {'doseStatus': false, 'reminders': true},
                    'acceptedAt': '2026-10-15T09:00:00.000Z',
                    'updatedAt': '2026-10-16T10:00:00.000Z',
                  },
                },
              ],
            }),
            200,
          ),
        ),
      );

      final shared = (await repository.loadSharedCircles()).single;
      expect(shared.owner.displayName, 'Alex');
      expect(shared.access.id, 'grant-1');
      expect(shared.access.person.id, 'owner-1');
      expect(shared.access.permissions.doseStatus, isFalse);
      expect(shared.access.permissions.reminders, isTrue);
      expect(shared.access.updatedAt.toUtc(), DateTime.utc(2026, 10, 16, 10));
      repository.dispose();
    },
  );

  test('routine parses scoped reminder, state, and evidence fields', () async {
    final repository = ConsumerApiRepository(
      baseUrl: 'https://example.test/api',
      tokenProvider: () async => 'recipient',
      client: MockClient((request) async {
        expect(request.url.queryParameters.keys, containsAll(['from', 'to']));
        return http.Response(
          jsonEncode({
            'owner': {'id': 'owner-1', 'displayName': 'Alex'},
            'permissions': {'doseStatus': true, 'reminders': true},
            'items': [
              {
                'id': 'dose-1',
                'label': 'Routine item',
                'scheduledFor': '2026-10-16T13:00:00.000Z',
                'ownerTimeZone': 'America/New_York',
                'state': 'taken',
                'evidence': 'self_report',
                'recordedAt': '2026-10-16T13:04:00.000Z',
              },
              {
                'id': 'dose-2',
                'label': 'Routine item',
                'scheduledFor': '2026-10-16T21:00:00.000Z',
                'ownerTimeZone': 'America/New_York',
                'state': 'not_recorded',
                'evidence': 'none',
              },
              {
                'id': 'dose-3',
                'label': 'Routine item',
                'state': 'taken',
                'evidence': 'device_observation',
              },
              {
                'id': 'dose-4',
                'label': 'Routine item',
                'state': 'skipped',
                'evidence': 'self_report',
                'recordedAt': '2026-10-16T22:05:00.000Z',
              },
            ],
            'fetchedAt': '2026-10-16T14:00:00.000Z',
            'notice': 'Not recorded does not mean missed.',
          }),
          200,
        );
      }),
    );

    final routine = await repository.loadSharedCircleRoutine(
      'grant-1',
      from: DateTime.utc(2026, 10, 16),
      to: DateTime.utc(2026, 10, 17),
    );
    expect(routine.items[0].state, CircleRoutineState.taken);
    expect(routine.items[0].evidence, CircleEvidence.selfReport);
    expect(routine.items[0].ownerTimeZone, 'America/New_York');
    expect(routine.items[1].state, CircleRoutineState.notRecorded);
    expect(routine.items[1].evidence, CircleEvidence.none);
    expect(routine.items[2].evidence, CircleEvidence.deviceObservation);
    expect(routine.items[2].scheduledFor, isNull);
    expect(routine.items[3].state, CircleRoutineState.skipped);
    expect(routine.items[3].evidence, CircleEvidence.selfReport);
    expect(routine.items[3].recordedAt, DateTime.utc(2026, 10, 16, 22, 5));
    expect(routine.notice, contains('does not mean missed'));
    repository.dispose();
  });

  test(
    'a Circle response is rejected when the signed-in account switches',
    () async {
      var token = 'account-a';
      final repository = ConsumerApiRepository(
        baseUrl: 'https://example.test/api',
        tokenProvider: () async => token,
        client: MockClient((_) async {
          token = 'account-b';
          return http.Response('{"pending":[],"members":[]}', 200);
        }),
      );

      await expectLater(
        repository.loadCircle(),
        throwsA(
          isA<ConsumerRepositoryException>().having(
            (error) => error.sessionChanged,
            'sessionChanged',
            isTrue,
          ),
        ),
      );
      repository.dispose();
    },
  );
}
