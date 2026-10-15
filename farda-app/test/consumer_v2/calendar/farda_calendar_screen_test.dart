import 'package:farda/consumer_v2/screens/calendar/farda_calendar_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final today = DateTime(2026, 10, 14);

  Future<void> pumpCalendar(
    WidgetTester tester, {
    List<ConsumerCalendarEvent>? events,
    ValueChanged<DateTime>? onSelectedDateChanged,
    ValueChanged<DateTime>? onVisibleMonthChanged,
    ValueChanged<ConsumerCalendarFilter>? onFilterChanged,
    ConsumerCalendarEventCallback? onEventAction,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: FardaCalendarScreen(
          today: today,
          initialSelectedDate: today,
          events: events,
          onSelectedDateChanged: onSelectedDateChanged,
          onVisibleMonthChanged: onVisibleMonthChanged,
          onFilterChanged: onFilterChanged,
          onEventAction: onEventAction,
        ),
      ),
    );
  }

  testWidgets('renders the handoff structure and local sample agenda', (
    tester,
  ) async {
    await pumpCalendar(tester);

    expect(find.text('farda.'), findsOneWidget);
    expect(find.text('A rhythm\nthat fits you.'), findsOneWidget);
    expect(find.text('October 2026'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Routines'), findsOneWidget);
    expect(find.text('Refills'), findsOneWidget);
    expect(find.text('Morning entry · Not yet confirmed'), findsOneWidget);
  });

  testWidgets('month controls update local state and emit callbacks', (
    tester,
  ) async {
    DateTime? changedMonth;
    DateTime? changedDate;
    await pumpCalendar(
      tester,
      onVisibleMonthChanged: (value) => changedMonth = value,
      onSelectedDateChanged: (value) => changedDate = value,
    );

    await tester.tap(find.byTooltip('Next month'));
    await tester.pump();

    expect(find.text('November 2026'), findsOneWidget);
    expect(changedMonth, DateTime(2026, 11));
    expect(changedDate, DateTime(2026, 11, 14));
  });

  testWidgets('date and filter choices update the selected-day cards', (
    tester,
  ) async {
    ConsumerCalendarFilter? changedFilter;
    DateTime? changedDate;
    await pumpCalendar(
      tester,
      onFilterChanged: (value) => changedFilter = value,
      onSelectedDateChanged: (value) => changedDate = value,
    );

    await tester.tap(find.text('Refills'));
    await tester.pump();
    expect(changedFilter, ConsumerCalendarFilter.refills);
    expect(find.text('No refill reminder is saved for this day.'), findsOneWidget);

    await tester.tap(find.text('16'));
    await tester.pump();

    expect(changedDate, DateTime(2026, 10, 16));
    expect(find.text('Check in with your pharmacy'), findsOneWidget);
    expect(find.text('Morning entry · Not yet confirmed'), findsNothing);
  });

  testWidgets('injected records and event actions remain presentation-only', (
    tester,
  ) async {
    final event = ConsumerCalendarEvent(
      id: 'routine-1',
      date: today,
      type: ConsumerCalendarEventType.routine,
      status: ConsumerCalendarEventStatus.recorded,
      eyebrow: '8:00 AM · Morning',
      title: 'Your entry is recorded',
      description: 'Self-reported in the app.',
      actionLabel: 'Review entry',
    );
    ConsumerCalendarEvent? actedOn;
    await pumpCalendar(
      tester,
      events: [event],
      onEventAction: (value) => actedOn = value,
    );

    await tester.ensureVisible(find.text('Review entry'));
    await tester.tap(find.text('Review entry'));
    await tester.pump();

    expect(actedOn, same(event));
  });

  testWidgets('month and date controls provide descriptive semantics', (
    tester,
  ) async {
    await pumpCalendar(tester);
    final semantics = tester.ensureSemantics();
    try {
      expect(
        find.bySemanticsLabel('Show the previous month before October 2026'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          RegExp(r'Wednesday, October 14, 2026\. Today'),
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          RegExp(r'Tuesday, October 13, 2026\. Unconfirmed entry'),
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          RegExp(r'Friday, October 16, 2026\. Refill reminder'),
        ),
        findsOneWidget,
      );
    } finally {
      semantics.dispose();
    }
  });
}
