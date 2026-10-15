import 'dart:ui' show SemanticsAction;

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

  testWidgets('renders the concise calendar and local preview agenda', (
    tester,
  ) async {
    await pumpCalendar(tester);

    expect(find.text('farda.'), findsOneWidget);
    expect(find.text('Find your\nrhythm.'), findsOneWidget);
    expect(find.text('October 2026'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Routines'), findsOneWidget);
    expect(find.text('Refills'), findsOneWidget);
    expect(find.text('Not yet confirmed'), findsOneWidget);
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
    await tester.pumpAndSettle();

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
    await tester.pumpAndSettle();
    expect(changedFilter, ConsumerCalendarFilter.refills);
    expect(find.text('No refill reminders for this day.'), findsOneWidget);

    await tester.tap(find.text('16'));
    await tester.pumpAndSettle();

    expect(changedDate, DateTime(2026, 10, 16));
    expect(find.text('Check in with your pharmacy'), findsOneWidget);
    expect(find.text('Not yet confirmed'), findsNothing);
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

  testWidgets('empty account has no sample entries or misleading legend', (
    tester,
  ) async {
    await pumpCalendar(tester, events: []);

    expect(find.text('A quiet day'), findsOneWidget);
    expect(find.text('No saved calendar items for this day.'), findsOneWidget);
    expect(find.text('Not yet confirmed'), findsNothing);
    expect(find.text('Recorded'), findsNothing);
    expect(find.text('Unconfirmed'), findsNothing);
  });

  testWidgets('empty filters offer a working return to all entries', (
    tester,
  ) async {
    await pumpCalendar(tester);
    await tester.tap(find.text('Refills'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show all entries'));
    await tester.pumpAndSettle();
    expect(find.text('Not yet confirmed'), findsOneWidget);
    expect(find.text('No refill reminders for this day.'), findsNothing);
  });

  testWidgets('actionable refill cards keep the no-order caveat visible', (
    tester,
  ) async {
    const caveat = 'A plan you recorded; no pharmacy order was placed.';
    await pumpCalendar(
      tester,
      events: [
        ConsumerCalendarEvent(
          id: 'refill-plan',
          date: today,
          type: ConsumerCalendarEventType.refill,
          status: ConsumerCalendarEventStatus.planned,
          eyebrow: 'REFILL PLAN',
          title: 'Your refill',
          description: caveat,
          actionLabel: 'Open refill station',
        ),
      ],
      onEventAction: (_) {},
    );
    expect(find.text(caveat), findsOneWidget);
    expect(find.text('Open refill station'), findsOneWidget);
  });

  testWidgets('filter chips expose an assistive-technology tap action', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await pumpCalendar(tester);
      final node = tester.getSemantics(
        find.bySemanticsLabel('Show refills calendar items'),
      );
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('selected day count and legend come only from actual events', (
    tester,
  ) async {
    await pumpCalendar(
      tester,
      events: [
        ConsumerCalendarEvent(
          id: 'refill-1',
          date: DateTime(2026, 10, 16),
          type: ConsumerCalendarEventType.refill,
          status: ConsumerCalendarEventStatus.planned,
          eyebrow: 'Your refill reminder',
          title: 'Check in with your pharmacy',
          description: 'Reminder only; pickup is not confirmed.',
        ),
      ],
    );

    expect(find.text('Refill'), findsOneWidget);
    expect(find.text('Recorded'), findsNothing);
    await tester.tap(find.text('16'));
    await tester.pumpAndSettle();
    expect(find.text('Check in with your pharmacy'), findsOneWidget);
    expect(find.text('A quiet day'), findsNothing);
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
        find.bySemanticsLabel(RegExp(r'Wednesday, October 14, 2026\. Today')),
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
