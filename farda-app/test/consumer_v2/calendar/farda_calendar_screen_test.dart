import 'dart:ui' show SemanticsAction, Tristate;

import 'package:farda/consumer_v2/screens/calendar/farda_calendar_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final today = DateTime(2026, 10, 14);

  Future<void> pumpCalendar(
    WidgetTester tester, {
    List<ConsumerCalendarEvent>? events,
    DateTime? initialSelectedDate,
    DateTime? initialVisibleMonth,
    ValueChanged<DateTime>? onSelectedDateChanged,
    ValueChanged<DateTime>? onVisibleMonthChanged,
    ValueChanged<ConsumerCalendarFilter>? onFilterChanged,
    ConsumerCalendarEventCallback? onEventAction,
    double width = 390,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        builder:
            (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
        home: FardaCalendarScreen(
          today: today,
          initialSelectedDate: initialSelectedDate ?? today,
          initialVisibleMonth:
              initialVisibleMonth ?? initialSelectedDate ?? today,
          events: events,
          onSelectedDateChanged: onSelectedDateChanged,
          onVisibleMonthChanged: onVisibleMonthChanged,
          onFilterChanged: onFilterChanged,
          onEventAction: onEventAction,
        ),
      ),
    );
  }

  testWidgets('starts in week mode and toggling month preserves selection', (
    tester,
  ) async {
    final selectedDates = <DateTime>[];
    final visibleMonths = <DateTime>[];
    final semantics = tester.ensureSemantics();
    try {
      await pumpCalendar(
        tester,
        onSelectedDateChanged: selectedDates.add,
        onVisibleMonthChanged: visibleMonths.add,
      );

      expect(find.text('YOUR CALENDAR'), findsOneWidget);
      expect(find.byTooltip('Previous week'), findsOneWidget);
      expect(find.byTooltip('Next week'), findsOneWidget);
      expect(find.byKey(const Key('calendar-day-2026-10-12')), findsOneWidget);
      expect(find.byKey(const Key('calendar-day-2026-10-18')), findsOneWidget);
      expect(
        find.byKey(const Key('calendar-month-day-2026-10-14')),
        findsNothing,
      );
      expect(
        tester
            .getSemantics(find.byKey(const Key('calendar-day-2026-10-14')))
            .getSemanticsData()
            .flagsCollection
            .isSelected,
        Tristate.isTrue,
      );
      expect(
        tester
            .getSemantics(find.byKey(const Key('calendar-month-toggle')))
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );

      await tester.tap(find.byKey(const Key('calendar-month-toggle')));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Previous month'), findsOneWidget);
      expect(find.byTooltip('Next month'), findsOneWidget);
      expect(
        find.byKey(const Key('calendar-month-day-2026-10-14')),
        findsOneWidget,
      );
      expect(find.text('Wednesday, October 14'), findsOneWidget);
      expect(selectedDates, isEmpty);
      expect(visibleMonths, isEmpty);

      await tester.tap(find.byKey(const Key('calendar-month-toggle')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('calendar-month-day-2026-10-14')),
        findsNothing,
      );
      expect(find.byTooltip('Next week'), findsOneWidget);
      expect(selectedDates, isEmpty);
      expect(visibleMonths, isEmpty);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
    'week navigation keeps the local weekday across a DST month boundary',
    (tester) async {
      final selectedDates = <DateTime>[];
      final visibleMonths = <DateTime>[];
      await pumpCalendar(
        tester,
        initialSelectedDate: DateTime(2026, 10, 28),
        onSelectedDateChanged: selectedDates.add,
        onVisibleMonthChanged: visibleMonths.add,
      );

      await tester.tap(find.byTooltip('Next week'));
      await tester.pumpAndSettle();

      expect(selectedDates, [DateTime(2026, 11, 4)]);
      expect(visibleMonths, [DateTime(2026, 11)]);
      expect(find.text('November 2026'), findsOneWidget);
      expect(find.byKey(const Key('calendar-day-2026-11-04')), findsOneWidget);
      expect(find.text('Wednesday, November 4'), findsOneWidget);
    },
  );

  testWidgets('Today restores the actual date and visible expanded month', (
    tester,
  ) async {
    final selectedDates = <DateTime>[];
    final visibleMonths = <DateTime>[];
    await pumpCalendar(
      tester,
      initialSelectedDate: DateTime(2026, 12, 31),
      onSelectedDateChanged: selectedDates.add,
      onVisibleMonthChanged: visibleMonths.add,
    );
    await tester.tap(find.byKey(const Key('calendar-month-toggle')));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Today').first);
    await tester.pumpAndSettle();

    expect(selectedDates, [today]);
    expect(visibleMonths, [DateTime(2026, 10)]);
    expect(find.text('October 2026'), findsOneWidget);
    expect(find.byTooltip('Next month'), findsOneWidget);
    expect(
      find.byKey(const Key('calendar-month-day-2026-10-14')),
      findsOneWidget,
    );
    expect(find.text('Wednesday, October 14'), findsOneWidget);
  });

  testWidgets('expanded month navigation crosses a year and clamps the day', (
    tester,
  ) async {
    final selectedDates = <DateTime>[];
    final visibleMonths = <DateTime>[];
    await pumpCalendar(
      tester,
      initialSelectedDate: DateTime(2026, 12, 31),
      onSelectedDateChanged: selectedDates.add,
      onVisibleMonthChanged: visibleMonths.add,
    );
    await tester.tap(find.byKey(const Key('calendar-month-toggle')));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();

    expect(visibleMonths, [DateTime(2027, 1), DateTime(2027, 2)]);
    expect(selectedDates, [DateTime(2027, 1, 31), DateTime(2027, 2, 28)]);
    expect(find.text('February 2027'), findsOneWidget);
    expect(
      find.byKey(const Key('calendar-month-day-2027-02-28')),
      findsOneWidget,
    );
    expect(find.text('Sunday, February 28'), findsOneWidget);
  });

  testWidgets('status, filter, and action semantics stay truthful', (
    tester,
  ) async {
    final events = [
      ConsumerCalendarEvent(
        id: 'pending-id',
        date: today,
        type: ConsumerCalendarEventType.routine,
        status: ConsumerCalendarEventStatus.pending,
        routineName: 'Future routine',
        eyebrow: '8:00 AM',
        title: 'Not yet confirmed',
        description: 'No dose has been confirmed.',
        actionLabel: 'Open upcoming entry',
      ),
      ConsumerCalendarEvent(
        id: 'unconfirmed-id',
        date: today,
        type: ConsumerCalendarEventType.routine,
        status: ConsumerCalendarEventStatus.unconfirmed,
        routineName: 'Past routine',
        eyebrow: '9:00 AM',
        title: 'Not yet confirmed',
        description: 'No dose has been confirmed.',
        actionLabel: 'Open past entry',
      ),
      ConsumerCalendarEvent(
        id: 'snoozed-id',
        date: today,
        type: ConsumerCalendarEventType.routine,
        status: ConsumerCalendarEventStatus.snoozed,
        routineName: 'Delayed routine',
        eyebrow: '10:00 AM',
        title: 'Reminder snoozed',
        description: 'Until 10:15 AM · No dose confirmed.',
        actionLabel: 'Open snoozed entry',
      ),
      ConsumerCalendarEvent(
        id: 'recorded-id',
        date: today,
        type: ConsumerCalendarEventType.routine,
        status: ConsumerCalendarEventStatus.recorded,
        routineName: 'Recorded routine',
        eyebrow: '11:00 AM',
        title: 'Recorded as taken',
        description: 'You recorded this dose as taken.',
        actionLabel: 'Review recorded entry',
      ),
      ConsumerCalendarEvent(
        id: 'skipped-id',
        date: today,
        type: ConsumerCalendarEventType.routine,
        status: ConsumerCalendarEventStatus.skipped,
        routineName: 'Skipped routine',
        eyebrow: '12:00 PM',
        title: 'Recorded as skipped',
        description: 'You recorded this dose as skipped.',
        actionLabel: 'Review skipped entry',
      ),
      ConsumerCalendarEvent(
        id: 'refill-id',
        date: today,
        type: ConsumerCalendarEventType.refill,
        status: ConsumerCalendarEventStatus.planned,
        eyebrow: 'REFILL PLAN',
        title: 'Your refill',
        description: 'A plan you recorded; no pharmacy order was placed.',
        actionLabel: 'Open refill station',
      ),
    ];
    final filterChanges = <ConsumerCalendarFilter>[];
    ConsumerCalendarEvent? actedOn;
    final semantics = tester.ensureSemantics();
    try {
      await pumpCalendar(
        tester,
        events: events,
        onFilterChanged: filterChanges.add,
        onEventAction: (event) => actedOn = event,
      );

      expect(find.textContaining('Upcoming'), findsOneWidget);
      expect(find.textContaining('Not yet confirmed'), findsOneWidget);
      expect(find.textContaining('Snoozed'), findsOneWidget);
      expect(find.textContaining('Recorded as taken'), findsOneWidget);
      expect(find.textContaining('Skipped · recorded by you'), findsOneWidget);
      expect(find.textContaining('Refill plan'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(r'Scheduled routine')),
        findsOneWidget,
      );
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Show refills calendar items'))
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );

      final refillsFilter = find.bySemanticsLabel(
        'Show refills calendar items',
      );
      await tester.ensureVisible(refillsFilter);
      await tester.pumpAndSettle();
      await tester.tap(refillsFilter);
      await tester.pumpAndSettle();

      expect(filterChanges, [ConsumerCalendarFilter.refills]);
      expect(find.textContaining('Refill plan'), findsOneWidget);
      expect(find.textContaining('Upcoming'), findsNothing);
      expect(
        find.text('A plan you recorded; no pharmacy order was placed.'),
        findsOneWidget,
      );
      expect(
        tester
            .getSemantics(find.text('Open refill station'))
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );

      await tester.ensureVisible(find.text('Open refill station'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open refill station'));
      await tester.pump();
      expect(actedOn, same(events.last));
      expect(actedOn?.id, 'refill-id');

      final routinesFilter = find.bySemanticsLabel(
        'Show routines calendar items',
      );
      await tester.ensureVisible(routinesFilter);
      await tester.pumpAndSettle();
      await tester.tap(routinesFilter);
      await tester.pumpAndSettle();
      expect(filterChanges, [
        ConsumerCalendarFilter.refills,
        ConsumerCalendarFilter.routines,
      ]);
      expect(find.textContaining('Refill plan'), findsNothing);
      expect(find.textContaining('Upcoming'), findsOneWidget);
      expect(find.textContaining('Snoozed'), findsOneWidget);
      expect(find.textContaining('Recorded as taken'), findsOneWidget);
      expect(find.textContaining('Skipped · recorded by you'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('an unresolved evening entry stays primary over saved history', (
    tester,
  ) async {
    final savedMorning = ConsumerCalendarEvent(
      id: 'saved-morning',
      date: DateTime(2026, 10, 14, 8),
      type: ConsumerCalendarEventType.routine,
      status: ConsumerCalendarEventStatus.recorded,
      routineName: 'Morning routine',
      eyebrow: '8:00 AM',
      title: 'Recorded as taken',
      description: 'You recorded this dose as taken.',
      actionLabel: 'Review morning entry',
    );
    final upcomingEvening = ConsumerCalendarEvent(
      id: 'upcoming-evening',
      date: DateTime(2026, 10, 14, 20),
      type: ConsumerCalendarEventType.routine,
      status: ConsumerCalendarEventStatus.pending,
      routineName: 'Evening routine',
      eyebrow: '8:00 PM',
      title: 'Not yet confirmed',
      description: 'No dose has been confirmed.',
      actionLabel: 'Add evening entry',
    );
    ConsumerCalendarEvent? actedOn;
    await pumpCalendar(
      tester,
      events: [savedMorning, upcomingEvening],
      onEventAction: (event) => actedOn = event,
    );

    expect(
      find.widgetWithText(FilledButton, 'Add evening entry'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(FilledButton, 'Review morning entry'),
      findsNothing,
    );
    expect(find.textContaining('Upcoming'), findsOneWidget);
    expect(find.textContaining('Recorded as taken'), findsOneWidget);

    await tester.tap(find.text('Add evening entry'));
    await tester.pump();
    expect(actedOn, same(upcomingEvening));
    expect(actedOn?.id, 'upcoming-evening');
  });

  testWidgets('empty filters can return to all entries without sample data', (
    tester,
  ) async {
    await pumpCalendar(tester, events: []);

    expect(find.text('Nothing planned here.'), findsOneWidget);
    expect(
      find.text('Choose another day or view your routine.'),
      findsOneWidget,
    );
    expect(find.text('Upcoming'), findsNothing);
    expect(find.text('Recorded by you'), findsNothing);

    await tester.tap(find.text('Refills'));
    await tester.pumpAndSettle();
    expect(find.text('No refill plans here.'), findsOneWidget);
    await tester.tap(find.text('Show all entries'));
    await tester.pumpAndSettle();
    expect(
      find.text('Choose another day or view your routine.'),
      findsOneWidget,
    );
  });

  testWidgets('320px layout with larger text keeps controls usable', (
    tester,
  ) async {
    ConsumerCalendarEvent markerEvent(
      String id,
      ConsumerCalendarEventStatus status, {
      ConsumerCalendarEventType type = ConsumerCalendarEventType.routine,
    }) => ConsumerCalendarEvent(
      id: id,
      date: today,
      type: type,
      status: status,
      routineName: type == ConsumerCalendarEventType.routine ? id : null,
      eyebrow: '8:00 AM',
      title: id,
      description:
          type == ConsumerCalendarEventType.refill
              ? 'A plan you recorded; no pharmacy order was placed.'
              : 'Calendar status.',
    );
    final events = [
      markerEvent('Recorded', ConsumerCalendarEventStatus.recorded),
      markerEvent('Skipped', ConsumerCalendarEventStatus.skipped),
      markerEvent('Snoozed', ConsumerCalendarEventStatus.snoozed),
      markerEvent('Unconfirmed', ConsumerCalendarEventStatus.unconfirmed),
      markerEvent('Scheduled', ConsumerCalendarEventStatus.pending),
      markerEvent(
        'Refill',
        ConsumerCalendarEventStatus.planned,
        type: ConsumerCalendarEventType.refill,
      ),
    ];

    await pumpCalendar(tester, events: events, width: 320, textScale: 1.3);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byKey(const Key('calendar-day-2026-10-14'))).width,
      greaterThanOrEqualTo(44),
    );
    expect(
      tester.getSize(find.byKey(const Key('calendar-month-toggle'))).height,
      greaterThanOrEqualTo(44),
    );

    await tester.tap(find.byKey(const Key('calendar-month-toggle')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const Key('calendar-month-day-2026-10-14')),
      findsOneWidget,
    );
    final monthDaySemantics =
        tester
            .getSemantics(
              find.byKey(const Key('calendar-month-day-2026-10-14')),
            )
            .getSemanticsData();
    for (final label in [
      'Recorded entry',
      'Skipped entry recorded',
      'Snoozed reminder',
      'Unconfirmed entry',
      'Scheduled routine',
      'Refill reminder',
    ]) {
      expect(monthDaySemantics.label, contains(label));
    }

    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      find.bySemanticsLabel('November 2026, hide full month'),
      findsOneWidget,
    );
  });
}
