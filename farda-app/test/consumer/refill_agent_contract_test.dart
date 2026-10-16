import 'dart:convert';
import 'package:farda/features/consumer/data/consumer_api_repository.dart';
import 'package:farda/features/consumer/data/consumer_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'snapshot batches 25 inventories into four requests and preserves revisions',
    () async {
      final paths = <String>[];
      Map? update;
      final repository = ConsumerApiRepository(
        baseUrl: 'https://example.test/api',
        tokenProvider: () async => 'session',
        client: MockClient((request) async {
          paths.add(request.url.path);
          if (request.method == 'PUT') {
            update = jsonDecode(request.body) as Map;
            return http.Response('{}', 200);
          }
          final body = switch (request.url.path.split('/').last) {
            'prescriptions' => {
              'data': List.generate(
                25,
                (i) => {'id': 'p$i', 'medicationName': 'Fixture $i'},
              ),
            },
            'doses' => {'data': []},
            'preferences' => {'preferences': {}, 'capabilities': {}},
            'refills' => {
              'refills': [],
              'inventories': List.generate(
                25,
                (i) => {
                  'prescriptionId': 'p$i',
                  'inventory': {
                    'quantity': i,
                    'revision': 2,
                    'observedAt': '2026-10-16T00:00:00Z',
                    'stale': false,
                  },
                },
              ),
            },
            _ => throw StateError('Unexpected request'),
          };
          return http.Response(jsonEncode(body), 200);
        }),
      );
      final snapshot = await repository.loadSnapshot(
        from: DateTime(2026, 10, 1),
        to: DateTime(2026, 11, 1),
      );
      expect(paths.length, 4);
      expect(snapshot.inventory.length, 25);
      expect(snapshot.capabilities.inventoryEnabled, isTrue);
      expect(snapshot.inventory.last.quantity, 24);
      await repository.updateInventory('p24', 26);
      expect(update!['revision'], 2);
      repository.dispose();
    },
  );

  test(
    'unavailable inventory batch never implies zero or writable supply',
    () async {
      final repository = ConsumerApiRepository(
        baseUrl: 'https://example.test/api',
        tokenProvider: () async => 'session',
        client: MockClient((request) async {
          final body = switch (request.url.path.split('/').last) {
            'prescriptions' => {
              'data': [
                {'id': 'p1', 'medicationName': 'Fixture'},
              ],
            },
            'doses' => {'data': []},
            'preferences' => {'preferences': {}, 'capabilities': {}},
            'refills' => {'refills': []},
            _ => throw StateError('Unexpected per-medication request'),
          };
          return http.Response(jsonEncode(body), 200);
        }),
      );
      final snapshot = await repository.loadSnapshot(
        from: DateTime(2026, 10, 1),
        to: DateTime(2026, 11, 1),
      );
      expect(snapshot.capabilities.inventoryEnabled, isFalse);
      expect(snapshot.inventory.single.quantity, isNull);
      expect(
        snapshot.warnings,
        contains('Supply counts could not be refreshed.'),
      );
      repository.dispose();
    },
  );

  test(
    'provider request contracts send explicit consent and no arbitrary external identity',
    () async {
      final requests = <http.Request>[];
      final repository = ConsumerApiRepository(
        baseUrl: 'https://example.test/api',
        tokenProvider: () async => 'session',
        client: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode({
              'prescriptionId': 'p1',
              'provider': {'configured': false},
              'canSubmit': false,
            }),
            200,
          );
        }),
      );
      await repository.submitRefillAgent(
        'p1',
        reviewToken: 'review',
        idempotencyKey: 'request-key-1',
      );
      expect(requests.single.url.path, '/api/refills/agent/p1/submit');
      expect(jsonDecode(requests.single.body), {
        'reviewToken': 'review',
        'confirmed': true,
        'idempotencyKey': 'request-key-1',
      });
      expect(requests.single.followRedirects, isFalse);
      repository.dispose();
    },
  );

  test('account switch suppresses returned private provider review', () async {
    var token = 'old';
    final repository = ConsumerApiRepository(
      baseUrl: 'https://example.test/api',
      tokenProvider: () async => token,
      client: MockClient((request) async {
        token = 'new';
        return http.Response(
          '{"prescriptionId":"p1","provider":{},"canSubmit":false}',
          200,
        );
      }),
    );
    await expectLater(
      repository.loadRefillAgent('p1'),
      throwsA(
        isA<ConsumerRepositoryException>().having(
          (e) => e.sessionChanged,
          'changed session',
          true,
        ),
      ),
    );
    repository.dispose();
  });
}
