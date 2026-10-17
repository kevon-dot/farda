import 'dart:io';

import 'package:farda/consumer_v2/screens/today/farda_today_screen.dart';
import 'package:farda/consumer_v2/screens/today/today_routine_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _loadFonts() async {
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
  final icons = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(iconBytes)));
  await icons.load();
}

void main() {
  Future<void> pumpToday(
    WidgetTester tester, {
    int savedMinute = 0,
    double width = 390,
    double textScale = 1,
  }) async {
    await _loadFonts();
    debugDisableShadows = false;
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) {
          final media = MediaQuery.of(context);
          return MediaQuery(
            data: media.copyWith(
              padding: const EdgeInsets.only(top: 48, bottom: 20),
              viewPadding: const EdgeInsets.only(top: 48, bottom: 20),
              textScaler: TextScaler.linear(textScale),
            ),
            child: child!,
          );
        },
        home: FardaTodayScreen(
          initialDate: DateTime(2026, 10, 14),
          receiptClock: () => DateTime(2026, 10, 14, 9, savedMinute),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Today pending Figma reference', (tester) async {
    await pumpToday(tester);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(FardaTodayScreen),
      matchesGoldenFile('goldens/today-pending-390.png'),
    );
    debugDisableShadows = true;
  });

  testWidgets('Today pending remains readable at 320 with larger text', (
    tester,
  ) async {
    await pumpToday(tester, width: 320, textScale: 1.6);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(FardaTodayScreen),
      matchesGoldenFile('goldens/today-pending-320-large-text.png'),
    );
    await tester.ensureVisible(
      find.byKey(FardaTodayRoutineCard.snoozeButtonKey),
    );
    await tester.tap(find.byKey(FardaTodayRoutineCard.snoozeButtonKey));
    await tester.pumpAndSettle();
    expect(
      find.text('Reminder snoozed. Your record is unconfirmed.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    debugDisableShadows = true;
  });

  testWidgets('Today confirmed receipt after explicit check-in', (
    tester,
  ) async {
    await pumpToday(tester, savedMinute: 4);
    await tester.ensureVisible(
      find.byKey(FardaTodayRoutineCard.logDoseButtonKey),
    );
    await tester.tap(find.byKey(FardaTodayRoutineCard.logDoseButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(FardaTodayScreen.confirmDoseButtonKey));
    await tester.pumpAndSettle();
    expect(find.text('You’re all set.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(FardaTodayScreen),
      matchesGoldenFile('goldens/today-confirmed-390.png'),
    );
    debugDisableShadows = true;
  });

  testWidgets('Today full-screen check-in reference', (tester) async {
    await pumpToday(tester);
    await tester.ensureVisible(
      find.byKey(FardaTodayRoutineCard.logDoseButtonKey),
    );
    await tester.tap(find.byKey(FardaTodayRoutineCard.logDoseButtonKey));
    await tester.pumpAndSettle();
    expect(find.text('Your record.\nYour choice.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(FardaTodayScreen),
      matchesGoldenFile('goldens/today-checkin-390.png'),
    );
    debugDisableShadows = true;
  });

  testWidgets('Today snoozed receipt stays unconfirmed', (tester) async {
    await pumpToday(tester);
    await tester.ensureVisible(
      find.byKey(FardaTodayRoutineCard.snoozeButtonKey),
    );
    await tester.tap(find.byKey(FardaTodayRoutineCard.snoozeButtonKey));
    await tester.pumpAndSettle();
    expect(
      find.text('Reminder snoozed. Your record is unconfirmed.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(FardaTodayScreen),
      matchesGoldenFile('goldens/today-snoozed-390.png'),
    );
    debugDisableShadows = true;
  });

  testWidgets('Today check-in is usable at 320 with larger text', (
    tester,
  ) async {
    await pumpToday(tester, width: 320, textScale: 1.3);
    await tester.ensureVisible(
      find.byKey(FardaTodayRoutineCard.logDoseButtonKey),
    );
    await tester.tap(find.byKey(FardaTodayRoutineCard.logDoseButtonKey));
    await tester.pumpAndSettle();
    expect(find.text('Your record.\nYour choice.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(FardaTodayScreen),
      matchesGoldenFile('goldens/today-checkin-320-large-text.png'),
    );
    debugDisableShadows = true;
  });
}
