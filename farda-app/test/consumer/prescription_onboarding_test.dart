import 'dart:async';
import 'dart:io';
import 'package:farda/application/authentication/storage/auth_storage.dart';
import 'package:farda/features/consumer/guided_label_capture.dart';
import 'package:farda/features/consumer/consumer_controller.dart';
import 'package:farda/features/consumer/data/consumer_demo_repository.dart';
import 'package:farda/features/consumer/data/consumer_models.dart';
import 'package:farda/features/consumer/data/label_scan.dart';
import 'package:farda/features/consumer/prescription_onboarding.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class RecordingRepository extends ConsumerDemoRepository
    implements LabelScanRepository {
  final extraction = Completer<LabelScanDraft>();
  @override
  Future<LabelScanDraft> extractLabel(List<LabelPhoto> photos) =>
      extraction.future;
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
  ValueChanged<ConsumerController>? onController,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(320, 740);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final controller = ConsumerController(repository);
  addTearDown(controller.dispose);
  onController?.call(controller);
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

  testWidgets('missing scan directions stay blank until explicitly entered', (
    tester,
  ) async {
    final repository = RecordingRepository();
    await mount(
      tester,
      repository,
      scan: (_) async => const LabelScanDraft(medicationName: 'Printed name'),
    );
    await tap(tester, 'Scan label');
    expect(
      find.textContaining('Still needed: complete directions.'),
      findsOneWidget,
    );
    await tap(tester, 'Continue');
    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller!.text, isEmpty);
    expect(field.autocorrect, isFalse);
    expect(field.enableSuggestions, isFalse);
    await tap(tester, 'Continue');
    expect(
      find.textContaining('Copy the complete directions.'),
      findsOneWidget,
    );
    expect(repository.saves, isEmpty);
    await tester.enterText(find.byType(TextField).first, 'Exactly as printed');
    await tester.pump();
    expect(find.textContaining('Still needed:'), findsNothing);
  });

  testWidgets('session expiry clears draft and ignores a pending scan', (
    tester,
  ) async {
    final repository = RecordingRepository();
    final pending = Completer<LabelScanDraft?>();
    late ConsumerController controller;
    var scans = 0;
    await mount(
      tester,
      repository,
      onController: (value) => controller = value,
      scan: (_) {
        scans++;
        return pending.future;
      },
    );
    await tap(tester, 'Enter manually');
    await tester.enterText(find.byType(TextField).first, 'Private medication');
    await tester.ensureVisible(find.text('Scan another section'));
    await tester.tap(find.text('Scan another section'));
    await tester.pump();
    expect(
      tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, 'Scan another section'),
          )
          .onPressed,
      isNull,
    );
    await controller.mutate(() async {
      throw const ConsumerRepositoryException(
        'Session ended',
        sessionExpired: true,
      );
    });
    await tester.pumpAndSettle();
    expect(find.text('Sign in again to continue'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    pending.complete(
      const LabelScanDraft(
        medicationName: 'Late result',
        directions: 'Unconfirmed',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Late result'), findsNothing);
    expect(scans, 1);
    expect(repository.saves, isEmpty);
  });

  for (final lateSuccess in [false, true]) {
    testWidgets(
      'account swap clears parent draft after reload and late OCR ${lateSuccess ? 'success' : 'sessionChanged'}',
      (tester) async {
        final repository = RecordingRepository();
        late ConsumerController controller;
        final photo = LabelPhoto(
          bytes: File('test/fixtures/label-photo.png').readAsBytesSync(),
          mimeType: 'image/png',
        );
        await mount(
          tester,
          repository,
          onController: (value) => controller = value,
          scan:
              (context) => Navigator.of(context).push<LabelScanDraft>(
                MaterialPageRoute(
                  builder:
                      (_) => GuidedLabelCaptureScreen(
                        controller: controller,
                        takePhoto: (_) async => photo,
                      ),
                ),
              ),
        );
        await tap(tester, 'Enter manually');
        final name =
            tester.widget<TextField>(find.byType(TextField).first).controller!;
        await tester.enterText(
          find.byType(TextField).first,
          'Account A private medicine',
        );
        await tap(tester, 'Continue');
        final directions =
            tester.widget<TextField>(find.byType(TextField).first).controller!;
        await tester.enterText(
          find.byType(TextField).first,
          'Account A printed directions',
        );
        await tap(tester, 'Scan another section');
        await tester.scrollUntilVisible(find.text('Take first photo'), 180);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Take first photo'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.byType(CheckboxListTile), 180);
        await tester.pumpAndSettle();
        await tester.tap(find.byType(CheckboxListTile));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.text('Review label details'), 180);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Review label details'));
        await tester.pump();

        // AuthStorage publishes an A→B swap while OCR still belongs to A.
        // The same controller then loads B successfully: expiry alone cannot guard A.
        AuthStorage.sessionRevision.value++;
        await controller.load();
        expect(controller.sessionExpired, false);
        await tester.pumpAndSettle();
        expect(name.text, isEmpty);
        expect(directions.text, isEmpty);
        expect(find.byType(Image), findsNothing);
        if (lateSuccess) {
          repository.extraction.complete(
            const LabelScanDraft(
              medicationName: 'Account A late OCR',
              directions: 'Account A late instructions',
            ),
          );
        } else {
          repository.extraction.completeError(
            const ConsumerRepositoryException(
              'Your account changed. Reopen the scanner.',
              sessionExpired: true,
              sessionChanged: true,
            ),
          );
        }
        await tester.pumpAndSettle();
        await tap(tester, 'Close capture');
        expect(find.text('Sign in again to continue'), findsOneWidget);
        expect(find.byType(TextField), findsNothing);
        expect(find.text('Save my routine'), findsNothing);
        expect(find.textContaining('Account A'), findsNothing);
        expect(repository.saves, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

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
