import 'dart:io';

import 'package:farda/consumer_v2/consumer_v2_entry.dart';
import 'package:farda/consumer_v2/screens/today/farda_today_screen.dart';
import 'package:farda/consumer_v2/screens/today/today_routine_card.dart';
import 'package:farda/consumer_v2/screens/you/you_models.dart';
import 'package:farda/features/consumer/data/consumer_demo_repository.dart';
import 'package:farda/features/consumer/data/consumer_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Actual Flutter frames of the authenticated four-tab shell. This fixture is
/// entirely in test code; no sample records are added to the app route.
class _VisualFixtureRepository extends ConsumerDemoRepository {
  _VisualFixtureRepository({
    this.singleRoutine = false,
    this.receivedRefill = false,
  });

  final bool singleRoutine;
  final bool receivedRefill;
  OccurrenceStatus _morningStatus = OccurrenceStatus.unconfirmed;
  DateTime? _morningRecordedAt;
  DateTime? _morningSnoozedUntil;

  @override
  Future<void> recordOccurrence(ConsumerOccurrenceUpdate update) async {
    if (update.id != 'morning-today') return;
    _morningStatus = update.status ?? OccurrenceStatus.unconfirmed;
    _morningRecordedAt = DateTime.now();
    _morningSnoozedUntil = null;
  }

  @override
  Future<void> snoozeOccurrence(String id, Duration duration) async {
    if (id == 'morning-today') {
      _morningSnoozedUntil = DateTime.now().add(duration);
    }
  }

  @override
  bool get isDemo => false;

  @override
  Future<ConsumerSnapshot> loadSnapshot({
    required DateTime from,
    required DateTime to,
  }) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final occurrences = <ConsumerOccurrence>[
      ConsumerOccurrence(
        id: 'yesterday',
        prescriptionId: 'morning',
        scheduledFor: today
            .subtract(const Duration(days: 1))
            .add(const Duration(hours: 9)),
        status: OccurrenceStatus.taken,
      ),
      ConsumerOccurrence(
        id: 'morning-today',
        prescriptionId: 'morning',
        scheduledFor: today.add(const Duration(hours: 9)),
        status: _morningStatus,
        recordedAt: _morningRecordedAt,
        snoozedUntil: _morningSnoozedUntil,
      ),
      if (!singleRoutine)
        ConsumerOccurrence(
          id: 'evening-today',
          prescriptionId: 'evening',
          scheduledFor: today.add(const Duration(hours: 20)),
        ),
    ];
    return ConsumerSnapshot(
      prescriptions: [
        const ConsumerPrescription(
          id: 'morning',
          name: 'Morning routine',
          pharmacy: 'Your pharmacy',
          times: ['09:00'],
          labelReviewed: true,
        ),
        if (!singleRoutine)
          const ConsumerPrescription(
            id: 'evening',
            name: 'Evening routine',
            times: ['20:00'],
            labelReviewed: true,
          ),
      ],
      occurrences:
          occurrences
              .where(
                (item) =>
                    !item.scheduledFor.isBefore(from) &&
                    item.scheduledFor.isBefore(to),
              )
              .toList(),
      inventory: [
        ConsumerInventory(
          prescriptionId: 'morning',
          quantity: 12,
          dailyUnits: 1,
          countedAt: now,
          refillId: receivedRefill ? 'receipt-1' : null,
          stage: receivedRefill ? RefillStage.received : RefillStage.planning,
          plannedFor: today.add(const Duration(days: 5)),
        ),
      ],
      capabilities: const ConsumerCapabilities(
        inventoryEnabled: true,
        refillsEnabled: true,
      ),
      fetchedAt: now,
    );
  }
}

/// Date labels reflect the current day; export captures only when explicitly
/// requested. Normal CI runs check rendered layout and interactions without
/// comparing yesterday's pixels.
const _exportVisuals = bool.fromEnvironment('UPDATE_VISUALS');

Future<void> _pumpVisualFrame(
  WidgetTester tester, {
  required Size size,
  double textScale = 1,
  int tab = 0,
  bool singleRoutine = false,
  bool receivedRefill = false,
}) async {
  if (_exportVisuals) debugDisableShadows = false;
  final fonts = FontLoader('Outfit');
  for (final weight in ['Light', 'Regular', 'Medium', 'SemiBold', 'Bold']) {
    fonts.addFont(rootBundle.load('assets/fonts/Outfit-$weight.ttf'));
  }
  await fonts.load();
  final flutterRoot = Platform.environment['FLUTTER_ROOT']!;
  final iconBytes =
      File(
        '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ).readAsBytesSync();
  await (FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(iconBytes)))).load();

  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      // Routes pushed above the consumer shell inherit the application font.
      // Flutter tests otherwise substitute Ahem for the default sans font.
      theme: ThemeData(fontFamily: 'Outfit'),
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            padding: const EdgeInsets.only(top: 48, bottom: 20),
            viewPadding: const EdgeInsets.only(top: 48, bottom: 20),
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        );
      },
      home: ConsumerV2Entry(
        initialIndex: tab,
        repository: _VisualFixtureRepository(
          singleRoutine: singleRoutine,
          receivedRefill: receivedRefill,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> _checkFrame(WidgetTester tester, String name) async {
  expect(tester.takeException(), isNull);
  if (_exportVisuals) {
    try {
      debugDisableShadows = false;
      await tester.pump();
      await expectLater(
        // The app-level boundary includes Navigator overlays (dialogs and
        // bottom sheets) that sit outside ConsumerV2Entry's subtree.
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/$name.png'),
      );
    } finally {
      debugDisableShadows = true;
    }
  }
}

void main() {
  for (final layout in <({String name, Size size, double textScale})>[
    (name: '390', size: const Size(390, 844), textScale: 1),
    (name: '320-large-text', size: const Size(320, 844), textScale: 1.3),
  ]) {
    for (var tab = 0; tab < 4; tab++) {
      testWidgets('${layout.name} tab $tab', (tester) async {
        await _pumpVisualFrame(
          tester,
          size: layout.size,
          textScale: layout.textScale,
          tab: tab,
        );
        await _checkFrame(tester, '${layout.name}-tab-$tab');
      });
    }
  }

  for (final tab in [0, 1]) {
    testWidgets('390 single routine tab $tab', (tester) async {
      await _pumpVisualFrame(
        tester,
        size: const Size(390, 844),
        tab: tab,
        singleRoutine: true,
      );
      await _checkFrame(tester, '390-single-routine-tab-$tab');
    });
  }

  testWidgets('390 today check in', (tester) async {
    await _pumpVisualFrame(
      tester,
      size: const Size(390, 844),
      tab: 0,
      singleRoutine: true,
    );
    await tester.ensureVisible(
      find.byKey(FardaTodayRoutineCard.logDoseButtonKey),
    );
    await tester.tap(find.byKey(FardaTodayRoutineCard.logDoseButtonKey));
    await tester.pumpAndSettle();
    await _checkFrame(tester, '390-today-check-in');
  });

  testWidgets('320 today check in', (tester) async {
    await _pumpVisualFrame(
      tester,
      size: const Size(320, 844),
      textScale: 1.3,
      tab: 0,
      singleRoutine: true,
    );
    await tester.ensureVisible(
      find.byKey(FardaTodayRoutineCard.logDoseButtonKey),
    );
    await tester.tap(find.byKey(FardaTodayRoutineCard.logDoseButtonKey));
    await tester.pumpAndSettle();
    await _checkFrame(tester, '320-today-check-in');
  });

  testWidgets('390 today confirmed receipt', (tester) async {
    await _pumpVisualFrame(
      tester,
      size: const Size(390, 844),
      tab: 0,
      singleRoutine: true,
    );
    await tester.ensureVisible(
      find.byKey(FardaTodayRoutineCard.logDoseButtonKey),
    );
    await tester.tap(find.byKey(FardaTodayRoutineCard.logDoseButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(FardaTodayScreen.confirmDoseButtonKey));
    await tester.pumpAndSettle();
    await _checkFrame(tester, '390-today-confirmed-receipt');
  });

  testWidgets('390 today snoozed receipt', (tester) async {
    await _pumpVisualFrame(
      tester,
      size: const Size(390, 844),
      tab: 0,
      singleRoutine: true,
    );
    await tester.ensureVisible(
      find.byKey(FardaTodayRoutineCard.snoozeButtonKey),
    );
    await tester.tap(find.byKey(FardaTodayRoutineCard.snoozeButtonKey));
    await tester.pumpAndSettle();
    await _checkFrame(tester, '390-today-snoozed-receipt');
  });

  testWidgets('390 calendar lower month', (tester) async {
    await _pumpVisualFrame(tester, size: const Size(390, 844), tab: 1);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -460));
    await tester.pumpAndSettle();
    await _checkFrame(tester, '390-calendar-scrolled');
  });

  testWidgets('320 calendar lower month', (tester) async {
    await _pumpVisualFrame(
      tester,
      size: const Size(320, 844),
      textScale: 1.3,
      tab: 1,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -520));
    await tester.pumpAndSettle();
    await _checkFrame(tester, '320-calendar-scrolled');
  });

  for (final destination in <({String name, Key key})>[
    (name: 'routine', key: FardaYouKeys.routineLink),
    (name: 'reminders', key: FardaYouKeys.remindersLink),
    (name: 'vial', key: FardaYouKeys.vialLink),
    (name: 'circle', key: FardaYouKeys.circleLink),
  ]) {
    testWidgets('390 you ${destination.name}', (tester) async {
      await _pumpVisualFrame(tester, size: const Size(390, 844), tab: 3);
      await tester.tap(find.byKey(destination.key));
      await tester.pumpAndSettle();
      await _checkFrame(tester, '390-you-${destination.name}');
    });
  }

  for (final preview in <({String name, Key key})>[
    (name: 'live-activity', key: FardaYouKeys.liveActivityLink),
    (name: 'call', key: FardaYouKeys.callPreviewLink),
  ]) {
    testWidgets('390 you ${preview.name}', (tester) async {
      await _pumpVisualFrame(tester, size: const Size(390, 844), tab: 3);
      await tester.tap(find.byKey(FardaYouKeys.remindersLink));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(preview.key));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(preview.key));
      await tester.pumpAndSettle();
      await _checkFrame(tester, '390-you-${preview.name}');
    });
  }

  testWidgets('390 you live activity before', (tester) async {
    await _pumpVisualFrame(tester, size: const Size(390, 844), tab: 3);
    await tester.tap(find.byKey(FardaYouKeys.remindersLink));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(FardaYouKeys.liveActivityLink));
    await tester.tap(find.byKey(FardaYouKeys.liveActivityLink));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('10 min before'));
    await tester.tap(find.text('10 min before'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 550));
    await tester.pumpAndSettle();
    await _checkFrame(tester, '390-you-live-activity-before');
  });

  testWidgets('390 you call answered', (tester) async {
    await _pumpVisualFrame(tester, size: const Size(390, 844), tab: 3);
    await tester.tap(find.byKey(FardaYouKeys.remindersLink));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(FardaYouKeys.callPreviewLink));
    await tester.tap(find.byKey(FardaYouKeys.callPreviewLink));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Answer'));
    await tester.pumpAndSettle();
    await _checkFrame(tester, '390-you-call-answered');
  });

  testWidgets('390 calendar planned refill day', (tester) async {
    await _pumpVisualFrame(tester, size: const Size(390, 844), tab: 1);
    final now = DateTime.now();
    final planned = DateTime(now.year, now.month, now.day + 5);
    if (planned.month != now.month || planned.year != now.year) {
      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
    }
    final day = find.text('${planned.day}').last;
    await tester.ensureVisible(day);
    await tester.tap(day);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 550));
    await tester.pumpAndSettle();
    await _checkFrame(tester, '390-calendar-refill-day');
  });

  testWidgets('390 refills handoff', (tester) async {
    await _pumpVisualFrame(tester, size: const Size(390, 844), tab: 2);
    await tester.tap(find.text('Plan my refill').first);
    await tester.pumpAndSettle();
    await _checkFrame(tester, '390-refills-handoff');
  });

  testWidgets('320 refills handoff', (tester) async {
    await _pumpVisualFrame(
      tester,
      size: const Size(320, 844),
      textScale: 1.3,
      tab: 2,
    );
    await tester.tap(find.text('Plan my refill').first);
    await tester.pumpAndSettle();
    await _checkFrame(tester, '320-refills-handoff');
  });

  testWidgets('390 refills receipt dialog', (tester) async {
    await _pumpVisualFrame(
      tester,
      size: const Size(390, 844),
      tab: 2,
      receivedRefill: true,
    );
    await tester.tap(find.text('Reconcile my refill').first);
    await tester.pumpAndSettle();
    await _checkFrame(tester, '390-refills-receipt-dialog');
  });
}
