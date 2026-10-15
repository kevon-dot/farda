import 'dart:io';

import 'package:farda/features/consumer/consumer_controller.dart';
import 'package:farda/features/consumer/data/consumer_demo_repository.dart';
import 'package:farda/features/consumer/data/label_scan.dart';
import 'package:farda/features/consumer/prescription_onboarding.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _exportVisuals = bool.fromEnvironment('UPDATE_VISUALS');

Future<void> _tap(WidgetTester tester, String label) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text(label).last);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [390.0, 320.0]) {
    testWidgets('prescription flow frames at $width', (tester) async {
      final fonts = FontLoader('Outfit');
      for (final weight in ['Light', 'Regular', 'Medium', 'SemiBold', 'Bold']) {
        fonts.addFont(rootBundle.load('assets/fonts/Outfit-$weight.ttf'));
      }
      await fonts.load();
      final flutterRoot = Platform.environment['FLUTTER_ROOT']!;
      final bytes =
          File(
            '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          ).readAsBytesSync();
      await (FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = ConsumerController(
        ConsumerDemoRepository(),
        now: () => DateTime(2026, 10, 15, 8),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'Outfit'),
          builder:
              (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  padding: const EdgeInsets.only(top: 48, bottom: 20),
                  viewPadding: const EdgeInsets.only(top: 48, bottom: 20),
                  textScaler: TextScaler.linear(width == 320 ? 1.3 : 1),
                ),
                child: child!,
              ),
          home: PrescriptionOnboarding(
            controller: controller,
            scanLabel: (_) async => const LabelScanDraft(manualEntry: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> frame(String name) async {
        expect(tester.takeException(), isNull);
        if (_exportVisuals) {
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(
              'goldens/onboarding-$name-${width.toInt()}${width == 320 ? '-large-text' : ''}.png',
            ),
          );
        }
      }

      await frame('welcome');
      await _tap(tester, 'Enter manually');
      await tester.enterText(
        find.byType(TextField).first,
        'Example medication 10 mg tablets',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await frame('name');
      await _tap(tester, 'Continue');
      await tester.enterText(
        find.byType(TextField).first,
        'Copy every instruction exactly as it appears on your prescription label, including text around the bottle. This is sample text for the interface preview.',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await frame('directions');
      await _tap(tester, 'Continue');
      await tester.enterText(find.byType(TextField).first, 'Your pharmacy');
      await tester.enterText(find.byType(TextField).last, 'EXAMPLE-104');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await frame('pharmacy');
      await _tap(tester, 'Continue');
      await frame('schedule-choice');
      await _tap(tester, 'No daily reminders');
      await frame('no-reminders');
      await _tap(tester, 'Review my routine');
      await frame('review');
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await _tap(tester, 'Save my routine');
      await frame('saved');
    });
  }
}
