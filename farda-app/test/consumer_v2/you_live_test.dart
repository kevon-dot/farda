import 'package:farda/consumer_v2/screens/you/farda_you_screen.dart';
import 'package:farda/features/consumer/consumer_controller.dart';
import 'package:farda/features/consumer/data/consumer_demo_repository.dart';
import 'package:farda/features/consumer/data/consumer_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _YouRepository extends ConsumerDemoRepository {
  _YouRepository({this.hasRoutine = true});

  final bool hasRoutine;
  bool failNextWrite = false;
  int writes = 0;
  ConsumerReminderPreferences preferences = const ConsumerReminderPreferences();

  @override
  bool get isDemo => false;

  @override
  Future<ConsumerSnapshot> loadSnapshot({
    required DateTime from,
    required DateTime to,
  }) async => ConsumerSnapshot(
    prescriptions:
        hasRoutine
            ? const [
              ConsumerPrescription(
                id: 'rx',
                name: 'Actual saved routine',
                times: ['18:30'],
                timeZone: 'America/New_York',
                directions: 'One tablet as directed',
                labelReviewed: true,
              ),
            ]
            : const [],
    preferences: preferences,
    capabilities: const ConsumerCapabilities(
      liveActivityDeliveryEnabled: true,
      phoneVerified: true,
      voiceEnabled: true,
    ),
    callConsentText: 'I consent to automated reminder calls.',
    fetchedAt: DateTime.now(),
  );

  @override
  Future<void> saveReminderPreferences(
    ConsumerReminderPreferences next, {
    bool callConsent = false,
  }) async {
    writes++;
    if (failNextWrite) {
      failNextWrite = false;
      throw const ConsumerRepositoryException(
        'The server did not save this preference.',
      );
    }
    preferences = next;
  }
}

void main() {
  Future<ConsumerController> pumpYou(
    WidgetTester tester,
    _YouRepository repository, {
    FardaYouDestination destination = FardaYouDestination.overview,
    double width = 390,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = ConsumerController(repository);
    addTearDown(controller.dispose);
    await controller.load();
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 844),
            textScaler: TextScaler.linear(textScale),
          ),
          child: FardaYouScreen(
            controller: controller,
            initialDestination: destination,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets(
    'empty account does not show sample medication as a saved routine',
    (tester) async {
      await pumpYou(
        tester,
        _YouRepository(hasRoutine: false),
        destination: FardaYouDestination.routine,
      );
      expect(find.textContaining('No medication is saved'), findsOneWidget);
      expect(find.text('Daily medication'), findsNothing);
      expect(find.text('Evening routine'), findsNothing);
    },
  );

  testWidgets('You overview retains its previews at narrow large-text width', (
    tester,
  ) async {
    await pumpYou(tester, _YouRepository(), width: 320, textScale: 1.6);
    expect(find.byKey(FardaYouKeys.routineLink), findsOneWidget);
    expect(find.byKey(FardaYouKeys.vialLink), findsOneWidget);
    expect(find.byKey(FardaYouKeys.circleLink), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final destination in [
    FardaYouDestination.routine,
    FardaYouDestination.reminders,
    FardaYouDestination.vial,
    FardaYouDestination.circle,
  ]) {
    testWidgets('$destination scrolls at narrow large-text width', (
      tester,
    ) async {
      await pumpYou(
        tester,
        _YouRepository(),
        destination: destination,
        width: 320,
        textScale: 1.6,
      );
      expect(tester.takeException(), isNull);
      final back = find.text('Back to your space');
      await tester.ensureVisible(back);
      await tester.pumpAndSettle();
      expect(back, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('routine and quiet hours come from account records', (
    tester,
  ) async {
    await pumpYou(
      tester,
      _YouRepository(),
      destination: FardaYouDestination.routine,
    );
    expect(find.text('Actual saved routine'), findsOneWidget);
    expect(find.text('One tablet as directed'), findsOneWidget);
    expect(find.text('Every day · America/New_York'), findsOneWidget);
    expect(find.text('Evening routine'), findsNothing);
  });

  testWidgets(
    'authenticated reminder rhythm uses relative timing, not sample time',
    (tester) async {
      final repository = _YouRepository();
      await pumpYou(
        tester,
        repository,
        destination: FardaYouDestination.reminders,
      );
      expect(find.text('−10m'), findsOneWidget);
      expect(find.text('+10m'), findsOneWidget);
      expect(find.text('8:50'), findsNothing);
      expect(repository.writes, 0);
    },
  );

  testWidgets('vial and Circle are clearly local previews', (tester) async {
    final repository = _YouRepository();
    await pumpYou(tester, repository, destination: FardaYouDestination.vial);
    expect(find.text('Meet your vial.'), findsOneWidget);
    expect(find.text('A local preview. No device connects.'), findsOneWidget);
    expect(find.text('Pair your vial'), findsOneWidget);
    expect(repository.writes, 0);

    await tester.ensureVisible(find.text('Back to your space'));
    await tester.tap(find.text('Back to your space'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(FardaYouKeys.circleLink));
    await tester.tap(find.byKey(FardaYouKeys.circleLink));
    await tester.pumpAndSettle();
    expect(find.text('Try the settings. No invites are sent.'), findsOneWidget);
    expect(
      find.text('Preview only. Sharing starts off; no access is granted.'),
      findsOneWidget,
    );
    expect(repository.writes, 0);
  });

  testWidgets('vial preview completes after its three visible setup steps', (
    tester,
  ) async {
    final repository = _YouRepository();
    await pumpYou(tester, repository, destination: FardaYouDestination.vial);
    final advance = find.text('Simulate next setup step');
    for (var step = 0; step < 3; step++) {
      await tester.ensureVisible(advance);
      await tester.tap(advance);
      await tester.pumpAndSettle();
    }
    expect(find.text('Preview setup complete'), findsOneWidget);
    expect(advance, findsNothing);
    expect(repository.writes, 0);
  });

  testWidgets(
    'failed preference save keeps server value; accepted save reloads',
    (tester) async {
      final repository = _YouRepository()..failNextWrite = true;
      final controller = await pumpYou(
        tester,
        repository,
        destination: FardaYouDestination.reminders,
      );
      final toggle = find.byKey(FardaYouKeys.liveActivityToggle);
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(repository.writes, 1);
      expect(repository.preferences.liveActivitiesEnabled, false);
      expect(controller.snapshot!.preferences.liveActivitiesEnabled, false);
      expect(find.text('Off · 10 minutes before your routine'), findsOneWidget);

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(repository.writes, 2);
      expect(repository.preferences.liveActivitiesEnabled, true);
      expect(controller.snapshot!.preferences.liveActivitiesEnabled, true);
      expect(find.text('On · 10 minutes before your routine'), findsOneWidget);
    },
  );

  testWidgets('call opt-in needs explicit consent and a confirmed write', (
    tester,
  ) async {
    final repository = _YouRepository();
    final controller = await pumpYou(
      tester,
      repository,
      destination: FardaYouDestination.reminders,
    );
    final toggle = find.byKey(FardaYouKeys.callToggle);
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(repository.writes, 0);
    expect(find.text('I consent to automated reminder calls.'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(controller.snapshot!.preferences.callsEnabled, false);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.tap(find.text('I agree to reminder calls'));
    await tester.pumpAndSettle();
    expect(repository.writes, 1);
    expect(controller.snapshot!.preferences.callsEnabled, true);
  });

  testWidgets(
    'quiet hours and timezone only change after confirmed account save',
    (tester) async {
      final repository = _YouRepository()..failNextWrite = true;
      final controller = await pumpYou(
        tester,
        repository,
        destination: FardaYouDestination.reminders,
      );
      final edit = find.byKey(FardaYouKeys.quietHoursEdit);
      expect(
        find.text('Calls wait during quiet hours · America/Los_Angeles'),
        findsOneWidget,
      );

      Future<void> chooseEasternAndSave() async {
        await tester.ensureVisible(edit);
        await tester.tap(edit);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Eastern · New York'));
        await tester.pumpAndSettle();
        expect(find.text('QUIET HOURS START'), findsOneWidget);
        await tester.tap(find.text('OK').last);
        await tester.pumpAndSettle();
        expect(find.text('QUIET HOURS END'), findsOneWidget);
        await tester.tap(find.text('OK').last);
        await tester.pumpAndSettle();
      }

      await chooseEasternAndSave();
      expect(repository.writes, 1);
      expect(repository.preferences.timeZone, 'America/Los_Angeles');
      expect(controller.snapshot!.preferences.timeZone, 'America/Los_Angeles');
      expect(
        find.text('Calls wait during quiet hours · America/Los_Angeles'),
        findsOneWidget,
      );
      expect(
        find.text('The server did not save this preference.'),
        findsOneWidget,
      );

      await chooseEasternAndSave();
      expect(repository.writes, 2);
      expect(repository.preferences.timeZone, 'America/New_York');
      expect(controller.snapshot!.preferences.timeZone, 'America/New_York');
      expect(
        find.text('Calls wait during quiet hours · America/New_York'),
        findsOneWidget,
      );
    },
  );
}
