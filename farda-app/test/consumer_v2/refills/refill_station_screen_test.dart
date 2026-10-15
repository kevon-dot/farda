import 'package:farda/consumer_v2/screens/refills/refill_station_screen.dart';
import 'package:farda/consumer_v2/screens/refills/refill_station_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'preview matches the refill summary and keeps the handoff explicit',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = RefillStationController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(home: RefillStationScreen(controller: controller)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Refill, with less rush.'), findsOneWidget);
      expect(find.text('6'), findsOneWidget);
      expect(find.text('Daily medication'), findsOneWidget);
      expect(find.text('Plan my refill'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Plan my refill'));
      await tester.pumpAndSettle();
      expect(find.text('Let’s get\nyou ready.'), findsOneWidget);
      expect(find.textContaining('No refill order is submitted.'), findsOneWidget);
      expect(controller.state.stage, RefillJourneyStage.planAhead);

      await tester.ensureVisible(find.text('Prepare pharmacy handoff'));
      await tester.tap(find.text('Prepare pharmacy handoff'));
      await tester.pumpAndSettle();
      expect(controller.state.stage, RefillJourneyStage.handoffPrepared);
      expect(find.text('I contacted my pharmacy'), findsOneWidget);
    },
  );

  testWidgets('preview remains usable at 320 px and larger text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 844),
          ).copyWith(textScaler: const TextScaler.linear(1.3)),
          child: const RefillStationScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Plan my refill'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Plan my refill'));
    await tester.tap(find.text('Plan my refill'));
    await tester.pumpAndSettle();
    expect(find.text('Let’s get\nyou ready.'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('No refill order is submitted.'),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.textContaining('No refill order is submitted.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
