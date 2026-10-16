import 'dart:io';
import 'dart:ui' as ui;
import 'package:farda/consumer_v2/screens/membership/farda_membership_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final onboarding in [false, true]) {
    testWidgets('render membership for design review: onboarding=$onboarding', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 1250);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final loader = FontLoader('Outfit')
        ..addFont(rootBundle.load('assets/fonts/Outfit-Regular.ttf'));
      await loader.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'Outfit'),
          home: RepaintBoundary(
            key: key,
            child: FardaMembershipScreen(
              initialTier: onboarding ? 'plus' : 'family',
              onboardingOffer: onboarding,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          onboarding
              ? 'test/visual_qa/goldens/390-membership-onboarding.png'
              : 'test/visual_qa/goldens/390-membership-family.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
      });
      expect(tester.takeException(), isNull);
    });
  }
}
