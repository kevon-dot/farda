import 'package:farda/consumer_v2/consumer_v2_entry.dart';
import 'package:farda/consumer_v2/screens/today/farda_today_screen.dart';
import 'package:farda/consumer_v2/screens/today/today_routine_card.dart';
import 'package:farda/features/consumer/data/consumer_demo_repository.dart';
import 'package:farda/features/consumer/data/consumer_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordsRepository extends ConsumerDemoRepository {
  _RecordsRepository({this.hasOccurrence = true});

  final bool hasOccurrence;
  bool failNextWrite = false;
  OccurrenceStatus status = OccurrenceStatus.unconfirmed;
  int revision = 0;
  int writes = 0;

  @override
  bool get isDemo => false;

  @override
  Future<ConsumerSnapshot> loadSnapshot({
    required DateTime from,
    required DateTime to,
  }) async {
    final now = DateTime.now();
    final due = DateTime(now.year, now.month, now.day, 9);
    return ConsumerSnapshot(
      prescriptions:
          hasOccurrence
              ? const [
                ConsumerPrescription(id: 'rx', name: 'My reviewed routine'),
              ]
              : const [],
      occurrences:
          hasOccurrence && !due.isBefore(from) && due.isBefore(to)
              ? [
                ConsumerOccurrence(
                  id: 'occurrence',
                  prescriptionId: 'rx',
                  scheduledFor: due,
                  status: status,
                  revision: revision,
                ),
              ]
              : const [],
      fetchedAt: now,
    );
  }

  @override
  Future<void> recordOccurrence(ConsumerOccurrenceUpdate update) async {
    writes++;
    if (failNextWrite) {
      failNextWrite = false;
      throw const ConsumerRepositoryException(
        'The server did not save this entry.',
      );
    }
    if (update.id != 'occurrence' || update.expectedRevision != revision) {
      throw const ConsumerRepositoryException(
        'This record changed. Refresh it.',
      );
    }
    status = update.status!;
    revision++;
  }
}

class _MultipleRecordsRepository extends _RecordsRepository {
  OccurrenceStatus eveningStatus = OccurrenceStatus.unconfirmed;
  int eveningRevision = 0;
  String? lastWrittenId;
  String? lastSnoozedId;
  DateTime? eveningSnoozedUntil;

  @override
  Future<ConsumerSnapshot> loadSnapshot({
    required DateTime from,
    required DateTime to,
  }) async {
    final base = await super.loadSnapshot(from: from, to: to);
    final now = DateTime.now();
    final evening = DateTime(now.year, now.month, now.day, 21);
    return ConsumerSnapshot(
      prescriptions: [
        ...base.prescriptions,
        const ConsumerPrescription(
          id: 'evening-rx',
          name: 'Evening reviewed routine',
        ),
      ],
      occurrences: [
        ...base.occurrences,
        if (!evening.isBefore(from) && evening.isBefore(to))
          ConsumerOccurrence(
            id: 'evening-occurrence',
            prescriptionId: 'evening-rx',
            scheduledFor: evening,
            status: eveningStatus,
            revision: eveningRevision,
            snoozedUntil: eveningSnoozedUntil,
          ),
      ],
      fetchedAt: now,
    );
  }

  @override
  Future<void> recordOccurrence(ConsumerOccurrenceUpdate update) async {
    lastWrittenId = update.id;
    if (update.id != 'evening-occurrence') {
      return super.recordOccurrence(update);
    }
    writes++;
    if (failNextWrite) {
      failNextWrite = false;
      throw const ConsumerRepositoryException(
        'The server did not save this entry.',
      );
    }
    if (update.expectedRevision != eveningRevision) {
      throw const ConsumerRepositoryException(
        'This record changed. Refresh it.',
      );
    }
    eveningStatus = update.status!;
    eveningRevision++;
  }

  @override
  Future<void> snoozeOccurrence(String id, Duration duration) async {
    lastSnoozedId = id;
    if (id != 'evening-occurrence') {
      throw const ConsumerRepositoryException('Wrong occurrence.');
    }
    eveningSnoozedUntil = DateTime.now().add(duration);
  }
}

void main() {
  Future<void> pumpEntry(
    WidgetTester tester,
    _RecordsRepository repository,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(home: ConsumerV2Entry(repository: repository)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('empty account never displays a sample dose or a save control', (
    tester,
  ) async {
    await pumpEntry(tester, _RecordsRepository(hasOccurrence: false));
    expect(find.text('No routine on this day'), findsOneWidget);
    expect(find.byKey(FardaTodayRoutineCard.logDoseButtonKey), findsNothing);

    await tester.tap(find.text('Refills'));
    await tester.pumpAndSettle();
    expect(find.text('No prescriptions yet'), findsOneWidget);
    expect(find.text('Daily medication'), findsNothing);

    await tester.tap(find.text('You'));
    await tester.pumpAndSettle();
    expect(find.text('Sharing preview'), findsOneWidget);
  });

  testWidgets(
    'failed write stays unconfirmed; accepted write survives reload',
    (tester) async {
      final repository = _RecordsRepository()..failNextWrite = true;
      await pumpEntry(tester, repository);
      final log = find.byKey(FardaTodayRoutineCard.logDoseButtonKey);
      await tester.ensureVisible(log);
      await tester.tap(log);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(FardaTodayScreen.confirmDoseButtonKey));
      await tester.pumpAndSettle();
      expect(repository.status, OccurrenceStatus.unconfirmed);
      expect(find.text('Your record.\nYour choice.'), findsOneWidget);
      expect(find.text('You’re all set.'), findsNothing);
      await tester.tap(find.byKey(FardaTodayScreen.confirmDoseButtonKey));
      await tester.pumpAndSettle();
      expect(repository.status, OccurrenceStatus.taken);
      expect(repository.writes, 2);
      expect(find.text('Taken · You confirmed'), findsOneWidget);

      await tester.tap(find.text('Calendar'));
      await tester.pumpAndSettle();
      expect(find.textContaining('My reviewed routine'), findsOneWidget);
      expect(find.text('Recorded as taken'), findsOneWidget);
    },
  );

  testWidgets(
    'multiple routines show separate statuses and save selected ID only',
    (tester) async {
      final repository = _MultipleRecordsRepository()..failNextWrite = true;
      await pumpEntry(tester, repository);
      expect(find.text('My reviewed routine'), findsWidgets);
      expect(find.textContaining('Evening reviewed routine'), findsWidgets);
      expect(find.byKey(const Key('today_routine_occurrence')), findsOneWidget);
      expect(
        find.byKey(const Key('today_routine_evening-occurrence')),
        findsOneWidget,
      );

      await tester.ensureVisible(
        find.byKey(const Key('today_routine_evening-occurrence')),
      );
      await tester.tap(
        find.byKey(const Key('today_routine_evening-occurrence')),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(FardaTodayRoutineCard.logDoseButtonKey),
      );
      await tester.tap(find.byKey(FardaTodayRoutineCard.logDoseButtonKey));
      await tester.pumpAndSettle();
      expect(find.textContaining('Evening reviewed routine'), findsWidgets);
      await tester.tap(find.byKey(FardaTodayScreen.confirmDoseButtonKey));
      await tester.pumpAndSettle();
      expect(repository.lastWrittenId, 'evening-occurrence');
      expect(repository.eveningStatus, OccurrenceStatus.unconfirmed);
      expect(find.text('Your record.\nYour choice.'), findsOneWidget);
      expect(find.text('You’re all set.'), findsNothing);
      await tester.tap(find.byKey(FardaTodayScreen.confirmDoseButtonKey));
      await tester.pumpAndSettle();
      expect(repository.eveningStatus, OccurrenceStatus.taken);
      expect(repository.status, OccurrenceStatus.unconfirmed);
      expect(find.text('You’re all set.'), findsOneWidget);
      expect(find.text('Taken · You confirmed'), findsOneWidget);

      await tester.ensureVisible(find.text('Back to today'));
      await tester.tap(find.text('Back to today'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Taken · self-reported'), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(const Key('today_routine_occurrence')),
      );
      await tester.tap(find.byKey(const Key('today_routine_occurrence')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(FardaTodayRoutineCard.logDoseButtonKey),
        findsOneWidget,
      );
      expect(find.textContaining('Not yet confirmed'), findsWidgets);
      await tester.ensureVisible(
        find.byKey(const Key('today_routine_evening-occurrence')),
      );
      await tester.tap(
        find.byKey(const Key('today_routine_evening-occurrence')),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(FardaTodayRoutineCard.correctEntryButtonKey),
      );
      await tester.tap(find.byKey(FardaTodayRoutineCard.correctEntryButtonKey));
      await tester.pumpAndSettle();
      expect(find.textContaining('Let’s correct that.'), findsOneWidget);
    },
  );

  testWidgets('skip and snooze mutate only the selected routine', (
    tester,
  ) async {
    final repository = _MultipleRecordsRepository();
    await pumpEntry(tester, repository);
    await tester.ensureVisible(
      find.byKey(FardaTodayRoutineCard.moreOptionsButtonKey),
    );
    await tester.tap(find.byKey(FardaTodayRoutineCard.moreOptionsButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(FardaTodayScreen.recordSkippedButtonKey));
    await tester.pumpAndSettle();
    expect(repository.lastWrittenId, 'occurrence');
    expect(repository.status, OccurrenceStatus.skipped);
    expect(repository.eveningStatus, OccurrenceStatus.unconfirmed);

    await tester.ensureVisible(
      find.byKey(const Key('today_routine_evening-occurrence')),
    );
    await tester.tap(find.byKey(const Key('today_routine_evening-occurrence')));
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(
      tester.element(find.byKey(FardaTodayRoutineCard.snoozeButtonKey)),
      alignment: 0.25,
      alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(FardaTodayRoutineCard.snoozeButtonKey));
    await tester.pumpAndSettle();
    expect(repository.lastSnoozedId, 'evening-occurrence');
    expect(repository.status, OccurrenceStatus.skipped);
    expect(repository.eveningStatus, OccurrenceStatus.unconfirmed);
    expect(find.text('We’ll remind\nyou again.'), findsOneWidget);
    expect(
      find.text('Reminder snoozed. Your record is unconfirmed.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Back to today'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Snoozed · unconfirmed'), findsOneWidget);
  });

  testWidgets(
    'calendar distinguishes skipped and snoozed records and routes exact IDs',
    (tester) async {
      final repository =
          _MultipleRecordsRepository()
            ..status = OccurrenceStatus.skipped
            ..eveningSnoozedUntil = DateTime.now().add(
              const Duration(hours: 1),
            );
      await pumpEntry(tester, repository);

      await tester.tap(find.text('Calendar'));
      await tester.pumpAndSettle();

      expect(find.text('Evening reviewed routine'), findsOneWidget);
      expect(find.text('My reviewed routine'), findsOneWidget);
      expect(find.textContaining('Snoozed'), findsOneWidget);
      expect(find.textContaining('Skipped · recorded by you'), findsOneWidget);

      await tester.ensureVisible(find.text('Add an entry'));
      await tester.tap(find.text('Add an entry'));
      await tester.pumpAndSettle();
      expect(find.text('Your check-in.'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('Evening reviewed routine'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      final skippedCard = find.bySemanticsLabel(
        RegExp(r'My reviewed routine.*Skipped'),
      );
      await tester.ensureVisible(skippedCard);
      await tester.tap(skippedCard);
      await tester.pumpAndSettle();
      expect(find.text('Let’s correct that.'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('My reviewed routine'),
        ),
        findsOneWidget,
      );
    },
  );
}
