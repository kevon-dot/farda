import 'package:farda/features/consumer/consumer_entry.dart';
import 'package:farda/features/consumer/data/consumer_demo_repository.dart';
import 'package:farda/routes/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  test('consumer routes retain the integrated app and v2 preview paths', () {
    expect(CustomRoutePaths.dashboard, '/dashboard');
    expect(CustomRoutePaths.consumer, '/consumer');
    expect(CustomRoutePaths.consumerDemo, '/consumer/demo');
    expect(CustomRoutePaths.consumerV2, '/consumer/v2');
    expect(CustomRoutePaths.consumerV2Today, '/consumer/v2/today');
    expect(CustomRoutePaths.signedInHome, CustomRoutePaths.consumerV2Today);
    expect(CustomRoutePaths.accountTools, '/dashboard?tab=you');
    expect(CustomRoutePaths.refillTools, '/dashboard?tab=refills');
    expect(CustomRoutePaths.signedInHome, isNot(CustomRoutePaths.dashboard));
    expect(CustomRoutePaths.consumerV2Calendar, '/consumer/v2/calendar');
    expect(CustomRoutePaths.consumerV2Refills, '/consumer/v2/refills');
    expect(CustomRoutePaths.consumerV2You, '/consumer/v2/you');
    expect(
      CustomRoutePaths.consumerV2TabPath(0),
      CustomRoutePaths.consumerV2Today,
    );
    expect(
      CustomRoutePaths.consumerV2TabPath(3),
      CustomRoutePaths.consumerV2You,
    );
    expect(CustomRoutePaths.home, '/home');
    expect(CustomRoutePaths.plan, '/plan');
    expect(CustomRoutePaths.calendar, '/calendar');
    expect(CustomRoutePaths.more, '/more');
  });

  testWidgets('account tools provide a route back to the signed-in Today view',
      (tester) async {
    final router = GoRouter(
      initialLocation: CustomRoutePaths.accountTools,
      routes: [
        GoRoute(
          path: CustomRoutePaths.dashboard,
          builder: (_, __) =>
              ConsumerEntry(repository: ConsumerDemoRepository()),
        ),
        GoRoute(
          path: CustomRoutePaths.signedInHome,
          builder: (_, __) => const Scaffold(body: Text('Figma Today')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Back to Today'));
    await tester.pumpAndSettle();

    expect(
      router.routeInformationProvider.value.uri.path,
      CustomRoutePaths.signedInHome,
    );
    expect(find.text('Figma Today'), findsOneWidget);
  });
}
