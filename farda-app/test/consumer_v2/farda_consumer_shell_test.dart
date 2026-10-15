import 'package:farda/consumer_v2/farda_consumer_shell.dart';
import 'package:farda/consumer_v2/screens/you/farda_you_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpShell(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(home: FardaConsumerShell()),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('switches between the four consumer tabs', (tester) async {
    await pumpShell(tester);

    expect(find.byType(FardaConsumerNavigationBar), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Calendar'), findsOneWidget);
    expect(find.text('Refills'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);

    await tester.tap(find.text('You'));
    await tester.pumpAndSettle();

    expect(find.text('A little\nmore you.'), findsOneWidget);
    expect(find.byKey(FardaYouKeys.routineLink), findsOneWidget);
  });

  testWidgets('hides app navigation during native-surface previews', (
    tester,
  ) async {
    await pumpShell(tester);

    await tester.tap(find.text('You'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(FardaYouKeys.remindersLink));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(FardaYouKeys.liveActivityLink));
    await tester.tap(find.byKey(FardaYouKeys.liveActivityLink));
    await tester.pumpAndSettle();

    expect(find.byType(FardaConsumerNavigationBar), findsNothing);
    expect(find.text('Reminder settings'), findsOneWidget);

    await tester.tap(find.text('Reminder settings'));
    await tester.pumpAndSettle();

    expect(find.byType(FardaConsumerNavigationBar), findsOneWidget);
  });
}
