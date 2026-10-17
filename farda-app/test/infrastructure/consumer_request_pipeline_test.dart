import 'dart:async';
import 'dart:convert';

import 'package:farda/features/consumer/consumer_controller.dart';
import 'package:farda/features/consumer/data/consumer_api_repository.dart';
import 'package:farda/features/consumer/data/consumer_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  http.Response snapshotResponse(http.Request request) {
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
  }

  test('distant startup windows share identical in-flight reads', () async {
    final calls = <String, int>{};
    final repository = ConsumerApiRepository(
      baseUrl: 'https://example.test/api',
      tokenProvider: () async => 'account-a',
      client: MockClient((request) async {
        calls.update(request.url.path, (value) => value + 1, ifAbsent: () => 1);
        await Future<void>.delayed(Duration.zero);
        return snapshotResponse(request);
      }),
    );
    final controller = ConsumerController(
      repository,
      now: () => DateTime(2026, 10, 15),
    )..visibleMonth = DateTime(2026, 3);

    await controller.load();

    expect(calls['/api/prescriptions'], 1);
    expect(calls['/api/reminders/preferences'], 1);
    expect(calls['/api/refills'], 1);
    expect(calls['/api/doses'], 2);
    expect(calls.values.fold<int>(0, (sum, value) => sum + value), 5);
    controller.dispose();
  });

  test('concurrent identical reads use one HTTP request', () async {
    final response = Completer<http.Response>();
    var calls = 0;
    final repository = ConsumerApiRepository(
      baseUrl: 'https://example.test/api',
      tokenProvider: () async => 'account-a',
      client: MockClient((_) {
        calls++;
        return response.future;
      }),
    );

    final first = repository.loadBillingStatus();
    final second = repository.loadBillingStatus();
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
    response.complete(http.Response('{"tier":"plus"}', 200));

    expect((await first).tier, 'plus');
    expect((await second).tier, 'plus');
    repository.dispose();
  });

  test('read cache expires and never exceeds its LRU bound', () async {
    var now = DateTime.utc(2026, 10, 17);
    var calls = 0;
    final repository = ConsumerApiRepository(
      baseUrl: 'https://example.test/api',
      tokenProvider: () async => 'account-a',
      readCacheTtl: const Duration(seconds: 5),
      maxReadCacheEntries: 1,
      clock: () => now,
      client: MockClient((request) async {
        calls++;
        if (request.url.path.endsWith('/billing/catalog')) {
          return http.Response('{"plans":[]}', 200);
        }
        return http.Response('{"data":[]}', 200);
      }),
    );

    await repository.loadBillingCatalog();
    await repository.loadPharmacyDirectory();
    await repository.loadBillingCatalog(); // catalog was evicted
    expect(calls, 3);

    now = now.add(const Duration(seconds: 6));
    await repository.loadBillingCatalog();
    expect(calls, 4);
    repository.dispose();
  });

  test('session changes cannot reuse another account cache', () async {
    var token = 'account-a';
    var calls = 0;
    final repository = ConsumerApiRepository(
      baseUrl: 'https://example.test/api',
      tokenProvider: () async => token,
      client: MockClient((_) async {
        calls++;
        return http.Response(
          jsonEncode({
            'plans': [
              {'tier': token, 'prices': []},
            ],
          }),
          200,
        );
      }),
    );

    expect(
      (await repository.loadBillingCatalog()).plans.single.tier,
      'account-a',
    );
    token = 'account-b';
    expect(
      (await repository.loadBillingCatalog()).plans.single.tier,
      'account-b',
    );
    await repository.loadBillingCatalog();
    expect(calls, 2);
    repository.dispose();
  });

  test('failed responses are never cached', () async {
    var calls = 0;
    final repository = ConsumerApiRepository(
      baseUrl: 'https://example.test/api',
      tokenProvider: () async => 'account-a',
      client: MockClient((_) async {
        calls++;
        return calls == 1
            ? http.Response('{"error":"unavailable"}', 503)
            : http.Response('{"plans":[]}', 200);
      }),
    );

    await expectLater(
      repository.loadBillingCatalog(),
      throwsA(isA<ConsumerRepositoryException>()),
    );
    expect((await repository.loadBillingCatalog()).plans, isEmpty);
    expect(calls, 2);
    repository.dispose();
  });

  test(
    'a confirmed write prevents an older read from becoming current',
    () async {
      final staleResponse = Completer<http.Response>();
      var catalogCalls = 0;
      var allCalls = 0;
      final repository = ConsumerApiRepository(
        baseUrl: 'https://example.test/api',
        tokenProvider: () async => 'account-a',
        client: MockClient((request) async {
          allCalls++;
          if (request.url.path.endsWith('/billing/catalog')) {
            catalogCalls++;
            if (catalogCalls == 1) return staleResponse.future;
            return http.Response(
              '{"plans":[{"tier":"current","prices":[]}]}',
              200,
            );
          }
          return http.Response(
            '{"url":"https://billing.stripe.com/session"}',
            200,
          );
        }),
      );

      final loading = repository.loadBillingCatalog();
      await Future<void>.delayed(Duration.zero);
      await repository.createBillingPortal(
        Uri.parse('https://farda.example/return'),
      );
      staleResponse.complete(
        http.Response('{"plans":[{"tier":"stale","prices":[]}]}', 200),
      );

      expect((await loading).plans.single.tier, 'current');
      expect(catalogCalls, 2);
      expect(allCalls, 3);
      repository.dispose();
    },
  );

  test('offline reads and writes stay within a single attempt', () async {
    var calls = 0;
    final repository = ConsumerApiRepository(
      baseUrl: 'https://example.test/api',
      tokenProvider: () async => 'account-a',
      client: MockClient((_) async {
        calls++;
        throw http.ClientException('offline');
      }),
    );

    await expectLater(
      repository.loadBillingCatalog(),
      throwsA(isA<ConsumerRepositoryException>()),
    );
    await expectLater(
      repository.createBillingPortal(Uri.parse('https://farda.example/return')),
      throwsA(isA<ConsumerRepositoryException>()),
    );
    expect(calls, 2);
    repository.dispose();
  });

  test('dispose prevents an in-flight response from being published', () async {
    final response = Completer<http.Response>();
    final repository = ConsumerApiRepository(
      baseUrl: 'https://example.test/api',
      tokenProvider: () async => 'account-a',
      client: MockClient((_) => response.future),
    );

    final loading = repository.loadBillingCatalog();
    await Future<void>.delayed(Duration.zero);
    repository.dispose();
    response.complete(http.Response('{"plans":[]}', 200));

    await expectLater(
      loading,
      throwsA(
        isA<ConsumerRepositoryException>().having(
          (error) => error.message,
          'message',
          contains('cancelled'),
        ),
      ),
    );
  });

  test(
    'pinned old-account logout cannot corrupt a concurrent current read',
    () async {
      final firstRead = Completer<http.Response>();
      final readStarted = Completer<void>();
      var readCalls = 0;
      final authorizations = <String?>[];
      final repository = ConsumerApiRepository(
        baseUrl: 'https://example.test/api',
        tokenProvider: () async => 'account-b',
        client: MockClient((request) async {
          authorizations.add(request.headers['Authorization']);
          if (request.url.path.endsWith('/billing/status')) {
            readCalls++;
            if (readCalls == 1) {
              readStarted.complete();
              return firstRead.future;
            }
            return http.Response('{"tier":"plus"}', 200);
          }
          expect(request.url.path, '/api/auth/sign-out');
          return http.Response('{}', 200);
        }),
      );

      final reading = repository.loadBillingStatus();
      await readStarted.future;
      expect(await repository.signOut('account-a'), isFalse);
      firstRead.complete(http.Response('{"tier":"stale"}', 200));

      expect((await reading).tier, 'plus');
      expect(readCalls, 2);
      expect(authorizations, [
        'Bearer account-b',
        'Bearer account-a',
        'Bearer account-b',
      ]);
      expect((await repository.loadBillingStatus()).tier, 'plus');
      repository.dispose();
    },
  );
}
