import 'package:farda/consumer_v2/screens/you/circle_routine_summary.dart';
import 'package:farda/features/consumer/data/circle_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

CircleRoutine _routine({bool doses = true, bool reminders = true}) =>
    CircleRoutine(
      owner: const CirclePerson(id: 'owner', displayName: 'Sam'),
      permissions: CirclePermissions(doseStatus: doses, reminders: reminders),
      fetchedAt: DateTime(2026, 10, 17),
      notice: '',
      items: const [
        CircleRoutineItem(
          id: '1',
          label: 'A',
          state: CircleRoutineState.taken,
          evidence: CircleEvidence.selfReport,
        ),
        CircleRoutineItem(
          id: '2',
          label: 'B',
          state: CircleRoutineState.taken,
          evidence: CircleEvidence.deviceObservation,
        ),
        CircleRoutineItem(
          id: '3',
          label: 'C',
          state: CircleRoutineState.notRecorded,
          evidence: CircleEvidence.none,
        ),
        CircleRoutineItem(
          id: '4',
          label: 'D',
          state: CircleRoutineState.skipped,
          evidence: CircleEvidence.selfReport,
        ),
        CircleRoutineItem(
          id: '5',
          label: 'E',
          state: CircleRoutineState.snoozed,
          evidence: CircleEvidence.selfReport,
        ),
      ],
    );

void main() {
  testWidgets(
    'summary distinguishes reported records from device and absent evidence',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CircleRoutineSummary(routine: _routine())),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1 reported taken'), findsOneWidget);
      expect(find.text('1 reported skipped'), findsOneWidget);
      expect(find.text('1 snoozed'), findsOneWidget);
      expect(find.text('2 not confirmed'), findsOneWidget);
      expect(
        find.textContaining('doesn’t mean a dose was missed'),
        findsOneWidget,
      );
    },
  );

  testWidgets('reminder-only and paused summaries reveal no status counts', (
    tester,
  ) async {
    for (final reminders in [true, false]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CircleRoutineSummary(
              routine: _routine(doses: false, reminders: reminders),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('reported taken'), findsNothing);
      expect(find.textContaining('not confirmed'), findsNothing);
      expect(
        find.text(
          reminders
              ? 'Reminder times are shared. Dose updates stay private.'
              : 'Still connected. Sharing paused.',
        ),
        findsOneWidget,
      );
    }
  });

  testWidgets('summary wraps at 320 with double-size text', (tester) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: CircleRoutineSummary(routine: _routine()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
