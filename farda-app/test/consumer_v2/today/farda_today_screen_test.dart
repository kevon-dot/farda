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

    expect(find.text('Not yet confirmed'), findsOneWidget);
    final logButton = find.byKey(FardaTodayRoutineCard.logDoseButtonKey);
    await tester.ensureVisible(logButton);
    await tester.tap(logButton);
    await tester.pumpAndSettle();

    expect(find.text('Your record.\nYour choice.'), findsOneWidget);
    expect(snapshots, isEmpty);

    await tester.tap(find.byKey(FardaTodayScreen.confirmDoseButtonKey));
    await tester.pumpAndSettle();

    expect(find.text('You’re all set.'), findsOneWidget);
    expect(find.textContaining('You confirmed ·'), findsOneWidget);
    expect(find.text('Taken · You confirmed'), findsOneWidget);
    expect(snapshots.single.status, TodayDoseStatus.confirmed);
    expect(snapshots.single.isSnoozed, isFalse);
  });

  testWidgets('leaving check-in writes no dose or reminder state', (
    tester,
  ) async {
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
    await tester.ensureVisible(find.byKey(FardaTodayRoutineCard.logDoseButtonKey));
    await tester.tap(find.byKey(FardaTodayRoutineCard.logDoseButtonKey));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Not now'));
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.text('Not yet confirmed'), findsOneWidget);
    expect(snapshots, isEmpty);
  });

  testWidgets('failed live write stays at check-in and does not show receipt', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FardaTodayScreen(
          initialDate: DateTime(2026, 10, 14),
          liveRecords: true,
          showBottomNavigation: false,
          routines: const [
            TodayRoutineRecord(
              id: 'routine-a',
              medicationLabel: 'Morning medication',
              timeLabel: '9:00 AM',
              status: TodayDoseStatus.pending,
              isSnoozed: false,
            ),
          ],
          onPersistDoseForId:
              (id, status) async => 'Could not save your entry.',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(FardaTodayRoutineCard.logDoseButtonKey));
    await tester.tap(find.byKey(FardaTodayRoutineCard.logDoseButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(FardaTodayScreen.confirmDoseButtonKey));
    await tester.pumpAndSettle();
    expect(find.text('Your record.\nYour choice.'), findsOneWidget);
    expect(find.text('You’re all set.'), findsNothing);
    expect(find.text('Could not save your entry.'), findsOneWidget);
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

    expect(find.text('We’ll remind\nyou again.'), findsOneWidget);
    expect(
      find.text('Reminder snoozed. Your record is unconfirmed.'),
      findsOneWidget,
    );
    expect(latest?.status, TodayDoseStatus.pending);
    expect(latest?.isSnoozed, isTrue);

    await tester.ensureVisible(find.text('Back to today'));
    await tester.tap(find.text('Back to today'));
    await tester.pumpAndSettle();
    expect(find.text('Reminder snoozed · Not yet confirmed'), findsOneWidget);
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
