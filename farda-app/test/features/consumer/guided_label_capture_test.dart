import 'dart:async';
import 'dart:io';
import 'package:farda/features/consumer/consumer_controller.dart';
import 'package:farda/features/consumer/data/consumer_demo_repository.dart';
import 'package:farda/features/consumer/data/consumer_models.dart';
import 'package:farda/features/consumer/data/label_scan.dart';
import 'package:farda/features/consumer/guided_label_capture.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class ScanRepository extends ConsumerDemoRepository
    implements LabelScanRepository {
  int calls = 0;
  bool fail = false;
  Completer<LabelScanDraft>? pending;
  @override
  Future<LabelScanDraft> extractLabel(List<LabelPhoto> photos) async {
    calls++;
    if (pending != null) return pending!.future;
    if (fail) {
      throw const ConsumerRepositoryException(
        'Scan unavailable. Enter manually or retry.',
      );
    }
    return const LabelScanDraft(
      medicationName: 'Sample medication',
      directions: 'Exact label wording.',
    );
  }
}

void main() {
  final photo = LabelPhoto(
    bytes: File('test/fixtures/label-photo.png').readAsBytesSync(),
    mimeType: 'image/png',
  );
  Future<void> mount(
    WidgetTester tester,
    ScanRepository repo, {
    ValueChanged<LabelScanDraft?>? result,
    ValueChanged<ConsumerController>? onController,
    Future<LabelPhoto?> Function(BuildContext)? takePhoto,
  }) async {
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = ConsumerController(repo);
    addTearDown(controller.dispose);
    onController?.call(controller);
    await tester.pumpWidget(
      MaterialApp(
        builder:
            (_, child) => MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 800),
                textScaler: TextScaler.linear(1.3),
              ),
              child: child!,
            ),
        home: Builder(
          builder:
              (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    final value = await Navigator.push<LabelScanDraft>(
                      context,
                      MaterialPageRoute(
                        builder:
                            (_) => GuidedLabelCaptureScreen(
                              controller: controller,
                              takePhoto: takePhoto ?? (_) async => photo,
                            ),
                      ),
                    );
                    result?.call(value);
                  },
                  child: const Text('Open scanner'),
                ),
              ),
        ),
      ),
    );
    await tester.tap(find.text('Open scanner'));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String text) async {
    await tester.scrollUntilVisible(
      find.text(text),
      220,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  testWidgets('manual fallback never asks for camera or uploads', (
    tester,
  ) async {
    final repo = ScanRepository();
    LabelScanDraft? draft;
    await mount(tester, repo, result: (value) => draft = value);
    await tap(tester, 'Enter manually instead');
    expect(draft?.manualEntry, true);
    expect(repo.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('coverage confirmation gates extraction and retakes reset it', (
    tester,
  ) async {
    final repo = ScanRepository();
    await mount(tester, repo);
    await tap(tester, 'Take first photo');
    await tester.scrollUntilVisible(
      find.text('Review label details'),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Review label details'),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Review label details'),
          )
          .onPressed,
      isNotNull,
    );
    await tester.drag(find.byType(ListView), const Offset(0, 700));
    await tester.pumpAndSettle();
    await tap(tester, 'Retake');
    await tester.scrollUntilVisible(
      find.text('Review label details'),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Review label details'),
          )
          .onPressed,
      isNull,
    );
    expect(repo.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scan failure retains photos and easy manual fallback', (
    tester,
  ) async {
    final repo = ScanRepository()..fail = true;
    LabelScanDraft? draft;
    await mount(tester, repo, result: (value) => draft = value);
    await tap(tester, 'Take first photo');
    await tester.scrollUntilVisible(
      find.byType(CheckboxListTile),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tap(tester, 'Review label details');
    expect(repo.calls, 1);
    expect(
      find.text('Scan unavailable. Enter manually or retry.'),
      findsOneWidget,
    );
    await tap(tester, 'Enter manually instead');
    expect(draft?.manualEntry, true);
    expect(tester.takeException(), isNull);
  });

  testWidgets('session expiry discards a late gallery or camera result', (
    tester,
  ) async {
    final repo = ScanRepository();
    final pending = Completer<LabelPhoto?>();
    late ConsumerController controller;
    await mount(
      tester,
      repo,
      onController: (value) => controller = value,
      takePhoto: (_) => pending.future,
    );
    await tester.scrollUntilVisible(find.text('Take first photo'), 180);
    await tester.tap(find.text('Take first photo'));
    await tester.pump();
    await controller.mutate(() async {
      throw const ConsumerRepositoryException(
        'Session ended',
        sessionExpired: true,
      );
    });
    await tester.pumpAndSettle();
    pending.complete(photo);
    await tester.pumpAndSettle();
    expect(find.text('Sign in again to continue'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(find.text('Review label details'), findsNothing);
    expect(repo.calls, 0);
  });

  testWidgets('manual fallback ignores an extraction still in flight', (
    tester,
  ) async {
    final repo = ScanRepository()..pending = Completer<LabelScanDraft>();
    LabelScanDraft? draft;
    await mount(tester, repo, result: (value) => draft = value);
    await tap(tester, 'Take first photo');
    await tester.scrollUntilVisible(find.byType(CheckboxListTile), 180);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Review label details'), 180);
    await tester.tap(find.text('Review label details'));
    await tester.pump();
    await tester.scrollUntilVisible(find.text('Enter manually instead'), 180);
    await tester.tap(find.text('Enter manually instead'));
    await tester.pumpAndSettle();
    repo.pending!.complete(
      const LabelScanDraft(medicationName: 'Late private label'),
    );
    await tester.pumpAndSettle();
    expect(draft?.manualEntry, true);
    expect(find.text('Open scanner'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('camera unavailable keeps manual route accessible', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/camera'),
      (_) async => <Object>[],
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/camera'),
        null,
      ),
    );
    await tester.pumpWidget(
      const MaterialApp(home: LabelViewfinderScreen(photoNumber: 2)),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.textContaining('Camera unavailable.'),
      180,
    );
    expect(find.textContaining('Camera unavailable.'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Enter manually instead'), 180);
    expect(find.text('Enter manually instead'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
