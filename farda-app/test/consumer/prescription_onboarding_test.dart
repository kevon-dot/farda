import 'package:farda/features/consumer/consumer_controller.dart';
import 'package:farda/features/consumer/data/consumer_demo_repository.dart';
import 'package:farda/features/consumer/data/consumer_models.dart';
import 'package:farda/features/consumer/data/label_scan.dart';
import 'package:farda/features/consumer/prescription_onboarding.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class RecordingRepository extends ConsumerDemoRepository {
  final saves = <ConsumerPrescriptionDraft>[];
  bool fail = false;
  @override
  Future<void> savePrescription(ConsumerPrescriptionDraft draft) async {
    saves.add(draft);
    if (fail) throw const ConsumerRepositoryException('Offline. Try again.');
    await super.savePrescription(draft);
  }
}

Future<void> mount(
  WidgetTester tester,
  RecordingRepository repository, {
  Future<LabelScanDraft?> Function(BuildContext)? scan,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(320, 740);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final controller = ConsumerController(repository);
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      builder:
          (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
      home: PrescriptionOnboarding(controller: controller, scanLabel: scan),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, String text) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  final finder = find.text(text);
  await tester.ensureVisible(finder.last);
  await tester.pumpAndSettle();
  await tester.tap(finder.last);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> fillManual(
  WidgetTester tester, {
  String directions = 'Use only as directed on the original label.',
}) async {
  await tap(tester, 'Enter manually');
  await tester.enterText(find.byType(TextField).first, 'Example 10 mg tablets');
  await tap(tester, 'Continue');
  await tester.enterText(find.byType(TextField).first, directions);
  await tap(tester, 'Continue');
  await tap(tester, 'Continue');
}

void main() {
  testWidgets(
    'manual long label keeps draft on back and requires final confirmation',
    (tester) async {
      final repository = RecordingRepository();
      await mount(tester, repository);
      final directions = List.filled(
        18,
        'Exact printed instruction; keep this whole sentence.',
      ).join(' ');
      await fillManual(tester, directions: directions);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        directions,
      );
      await tap(tester, 'Continue');
      await tap(tester, 'Continue');
      await tap(tester, 'No daily reminders');
      await tap(tester, 'Review my routine');
      expect(repository.saves, isEmpty);
      final save = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Save my routine'),
      );
      expect(save.onPressed, isNull);
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tap(tester, 'Save my routine');
      expect(repository.saves.single.directions, directions);
      expect(repository.saves.single.toJson().containsKey('schedule'), isFalse);
      expect(find.text('Your medication is saved.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('rescan fills blank fields without replacing corrections', (
    tester,
  ) async {
    final repository = RecordingRepository();
    await mount(
      tester,
      repository,
      scan:
          (_) async => const LabelScanDraft(
            medicationName: 'OCR name',
            directions: 'OCR directions',
          ),
    );
    await tap(tester, 'Enter manually');
    await tester.enterText(find.byType(TextField).first, 'User corrected name');
    await tap(tester, 'Scan another section');
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      'User corrected name',
    );
    await tap(tester, 'Continue');
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      'OCR directions',
    );
    expect(repository.saves, isEmpty);
  });

  testWidgets('over-limit OCR text remains intact and blocks continuation', (
    tester,
  ) async {
    final repository = RecordingRepository();
    final longText = List.filled(2100, 'x').join();
    await mount(
      tester,
      repository,
      scan:
          (_) async =>
              LabelScanDraft(medicationName: 'Example', directions: longText),
    );
    await tap(tester, 'Scan label');
    await tap(tester, 'Continue');
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      longText,
    );
    await tap(tester, 'Continue');
    expect(find.textContaining('Directions exceed'), findsOneWidget);
    expect(repository.saves, isEmpty);
  });

  testWidgets(
    'retry preserves idempotency key and editing invalidates confirmation',
    (tester) async {
      final repository = RecordingRepository()..fail = true;
      await mount(tester, repository);
      await fillManual(tester);
      await tap(tester, 'No daily reminders');
      await tap(tester, 'Review my routine');
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tap(tester, 'Save my routine');
      expect(find.text('Offline. Try again.'), findsOneWidget);
      await tap(tester, 'Save my routine');
      expect(repository.saves.length, 2);
      expect(
        repository.saves.first.clientRequestId,
        repository.saves.last.clientRequestId,
      );
      await tap(tester, 'Go back and edit');
      await tester.enterText(
        find.byType(TextField).first,
        'Corrected medicine',
      );
      await tap(tester, 'Continue');
      await tap(tester, 'Continue');
      await tap(tester, 'Continue');
      await tap(tester, 'Review my routine');
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isFalse,
      );
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tap(tester, 'Save my routine');
      expect(
        repository.saves.last.clientRequestId,
        isNot(repository.saves.first.clientRequestId),
      );
    },
  );

  testWidgets('daily reminders require an explicit time selection', (
    tester,
  ) async {
    final repository = RecordingRepository();
    await mount(tester, repository);
    await fillManual(tester);
    await tap(tester, 'Daily');
    await tap(tester, 'Review my routine');
    expect(find.text('Choose at least one reminder time.'), findsOneWidget);
    expect(repository.saves, isEmpty);
    await tap(tester, 'Choose reminder time');
    await tap(tester, 'OK');
    await tap(tester, 'Review my routine');
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tap(tester, 'Save my routine');
    expect(repository.saves.single.remindersEnabled, isTrue);
    expect(repository.saves.single.toJson()['schedule'], isA<Map>());
    expect(repository.saves.single.times, ['09:00']);
  });

  test(
    'record-only saves generate no daily occurrences even with stale times',
    () async {
      final repository = ConsumerDemoRepository();
      final now = DateTime.now();
      final draft = ConsumerPrescriptionDraft(
        name: 'As needed',
        directions: 'Exact directions',
        labelReviewed: true,
        timeZone: 'UTC',
        times: const ['09:00'],
        startDate: now,
        clientRequestId: 'test-record-only',
        remindersEnabled: false,
      );
      expect(draft.validationError, isNull);
      await repository.savePrescription(draft);
      final snapshot = await repository.loadSnapshot(
        from: DateTime(now.year, now.month, now.day),
        to: DateTime(now.year, now.month, now.day + 30),
      );
      final added = snapshot.prescriptions.singleWhere(
        (item) => item.name == 'As needed',
      );
      expect(added.times, isEmpty);
      expect(
        snapshot.occurrences.where((item) => item.prescriptionId == added.id),
        isEmpty,
      );
    },
  );
}
