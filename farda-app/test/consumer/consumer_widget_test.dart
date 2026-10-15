import 'package:farda/features/consumer/consumer_app.dart';
import 'package:farda/features/consumer/consumer_controller.dart';
import 'package:farda/features/consumer/data/consumer_demo_repository.dart';
import 'package:farda/features/consumer/data/consumer_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ConsumerController> mountApp(
  WidgetTester tester, {
  double scale = 1,
  Size size = const Size(390, 844),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  late ConsumerController controller;
  await tester.pumpWidget(
    MaterialApp(
      builder:
          (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
      home: ConsumerApp(
        repository: ConsumerDemoRepository(),
        onControllerReady: (value) => controller = value,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader =
        FontLoader('Outfit')
          ..addFont(rootBundle.load('assets/fonts/Outfit-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Outfit-SemiBold.ttf'));
    await loader.load();
  });
  testWidgets(
    'logging opens an explicit check-in and does not mutate on open or dismiss',
    (tester) async {
      final controller = await mountApp(tester);
      expect(
        find.text('DEMO · Sample data · No calls or pharmacy requests'),
        findsOneWidget,
      );
      final occurrence = controller.nextOccurrence!;
      await tester.ensureVisible(find.text('Log my dose'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Log my dose'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm: I already took it'), findsOneWidget);
      expect(controller.nextOccurrence!.status, OccurrenceStatus.unconfirmed);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(controller.nextOccurrence!.id, occurrence.id);
      expect(controller.nextOccurrence!.status, OccurrenceStatus.unconfirmed);
    },
  );

  testWidgets('a note-only form saves note without a dose status', (
    tester,
  ) async {
    final controller = await mountApp(tester);
    await tester.ensureVisible(find.text('Add a note without logging'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add a note without logging'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).first,
      'A note I actually wrote',
    );
    await tester.ensureVisible(find.text('Save note only'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save note only'));
    await tester.pumpAndSettle();
    expect(controller.nextOccurrence!.note, 'A note I actually wrote');
    expect(controller.nextOccurrence!.status, OccurrenceStatus.unconfirmed);
  });

  testWidgets('calendar month navigation and selected-day agenda work', (
    tester,
  ) async {
    final controller = await mountApp(tester);
    await tester.tap(find.text('Calendar').last);
    await tester.pumpAndSettle();
    final oldMonth = controller.visibleMonth;
    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
    expect(
      controller.visibleMonth,
      DateTime(oldMonth.year, oldMonth.month + 1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('320px handset and 200 percent text support every primary tab', (
    tester,
  ) async {
    await mountApp(tester, scale: 2, size: const Size(320, 700));
    expect(tester.takeException(), isNull);
    for (final label in ['Calendar', 'Refills', 'You', 'Today']) {
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: '$label must fit at large text',
      );
    }
  });

  testWidgets('refill planning never implies an order or changes stock', (
    tester,
  ) async {
    final controller = await mountApp(tester);
    await tester.tap(find.text('Refills').last);
    await tester.pumpAndSettle();
    final before = controller.snapshot!.inventory.single.quantity;
    await tester.ensureVisible(find.text('Plan my refill'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plan my refill'));
    await tester.pumpAndSettle();
    expect(controller.snapshot!.inventory.single.refillId, isNotNull);
    expect(controller.snapshot!.inventory.single.stage, RefillStage.planning);
    expect(controller.snapshot!.inventory.single.quantity, before);
  });
}
