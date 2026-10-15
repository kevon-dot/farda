import 'package:farda/consumer_v2/screens/today/farda_today_screen.dart';
import 'package:farda/consumer_v2/screens/today/today_models.dart';
import 'package:farda/consumer_v2/screens/today/today_routine_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('logging requires explicit confirmation', (tester) async {
    final snapshots = <TodayDoseSnapshot>[];
    await tester.pumpWidget(
      MaterialApp(
        home: FardaTodayScreen(
          initialDate: DateTime(2026, 10, 14),
          showBottomNavigation: false,
          onDoseChanged: snapshots.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('9:00 AM · Not yet confirmed'), findsOneWidget);
    final logButton = find.byKey(FardaTodayRoutineCard.logDoseButtonKey);
    await tester.ensureVisible(logButton);
    await tester.tap(logButton);
    await tester.pumpAndSettle();

    expect(find.text('Log your morning dose?'), findsOneWidget);
    expect(snapshots, isEmpty);

    await tester.tap(find.byKey(FardaTodayScreen.confirmDoseButtonKey));
    await tester.pumpAndSettle();

    expect(find.text('You confirmed · 9:00 AM'), findsOneWidget);
    expect(snapshots.single.status, TodayDoseStatus.confirmed);
    expect(snapshots.single.isSnoozed, isFalse);
  });

  testWidgets('snooze changes reminder state without confirming the dose', (
    tester,
  ) async {
    TodayDoseSnapshot? latest;
    await tester.pumpWidget(
      MaterialApp(
        home: FardaTodayScreen(
          initialDate: DateTime(2026, 10, 14),
          showBottomNavigation: false,
          onDoseChanged: (snapshot) => latest = snapshot,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final snoozeButton = find.byKey(FardaTodayRoutineCard.snoozeButtonKey);
    await tester.ensureVisible(snoozeButton);
    await tester.tap(snoozeButton);
    await tester.pumpAndSettle();

    expect(find.text('Reminder snoozed · Not yet confirmed'), findsOneWidget);
    expect(latest?.status, TodayDoseStatus.pending);
    expect(latest?.isSnoozed, isTrue);
  });

  testWidgets('day selection updates locally and opens the calendar callback', (
    tester,
  ) async {
    DateTime? selected;
    var calendarOpenCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: FardaTodayScreen(
          initialDate: DateTime(2026, 10, 14),
          showBottomNavigation: false,
          onDaySelected: (date) => selected = date,
          onOpenCalendar: () => calendarOpenCount++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('today_day_2026-10-15')));
    await tester.pumpAndSettle();

    expect(selected, DateTime(2026, 10, 15));
    expect(calendarOpenCount, 1);
    expect(find.text('15'), findsAtLeastNWidgets(2));
  });
}
