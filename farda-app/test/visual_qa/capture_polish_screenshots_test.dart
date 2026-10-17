import 'dart:io';

import 'package:farda/features/consumer/consumer_controller.dart';
import 'package:farda/features/consumer/data/consumer_demo_repository.dart';
import 'package:farda/features/consumer/data/consumer_models.dart';
import 'package:farda/features/consumer/data/label_scan.dart';
import 'package:farda/features/consumer/guided_label_capture.dart';
import 'package:farda/features/consumer/prescription_onboarding.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _exportVisuals = bool.fromEnvironment('UPDATE_VISUALS');

void main() {
  for (final width in [390.0, 320.0]) {
    testWidgets('capture guidance and missing fields at $width', (
      tester,
    ) async {
      final fonts = FontLoader('Outfit');
      for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
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
      final controller = ConsumerController(ConsumerDemoRepository());
      addTearDown(controller.dispose);
      Widget app(Widget child) => MaterialApp(
        debugShowCheckedModeBanner: false,
        builder:
            (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                padding: const EdgeInsets.only(top: 48, bottom: 20),
                textScaler: TextScaler.linear(width == 320 ? 1.3 : 1),
              ),
              child: child!,
            ),
        home: child,
      );
      Future<void> frame(String name) async {
        expect(tester.takeException(), isNull);
        if (_exportVisuals) {
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('goldens/capture-$name-${width.toInt()}.png'),
          );
        }
      }

      await tester.pumpWidget(
        app(
          PrescriptionOnboarding(
            controller: controller,
            scanLabel:
                (_) async =>
                    const LabelScanDraft(medicationName: 'Example label name'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Scan label'));
      await tester.tap(find.text('Scan label'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await frame('missing-directions');
      await controller.mutate(() async {
        throw const ConsumerRepositoryException(
          'Sign in again',
          sessionExpired: true,
        );
      });
      await tester.pumpAndSettle();
      await frame('session-ended');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/camera'),
        (_) async => <Object>[],
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/camera'),
          null,
        ),
      );
      await tester.pumpWidget(app(const LabelViewfinderScreen(photoNumber: 2)));
      await tester.pumpAndSettle();
      await frame('camera-guidance');
      await tester.scrollUntilVisible(find.text('Enter manually instead'), 180);
      await frame('camera-fallback');
    });
  }
}
