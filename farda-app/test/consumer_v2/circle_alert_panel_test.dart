import 'dart:async';
import 'package:farda/application/authentication/storage/auth_storage.dart';
import 'dart:io';
import 'package:farda/consumer_v2/design_system/farda_consumer_tokens.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:farda/consumer_v2/screens/you/circle_alert_panel.dart';
import 'package:farda/features/consumer/data/circle_alerts.dart';
import 'package:farda/features/consumer/data/circle_models.dart';

class Alerts implements CircleAlertsRepository {
  CircleAlertPolicy? saved;
  bool? consent;
  Completer<CircleAlertPolicy>? pending;
  @override
  Future<CircleAlertPolicy> loadCircleAlertPolicy(
    String id, {
    bool recipient = false,
  }) async => pending == null ? const CircleAlertPolicy() : pending!.future;
  @override
  Future<void> saveCircleAlertPolicy(
    String id,
    CircleAlertPolicy policy,
  ) async {
    saved = policy;
  }

  @override
  Future<void> setCircleAlertConsent(String id, bool value) async {
    consent = value;
  }

  @override
  Future<void> readCircleAlert(String id) async {}
  @override
  Future<List<CircleAlert>> loadCircleAlerts() async => [
    CircleAlert(
      id: 'a',
      owner: const CirclePerson(id: 'o', displayName: 'Sam'),
      createdAt: DateTime(2026, 10, 16, 9),
    ),
  ];
}

void main() {
  testWidgets(
    'session revision synchronously clears inbox with same repository',
    (tester) async {
      final repo = Alerts();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CircleAlertPanel(repository: repo, isCurrent: () => true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sam'), findsOneWidget);
      AuthStorage.sessionRevision.value++;
      await tester.pump();
      expect(find.text('Sam'), findsNothing);
      expect(find.text('No confirmation yet'), findsNothing);
      expect(
        find.text('Your account changed. Close this view to continue.'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'session revision rejects pending settings with same repository',
    (tester) async {
      final repo = Alerts()..pending = Completer<CircleAlertPolicy>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CircleAlertPanel(
              repository: repo,
              isCurrent: () => true,
              grantId: 'g',
              personName: 'Private Sam',
            ),
          ),
        ),
      );
      AuthStorage.sessionRevision.value++;
      repo.pending!.complete(const CircleAlertPolicy(enabled: true));
      await tester.pumpAndSettle();
      expect(find.text('With Private Sam'), findsNothing);
      expect(find.byType(SwitchListTile), findsNothing);
    },
  );
  test('reminder-hidden alert accepts null scheduledFor', () {
    final alert = CircleAlert.fromJson({
      'id': 'a',
      'owner': {'id': 'o', 'displayName': 'Sam'},
      'createdAt': '2026-10-16T09:00:00Z',
      'scheduledFor': null,
    });
    expect(alert.scheduledFor, isNull);
  });

  Future<void> pump(
    WidgetTester tester,
    Alerts repo, {
    bool recipient = false,
    bool inbox = false,
    bool Function()? current,
  }) async {
    final font = FontLoader('Outfit')
      ..addFont(rootBundle.load('assets/fonts/Outfit-Regular.ttf'));
    await font.load();
    await (FontLoader('MaterialIcons')..addFont(
      Future.value(
        File(
          '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        ).readAsBytesSync().buffer.asByteData(),
      ),
    )).load();
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: FardaConsumerTheme.from(ThemeData(fontFamily: 'Outfit')),
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 900),
              textScaler: TextScaler.linear(1.3),
            ),
            child: CircleAlertPanel(
              repository: repo,
              isCurrent: current ?? () => true,
              grantId: inbox ? null : 'g',
              personName: 'Sam',
              recipient: recipient,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a delayed response cannot reveal policy after account change', (
    tester,
  ) async {
    final repo = Alerts()..pending = Completer<CircleAlertPolicy>();
    var active = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CircleAlertPanel(
            repository: repo,
            isCurrent: () => active,
            grantId: 'g',
            personName: 'Sam',
          ),
        ),
      ),
    );
    active = false;
    repo.pending!.complete(
      const CircleAlertPolicy(enabled: true, recipientConsented: true),
    );
    await tester.pump();
    expect(find.text('Both people have opted in.'), findsNothing);
    expect(find.byType(SwitchListTile), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('owner starts opted out and renders at 320 / 1.3', (
    tester,
  ) async {
    final repo = Alerts();
    await pump(tester, repo);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );
    expect(
      find.text('Check-ins stay off until both people opt in.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('../visual_qa/goldens/320-circle-alert-settings.png'),
    );
  });
  testWidgets('recipient explicitly opts in without mutating owner policy', (
    tester,
  ) async {
    final repo = Alerts();
    await pump(tester, repo, recipient: true);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save preferences'));
    await tester.tap(find.text('Save preferences'));
    await tester.pumpAndSettle();
    expect(repo.consent, isTrue);
    expect(repo.saved, isNull);
    expect(tester.takeException(), isNull);
  });
  testWidgets('inbox is read-only and uses uncertainty language', (
    tester,
  ) async {
    await pump(tester, Alerts(), inbox: true);
    expect(find.text('No confirmation yet'), findsOneWidget);
    expect(find.text('Mark as read'), findsOneWidget);
    expect(find.text('Mark taken'), findsNothing);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('../visual_qa/goldens/320-circle-alert-inbox.png'),
    );
  });
}
