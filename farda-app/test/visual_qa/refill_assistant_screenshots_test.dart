import 'dart:io';

import 'package:farda/consumer_v2/screens/refills/refills_handoff_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Export actual Flutter renders only on explicit visual-QA runs. Normal CI
// exercises the same layouts and interactions without date/pixel baselines.
const _exportVisuals = bool.fromEnvironment('UPDATE_VISUALS');

Future<void> _capture(WidgetTester tester, String name) async {
  expect(tester.takeException(), isNull);
  if (!_exportVisuals) return;
  try {
    debugDisableShadows = false;
    await tester.pump();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/$name.png'),
    );
  } finally {
    debugDisableShadows = true;
  }
}

void main() {
  for (final narrow in [false, true]) {
    testWidgets('${narrow ? 320 : 390} refill assistant and editable request', (
      tester,
    ) async {
      final fonts = FontLoader('Outfit');
      for (final weight in ['Light', 'Regular', 'Medium', 'SemiBold', 'Bold']) {
        fonts.addFont(rootBundle.load('assets/fonts/Outfit-$weight.ttf'));
      }
      await fonts.load();
      final flutterRoot = Platform.environment['FLUTTER_ROOT']!;
      final iconBytes =
          File(
            '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          ).readAsBytesSync();
      await (FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.sublistView(iconBytes)))).load();
      tester.view.physicalSize = Size(narrow ? 320 : 390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'Outfit'),
          builder:
              (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  padding: const EdgeInsets.only(top: 48, bottom: 20),
                  viewPadding: const EdgeInsets.only(top: 48, bottom: 20),
                  textScaler: TextScaler.linear(narrow ? 1.3 : 1),
                ),
                child: child!,
              ),
          home: RefillsHandoffScreen(
            medicationName: 'Daily medication · extended release',
            rxLabel: 'Saved by you',
            rxNumber: 'RX48210012',
            directions:
                'Follow the directions on your prescription label. Check with your pharmacy if any wording is unclear.',
            pharmacy: 'Your community pharmacy',
            actionLabel: 'Save my refill plan',
            onSavePlan: () async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final prefix = narrow ? '320-large-text' : '390';
      await _capture(tester, '$prefix-refill-assistant');
      await tester.scrollUntilVisible(
        find.text('Review refill request'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await _capture(tester, '$prefix-refill-assistant-actions');
      await tester.tap(find.text('Review refill request'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('refill-request-text')), findsOneWidget);
      expect(find.byKey(const Key('refill-copy-request')), findsOneWidget);
      await _capture(tester, '$prefix-refill-request-review');
    });
  }
}
