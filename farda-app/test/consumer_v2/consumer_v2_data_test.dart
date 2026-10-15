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
      prescriptions: hasOccurrence
          ? const [ConsumerPrescription(id: 'rx', name: 'My reviewed routine')]
          : const [],
      occurrences: hasOccurrence && !due.isBefore(from) && due.isBefore(to)
          ? [ConsumerOccurrence(
              id: 'occurrence',
              prescriptionId: 'rx',
              scheduledFor: due,
              status: status,
              revision: revision,
            )]
          : const [],
      fetchedAt: now,
    );
  }

  @override
  Future<void> recordOccurrence(ConsumerOccurrenceUpdate update) async {
    writes++;
    if (failNextWrite) {
      failNextWrite = false;
      throw const ConsumerRepositoryException('The server did not save this entry.');
    }
    if (update.id != 'occurrence' || update.expectedRevision != revision) {
      throw const ConsumerRepositoryException('This record changed. Refresh it.');
    }
    status = update.status!;
    revision++;
  }
}

void main() {
  Future<void> pumpEntry(WidgetTester tester, _RecordsRepository repository) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: ConsumerV2Entry(repository: repository),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('empty account never displays a sample dose or a save control',
      (tester) async {
    await pumpEntry(tester, _RecordsRepository(hasOccurrence: false));
    expect(find.text('No routine on this day'), findsOneWidget);
    expect(find.byKey(FardaTodayRoutineCard.logDoseButtonKey), findsNothing);
  });

  testWidgets('failed write stays unconfirmed; accepted write survives reload',
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
    expect(find.textContaining('Not yet confirmed'), findsWidgets);
    expect(find.byKey(FardaTodayRoutineCard.logDoseButtonKey), findsOneWidget);

    await tester.ensureVisible(log);
    await tester.tap(log);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(FardaTodayScreen.confirmDoseButtonKey));
    await tester.pumpAndSettle();
    expect(repository.status, OccurrenceStatus.taken);
    expect(repository.writes, 2);
    expect(find.textContaining('You confirmed'), findsOneWidget);

    await tester.tap(find.text('Calendar'));
    await tester.pumpAndSettle();
    expect(find.text('My reviewed routine'), findsOneWidget);
    expect(find.text('You recorded this dose as taken.'), findsOneWidget);
  });
}
