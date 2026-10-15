import 'package:farda/consumer_v2/screens/today/farda_companion.dart';
import 'package:farda/consumer_v2/screens/today/today_models.dart';
import 'package:farda/consumer_v2/screens/today/today_routine_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpCard(
    WidgetTester tester, {
    TodayDoseStatus status = TodayDoseStatus.pending,
    bool snoozed = false,
    bool reduceMotion = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 350,
                child: FardaTodayRoutineCard(
                  timeLabel: '9:00 AM',
                  status: status,
                  isSnoozed: snoozed,
                  onOpenLog: () {},
                  onSnooze: () {},
                  onMoreOptions: () {},
                  onCorrectEntry: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  FardaCompanionMood mood(WidgetTester tester) =>
      tester.widget<FardaCompanion>(find.byType(FardaCompanion)).mood;

  testWidgets('pending routine has one prominent dose action and waving pose', (
    tester,
  ) async {
    await pumpCard(tester);
    expect(mood(tester), FardaCompanionMood.waving);
    expect(find.text('Not yet confirmed'), findsOneWidget);
    expect(find.byKey(FardaTodayRoutineCard.logDoseButtonKey), findsOneWidget);
    expect(
      find.byKey(FardaTodayRoutineCard.correctEntryButtonKey),
      findsNothing,
    );
    expect(find.text('Remind in 15 min'), findsOneWidget);
  });

  testWidgets('snooze is a resting pose and never a confirmed entry', (
    tester,
  ) async {
    await pumpCard(tester, snoozed: true, reduceMotion: true);
    expect(mood(tester), FardaCompanionMood.snoozed);
    expect(find.text('Reminder snoozed · Not yet confirmed'), findsOneWidget);
    expect(find.textContaining('You confirmed'), findsNothing);
    final snooze = find.descendant(
      of: find.byKey(FardaTodayRoutineCard.snoozeButtonKey),
      matching: find.byType(OutlinedButton),
    );
    expect(tester.widget<OutlinedButton>(snooze).onPressed, isNull);
  });

  testWidgets(
    'saved and skipped records have distinct, quiet companion states',
    (tester) async {
      await pumpCard(tester, status: TodayDoseStatus.confirmed);
      expect(mood(tester), FardaCompanionMood.confirmed);
      expect(find.text('You confirmed · 9:00 AM'), findsOneWidget);
      expect(find.byKey(FardaTodayRoutineCard.logDoseButtonKey), findsNothing);
      expect(
        find.byKey(FardaTodayRoutineCard.correctEntryButtonKey),
        findsOneWidget,
      );

      await pumpCard(tester, status: TodayDoseStatus.skipped);
      expect(mood(tester), FardaCompanionMood.skipped);
      expect(find.text('You recorded a skipped dose'), findsOneWidget);
      expect(find.byKey(FardaTodayRoutineCard.logDoseButtonKey), findsNothing);
    },
  );
}
