import 'package:farda/application/authentication/storage/auth_storage.dart';
import 'package:farda/consumer_v2/screens/refills/refills_handoff_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final clipboard = <String>[];
  var copyFails = false;
  var saves = 0;
  var saveFails = false;

  setUp(() {
    clipboard.clear();
    copyFails = false;
    saves = 0;
    saveFails = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            if (copyFails) throw PlatformException(code: 'unavailable');
            clipboard.add((call.arguments as Map)['text'] as String);
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> pump(WidgetTester tester, {bool narrow = false}) async {
    tester.view.physicalSize = Size(narrow ? 320 : 390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder:
            (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(narrow ? 1.3 : 1)),
              child: child!,
            ),
        home: RefillsHandoffScreen(
          medicationName:
              'A very long medication name with an extended release formulation',
          rxLabel: 'Saved by you',
          rxNumber: 'RX987654321012345678901234567890',
          directions:
              'Take exactly as directed on your prescription label. This saved instruction spans several lines so all of it must stay readable.',
          pharmacy: 'A long community pharmacy name on Market Street',
          actionLabel: 'Save my refill plan',
          onSavePlan: () async {
            saves++;
            return saveFails ? 'Plan unavailable. Please try again.' : null;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> review(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.text('Review refill request'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Review refill request'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review refill request'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'account change hides the whole private handoff and dismisses review',
    (tester) async {
      await pump(tester);
      expect(find.text('CHECK YOUR LABEL'), findsOneWidget);
      await review(tester);
      AuthStorage.sessionRevision.value++;
      await tester.pumpAndSettle();
      expect(find.text('CHECK YOUR LABEL'), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        find.text(
          'Your account session changed. Return to your routine to continue.',
        ),
        findsOneWidget,
      );
      expect(clipboard, isEmpty);
    },
  );

  testWidgets(
    'review edits copy only after an explicit tap, never saves a stage',
    (tester) async {
      await pump(tester);
      expect(clipboard, isEmpty);
      await review(tester);
      expect(clipboard, isEmpty);
      final input = find.byKey(const Key('refill-request-text'));
      final original = tester.widget<TextField>(input).controller!.text;
      expect(original, contains('RX987654321012345678901234567890'));
      expect(original, contains('A long community pharmacy name'));
      expect(original, contains('Directions on my saved label:'));
      await tester.enterText(
        input,
        'My reviewed request. Please confirm availability.',
      );
      await tester.tap(find.byKey(const Key('refill-copy-request')));
      await tester.pumpAndSettle();
      expect(clipboard, ['My reviewed request. Please confirm availability.']);
      expect(find.text('Copied. Nothing has been sent.'), findsOneWidget);
      expect(saves, 0);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      await review(tester);
      expect(
        tester.widget<TextField>(input).controller!.text,
        'My reviewed request. Please confirm availability.',
      );
      expect(clipboard.length, 1);
    },
  );

  testWidgets('clipboard errors preserve text and allow retry', (tester) async {
    await pump(tester);
    await review(tester);
    copyFails = true;
    await tester.tap(find.byKey(const Key('refill-copy-request')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not copy.'), findsOneWidget);
    expect(clipboard, isEmpty);
    expect(saves, 0);
    copyFails = false;
    await tester.tap(find.byKey(const Key('refill-copy-request')));
    await tester.pumpAndSettle();
    expect(clipboard.length, 1);
    expect(find.text('Copied. Nothing has been sent.'), findsOneWidget);
  });

  testWidgets('empty request cannot be copied and plan failures retain retry', (
    tester,
  ) async {
    await pump(tester);
    await review(tester);
    await tester.enterText(find.byKey(const Key('refill-request-text')), ' ');
    await tester.tap(find.byKey(const Key('refill-copy-request')));
    await tester.pumpAndSettle();
    expect(find.text('Add a message before copying.'), findsOneWidget);
    expect(clipboard, isEmpty);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    saveFails = true;
    await tester.scrollUntilVisible(
      find.byKey(const Key('refill-save-plan')),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('refill-save-plan')));
    await tester.pumpAndSettle();
    expect(saves, 1);
    expect(find.text('Plan unavailable. Please try again.'), findsOneWidget);
    expect(find.text('Save my refill plan'), findsOneWidget);
    expect(clipboard, isEmpty);
  });

  testWidgets('long label details and review stay readable at 320px / 1.3', (
    tester,
  ) async {
    await pump(tester, narrow: true);
    final medication = tester.widget<Text>(
      find.text(
        'A very long medication name with an extended release formulation',
      ),
    );
    expect(medication.maxLines, isNull);
    expect(medication.overflow, isNot(TextOverflow.ellipsis));
    expect(tester.takeException(), isNull);
    await review(tester);
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byKey(const Key('refill-copy-request'))).height,
      greaterThanOrEqualTo(44),
    );
    await tester.tap(find.byKey(const Key('refill-copy-request')));
    await tester.pumpAndSettle();
    expect(clipboard.single, contains('all of it must stay readable.'));
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
