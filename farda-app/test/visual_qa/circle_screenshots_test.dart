import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:farda/consumer_v2/design_system/farda_consumer_tokens.dart';
import 'package:farda/consumer_v2/screens/you/farda_circle_screen.dart';
import 'package:farda/features/consumer/data/consumer_demo_repository.dart';
import 'package:farda/features/consumer/data/circle_models.dart';

class _CircleFixture extends ConsumerDemoRepository {
  _CircleFixture({this.deviceEvidence = false});
  final bool deviceEvidence;
  @override
  bool get isDemo => false;
  static const permissions = CirclePermissions(
    doseStatus: true,
    reminders: true,
  );
  final time = DateTime(2026, 10, 16, 9, 4);
  CircleMember get member => CircleMember(
    id: 'fixture-access',
    person: const CirclePerson(id: 'fixture-recipient', displayName: 'Alex'),
    permissions: permissions,
    acceptedAt: time,
    updatedAt: time,
  );
  CircleInvitation get invitation => CircleInvitation(
    id: 'fixture-invite',
    person: const CirclePerson(id: 'fixture-owner', displayName: 'Sam'),
    permissions: permissions,
    createdAt: time,
    expiresAt: time.add(const Duration(days: 7)),
    inviteCode: 'fixture-invitation-code-0123456789-abcdefghijklmnop',
  );
  @override
  Future<List<CircleInvitation>> loadCircleInvitations() async => [invitation];
  @override
  Future<CircleInvitation> inviteToCircle(
    String phone,
    CirclePermissions permissions,
  ) async => invitation;
  @override
  Future<CircleOverview> loadCircle() async =>
      CircleOverview(pending: [], members: [member]);
  @override
  Future<List<SharedCircle>> loadSharedCircles() async => [
    SharedCircle(
      access: member,
      owner: const CirclePerson(id: 'fixture-owner', displayName: 'Sam'),
    ),
  ];
  @override
  Future<CircleRoutine> loadSharedCircleRoutine(
    String id, {
    required DateTime from,
    required DateTime to,
  }) async => CircleRoutine(
    owner: const CirclePerson(id: 'fixture-owner', displayName: 'Sam'),
    permissions: permissions,
    fetchedAt: time,
    notice: 'Not recorded does not mean missed.',
    items: [
      CircleRoutineItem(
        id: '1',
        label: 'Routine item',
        scheduledFor: DateTime(2026, 10, 16, 9),
        state: CircleRoutineState.taken,
        evidence:
            deviceEvidence
                ? CircleEvidence.deviceObservation
                : CircleEvidence.selfReport,
        recordedAt: time,
      ),
      CircleRoutineItem(
        id: '2',
        label: 'Routine item',
        scheduledFor: DateTime(2026, 10, 16, 20),
        state: CircleRoutineState.notRecorded,
        evidence: CircleEvidence.none,
      ),
    ],
  );
}

Future<void> pump(
  WidgetTester tester,
  double width,
  double scale, {
  bool deviceEvidence = false,
}) async {
  final fonts = FontLoader('Outfit');
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    fonts.addFont(rootBundle.load('assets/fonts/Outfit-$weight.ttf'));
  }
  await fonts.load();
  final bytes =
      File(
        '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ).readAsBytesSync();
  await (FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(bytes)))).load();
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: FardaConsumerTheme.from(ThemeData(fontFamily: 'Outfit')),
      builder:
          (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
      home: Scaffold(
        body: SafeArea(
          child: FardaCircleScreen(
            repository: _CircleFixture(deviceEvidence: deviceEvidence),
            onBack: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> shot(WidgetTester tester, String name) async {
  expect(tester.takeException(), isNull);
  if (const bool.fromEnvironment('UPDATE_VISUALS'))
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/$name.png'),
    );
}

void main() {
  testWidgets('device activity never renders reported taken', (tester) async {
    await pump(tester, 390, 1, deviceEvidence: true);
    await tester.ensureVisible(find.textContaining('Shared with me'));
    await tester.tap(find.textContaining('Shared with me'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Open shared routine'));
    await tester.tap(find.byTooltip('Open shared routine'));
    await tester.pumpAndSettle();
    expect(find.text('Vial activity detected'), findsOneWidget);
    expect(find.text('Reported taken'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final layout in [(390.0, 1.0, '390'), (320.0, 1.3, '320-large-text')]) {
    testWidgets('${layout.$3} circle flows', (tester) async {
      await pump(tester, layout.$1, layout.$2);
      await shot(tester, '${layout.$3}-circle');
      await tester.tap(find.text('Invite someone'));
      await tester.pumpAndSettle();
      await shot(tester, '${layout.$3}-circle-invite');
      await tester.enterText(find.byType(TextField), '+15551234567');
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Create invitation'));
      await tester.tap(find.text('Create invitation'));
      await tester.pumpAndSettle();
      await shot(tester, '${layout.$3}-circle-code');
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.textContaining('Shared with me'));
      await tester.tap(find.textContaining('Shared with me'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Review'));
      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();
      tester.view.viewInsets = FakeViewPadding(bottom: 240);
      await tester.pumpAndSettle();
      await shot(tester, '${layout.$3}-circle-accept-keyboard');
      await tester.tap(find.text('Not now'));
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('Open shared routine'));
      await tester.tap(find.byTooltip('Open shared routine'));
      await tester.pumpAndSettle();
      await shot(tester, '${layout.$3}-circle-shared-day');
    });
  }
}
