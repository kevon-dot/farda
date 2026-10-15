import 'dart:convert';
import 'package:farda/features/consumer/consumer_controller.dart';
import 'package:farda/features/consumer/data/consumer_api_repository.dart';
import 'package:farda/features/consumer/data/consumer_demo_repository.dart';
import 'package:farda/features/consumer/data/consumer_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final now = DateTime(2026, 10, 15, 10);
  final from = DateTime(2026, 10, 1);
  final to = DateTime(2026, 11, 1);
  ConsumerPrescriptionDraft draft({
    String directions = 'Check label',
    bool reviewed = true,
  }) => ConsumerPrescriptionDraft(
    name: 'Test prescription',
    directions: directions,
    labelReviewed: reviewed,
    timeZone: 'America/Los_Angeles',
    times: ['09:00'],
    startDate: now,
    clientRequestId: 'test-client-request-123',
  );

  test('manual review rejects missing directions and an unchecked label', () {
    expect(draft(directions: '').validationError, isNotNull);
    expect(draft(reviewed: false).validationError, isNotNull);
    expect(draft().validationError, isNull);
    expect(
      (draft().toJson()['schedule'] as Map)['timezone'],
      'America/Los_Angeles',
    );
  });

  test(
    'month-boundary refresh retains an unresolved occurrence from yesterday',
    () async {
      final midnight = DateTime(2026, 10, 1, 0, 10);
      final due = DateTime(2026, 9, 30, 23, 50);
      final ranges = <Duration>[];
      final repository = ConsumerApiRepository(
        baseUrl: 'https://example.test/api',
        tokenProvider: () async => 'token',
        client: MockClient((request) async {
          if (request.url.path.endsWith('/doses')) {
            final start = DateTime.parse(request.url.queryParameters['from']!);
            final end = DateTime.parse(request.url.queryParameters['to']!);
            ranges.add(end.difference(start));
            return http.Response(
              jsonEncode({
                'data':
                    !due.isBefore(start) && due.isBefore(end)
                        ? [
                          {
                            'id': 'midnight-entry',
                            'prescriptionId': 'p',
                            'scheduledFor': due.toUtc().toIso8601String(),
                            'status': 'unconfirmed',
                          },
                        ]
                        : [],
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/prescriptions')) {
            return http.Response('{"data":[]}', 200);
          }
          if (request.url.path.endsWith('/refills')) {
            return http.Response('{"refills":[]}', 200);
          }
          return http.Response('{"preferences":{},"capabilities":{}}', 200);
        }),
      );
      final controller = ConsumerController(repository, now: () => midnight);
      await controller.load();
      expect(controller.snapshot!.occurrences.single.id, 'midnight-entry');
      expect(ranges.length, 2);
      expect(ranges.every((r) => r.inDays <= 31), isTrue);
      controller.dispose();
    },
  );

  test(
    'logout pins the captured token instead of revoking a switched account',
    () async {
      String? sent;
      final repository = ConsumerApiRepository(
        baseUrl: 'https://example.test/api',
        tokenProvider: () async => 'account-B',
        client: MockClient((request) async {
          sent = request.headers['Authorization'];
          return http.Response('{}', 200);
        }),
      );
      expect(await repository.signOut('account-A'), isFalse);
      expect(sent, 'Bearer account-A');
      repository.dispose();
    },
  );

  test(
    'future schedule edits omit client now and preserve create save identity',
    () async {
      final requests = <http.Request>[];
      final repository = ConsumerApiRepository(
        baseUrl: 'https://example.test/api',
        tokenProvider: () async => 'token',
        client: MockClient((request) async {
          requests.add(request);
          return http.Response('{"data":{}}', 200);
        }),
      );
      await repository.savePrescription(draft());
      await repository.savePrescription(draft());
      expect(
        jsonDecode(requests[0].body)['clientRequestId'],
        jsonDecode(requests[1].body)['clientRequestId'],
      );
      await repository.updateSchedule('p1', draft());
      expect(
        jsonDecode(requests.last.body).containsKey('effectiveAt'),
        isFalse,
      );
      expect(requests.last.url.path, '/api/prescriptions/p1/schedules');
      expect(requests.every((r) => !r.followRedirects), isTrue);
      repository.dispose();
    },
  );

  test('first inventory count omits nonexistent revision zero', () async {
    http.Request? count;
    final repository = ConsumerApiRepository(
      baseUrl: 'https://example.test/api',
      tokenProvider: () async => 'token',
      client: MockClient((request) async {
        if (request.method == 'PUT') {
          count = request;
          return http.Response('{}', 200);
        }
        if (request.url.path.endsWith('/prescriptions')) {
          return http.Response(
            '{"data":[{"id":"p1","medicationName":"Fixture"}]}',
            200,
          );
        }
        if (request.url.path.endsWith('/doses')) {
          return http.Response('{"data":[]}', 200);
        }
        if (request.url.path.endsWith('/refills')) {
          return http.Response('{"refills":[]}', 200);
        }
        if (request.url.path.contains('/inventory/')) {
          return http.Response('{"inventory":null}', 200);
        }
        return http.Response('{"preferences":{},"capabilities":{}}', 200);
      }),
    );
    await repository.loadSnapshot(from: from, to: to);
    await repository.updateInventory('p1', 0);
    final body = jsonDecode(count!.body);
    expect(body['quantity'], 0);
    expect(body.containsKey('revision'), isFalse);
    repository.dispose();
  });

  test(
    'a repeated receipt is not added twice and new plans require explicit choice',
    () async {
      final repository = ConsumerDemoRepository(now: () => now);
      await repository.updateRefill('demo-medication', RefillStage.received);
      await repository.reconcileReceipt(
        'demo-medication',
        quantity: 30,
        alreadyIncluded: false,
      );
      await repository.reconcileReceipt(
        'demo-medication',
        quantity: 30,
        alreadyIncluded: false,
      );
      var state = await repository.loadSnapshot(from: from, to: to);
      expect(state.inventory.single.quantity, 36);
      expect(state.inventory.single.receiptReconciled, isTrue);
      final oldId = state.inventory.single.refillId;
      await repository.updateRefill(
        'demo-medication',
        RefillStage.planning,
        startNew: true,
      );
      state = await repository.loadSnapshot(from: from, to: to);
      expect(state.inventory.single.refillId, isNot(oldId));
      expect(state.inventory.single.quantity, 36);
    },
  );

  test(
    'zero supply remains zero; unknown schedule never becomes a days estimate',
    () {
      const unknown = ConsumerInventory(prescriptionId: 'm', quantity: 0);
      const supported = ConsumerInventory(
        prescriptionId: 'm',
        quantity: 0,
        dailyUnits: 1,
      );
      expect(unknown.quantity, 0);
      expect(unknown.estimatedDays, isNull);
      expect(supported.estimatedDays, 0);
    },
  );

  test('a note and snooze never mark a sample occurrence taken', () async {
    final repository = ConsumerDemoRepository(now: () => now);
    final initial = await repository.loadSnapshot(from: from, to: to);
    final occurrence = initial.occurrences.firstWhere(
      (o) => o.scheduledFor.day == 15,
    );
    await repository.recordOccurrence(
      ConsumerOccurrenceUpdate(id: occurrence.id, note: 'Actual note'),
    );
    await repository.snoozeOccurrence(
      occurrence.id,
      const Duration(minutes: 15),
    );
    final changed = (await repository.loadSnapshot(
      from: from,
      to: to,
    )).occurrences.firstWhere((o) => o.id == occurrence.id);
    expect(changed.status, OccurrenceStatus.unconfirmed);
    expect(changed.note, 'Actual note');
    expect(changed.snoozedUntil, now.add(const Duration(minutes: 15)));
    expect(changed.recordedAt, isNull);
  });

  test(
    'phone consent is explicit and never inferred from live activity preference',
    () async {
      final repository = ConsumerDemoRepository(now: () => now);
      await expectLater(
        repository.saveReminderPreferences(
          const ConsumerReminderPreferences(callsEnabled: true),
        ),
        throwsA(isA<ConsumerRepositoryException>()),
      );
      await repository.saveReminderPreferences(
        const ConsumerReminderPreferences(liveActivitiesEnabled: true),
      );
      final state = await repository.loadSnapshot(from: from, to: to);
      expect(state.preferences.callsEnabled, isFalse);
    },
  );

  test(
    'refill receipt leaves inventory unchanged until an explicit count',
    () async {
      final repository = ConsumerDemoRepository(now: () => now);
      await repository.updateRefill('demo-medication', RefillStage.received);
      var state = await repository.loadSnapshot(from: from, to: to);
      expect(state.inventory.single.quantity, 6);
      await repository.updateInventory('demo-medication', 30);
      state = await repository.loadSnapshot(from: from, to: to);
      expect(state.inventory.single.quantity, 30);
    },
  );

  test(
    'authenticated note update sends no taken status and preserves revision',
    () async {
      late http.Request captured;
      final repository = ConsumerApiRepository(
        baseUrl: 'https://example.test/api',
        tokenProvider: () async => 'test-token',
        client: MockClient((request) async {
          captured = request;
          return http.Response('{"data":{}}', 200);
        }),
      );
      await repository.recordOccurrence(
        const ConsumerOccurrenceUpdate(
          id: 'dose-1',
          note: 'My note',
          expectedRevision: 4,
        ),
      );
      expect(captured.method, 'PATCH');
      expect(captured.url.path, '/api/doses/dose-1');
      expect(captured.headers['Authorization'], 'Bearer test-token');
      expect(jsonDecode(captured.body), {
        'note': 'My note',
        'expectedRevision': 4,
      });
      repository.dispose();
    },
  );

  test(
    'expired session clears loaded data instead of replacing it with fixtures',
    () async {
      var expires = false;
      final repository = ConsumerApiRepository(
        baseUrl: 'https://example.test/api',
        tokenProvider: () async => 'test-token',
        tokenInvalidator:
            (_) async => throw StateError('Secure cleanup is unavailable'),
        client: MockClient((request) async {
          if (expires) return http.Response('{}', 401);
          if (request.url.path.endsWith('/prescriptions')) {
            return http.Response('{"data":[]}', 200);
          }
          if (request.url.path.endsWith('/doses')) {
            return http.Response('{"data":[]}', 200);
          }
          if (request.url.path.endsWith('/refills')) {
            return http.Response('{"refills":[]}', 200);
          }
          return http.Response('{"preferences":{},"capabilities":{}}', 200);
        }),
      );
      final controller = ConsumerController(repository, now: () => now);
      await controller.load();
      expect(controller.snapshot, isNotNull);
      expect(controller.snapshot!.prescriptions, isEmpty);
      expect(controller.repository.isDemo, isFalse);
      expires = true;
      await controller.load();
      expect(controller.sessionExpired, isTrue);
      expect(controller.snapshot, isNull);
      expect(controller.error, contains('cleanup could not be completed'));
      controller.dispose();
    },
  );

  test(
    'optional service failure is visible and does not hide real prescriptions',
    () async {
      final repository = ConsumerApiRepository(
        baseUrl: 'https://example.test/api',
        tokenProvider: () async => 'token',
        client: MockClient((request) async {
          if (request.url.path.endsWith('/prescriptions')) {
            return http.Response(
              jsonEncode({
                'data': [
                  {
                    'id': 'p1',
                    'medicationName': 'Real test fixture',
                    'dosageInstructions': null,
                    'labelReviewed': false,
                    'schedules': [
                      {
                        'version': 1,
                        'endedAt': '2026-01-01',
                        'times': ['08:00'],
                      },
                      {
                        'version': 2,
                        'endedAt': null,
                        'times': ['10:00'],
                        'timezone': 'UTC',
                      },
                    ],
                  },
                ],
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/doses')) {
            return http.Response('{"data":[]}', 200);
          }
          return http.Response('{}', 503);
        }),
      );
      final state = await repository.loadSnapshot(from: from, to: to);
      expect(state.prescriptions.single.times, ['10:00']);
      expect(state.prescriptions.single.directions, isNull);
      expect(state.warnings, isNotEmpty);
      expect(state.capabilities.voiceEnabled, isFalse);
      expect(state.capabilities.inventoryEnabled, isFalse);
      expect(state.inventory.single.quantity, isNull);
      repository.dispose();
    },
  );
}
