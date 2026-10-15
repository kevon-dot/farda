import 'package:farda/consumer_v2/consumer_v2_entry.dart';
import 'package:farda/consumer_v2/screens/you/you_models.dart';
import 'package:farda/features/consumer/data/consumer_demo_repository.dart';
import 'package:farda/features/consumer/data/consumer_models.dart';
import 'package:farda/features/consumer/prescription_onboarding.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _AccountRepository extends ConsumerDemoRepository {
  final medications = <ConsumerPrescription>[];
  @override
  bool get isDemo => false;
  @override
  Future<void> savePrescription(ConsumerPrescriptionDraft draft) async {
    medications.add(
      ConsumerPrescription(
        id: 'saved-${medications.length}',
        name: draft.name,
        directions: draft.directions,
        times: draft.remindersEnabled ? draft.times : [],
        labelReviewed: true,
      ),
    );
  }

  @override
  Future<ConsumerSnapshot> loadSnapshot({
    required DateTime from,
    required DateTime to,
  }) async => ConsumerSnapshot(
    prescriptions: List.of(medications),
    capabilities: const ConsumerCapabilities(
      inventoryEnabled: true,
      refillsEnabled: true,
    ),
    fetchedAt: DateTime.now(),
  );
}

Future<void> _tap(WidgetTester tester, String label) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text(label).last);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> _mount(
  WidgetTester tester,
  _AccountRepository repository, {
  int tab = 0,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: ConsumerV2Entry(repository: repository, initialIndex: tab),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'empty authenticated Today adds a medication and refreshes shell',
    (tester) async {
      final repository = _AccountRepository();
      await _mount(tester, repository);
      expect(find.text('No routine on this day'), findsNothing);
      await _tap(tester, 'Add medication');
      expect(find.byType(PrescriptionOnboarding), findsOneWidget);
      await _tap(tester, 'Enter manually');
      await tester.enterText(
        find.byType(TextField).first,
        'My reviewed medication',
      );
      await _tap(tester, 'Continue');
      await tester.enterText(
        find.byType(TextField).first,
        'Use as directed on my label.',
      );
      await _tap(tester, 'Continue');
      await _tap(tester, 'Continue');
      await _tap(tester, 'No daily reminders');
      await _tap(tester, 'Review my routine');
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await _tap(tester, 'Save my routine');
      await _tap(tester, 'Done');
      expect(find.byType(PrescriptionOnboarding), findsNothing);
      expect(find.text('No routine on this day'), findsOneWidget);
      expect(repository.medications.single.times, isEmpty);
      await _tap(tester, 'Refills');
      expect(find.text('My reviewed medication'), findsWidgets);
    },
  );

  testWidgets('empty authenticated Refills launches onboarding directly', (
    tester,
  ) async {
    await _mount(tester, _AccountRepository(), tab: 2);
    await _tap(tester, 'Add medication');
    expect(find.byType(PrescriptionOnboarding), findsOneWidget);
    await _tap(tester, 'Enter manually');
    expect(find.text('What’s on your label?'), findsOneWidget);
  });

  testWidgets(
    'saved prescription without today dose reviews existing and can add another',
    (tester) async {
      final repository =
          _AccountRepository()
            ..medications.add(
              const ConsumerPrescription(
                id: 'existing',
                name: 'Existing medication',
                directions: 'Reviewed directions',
                labelReviewed: true,
              ),
            );
      await _mount(tester, repository);
      expect(find.text('No routine on this day'), findsOneWidget);
      expect(find.text('Add medication'), findsNothing);
      await _tap(tester, 'No routine on this day');
      expect(find.text('Existing medication'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
      await _tap(tester, 'Add medication');
      expect(find.byType(PrescriptionOnboarding), findsOneWidget);
      expect(repository.medications.length, 1);
    },
  );

  testWidgets(
    'You routine offers additional medication without replacing edit',
    (tester) async {
      final repository =
          _AccountRepository()
            ..medications.add(
              const ConsumerPrescription(
                id: 'existing',
                name: 'Existing medication',
                labelReviewed: true,
              ),
            );
      await _mount(tester, repository, tab: 3);
      await tester.ensureVisible(find.byKey(FardaYouKeys.routineLink));
      await tester.tap(find.byKey(FardaYouKeys.routineLink));
      await tester.pumpAndSettle();
      expect(find.text('Edit'), findsOneWidget);
      await _tap(tester, 'Add medication');
      expect(find.byType(PrescriptionOnboarding), findsOneWidget);
    },
  );
}
