import 'dart:io';
import 'package:farda/features/consumer/consumer_controller.dart';
import 'package:farda/features/consumer/data/consumer_demo_repository.dart';
import 'package:farda/features/consumer/data/label_scan.dart';
import 'package:farda/features/consumer/guided_label_capture.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _exportVisuals = bool.fromEnvironment('UPDATE_VISUALS');
void main() {
  for (final width in [390.0, 320.0]) {
    testWidgets('label capture at $width', (tester) async {
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
      final photo = LabelPhoto(
        bytes: File('test/fixtures/label-photo.png').readAsBytesSync(),
        mimeType: 'image/png',
      );
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          builder:
              (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  padding: const EdgeInsets.only(top: 48, bottom: 20),
                  viewPadding: const EdgeInsets.only(top: 48, bottom: 20),
                  textScaler: TextScaler.linear(width == 320 ? 1.3 : 1),
                ),
                child: child!,
              ),
          home: GuidedLabelCaptureScreen(
            controller: controller,
            takePhoto: (_) async => photo,
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> frame(String name) async {
        expect(tester.takeException(), isNull);
        if (_exportVisuals) {
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('goldens/label-$name-${width.toInt()}.png'),
          );
        }
      }

      await frame('intro');
      await tester.scrollUntilVisible(find.text('Take first photo'), 160);
      await tester.tap(find.text('Take first photo'));
      await tester.pumpAndSettle();
      await tester.runAsync(() => precacheImage(MemoryImage(photo.bytes), tester.element(find.byType(GuidedLabelCaptureScreen))));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, 900));
      await tester.pumpAndSettle();
      await frame('photos');
      await tester.scrollUntilVisible(find.text('Enter manually instead'), 160);
      await frame('coverage');
    });
  }
}
