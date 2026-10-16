import 'dart:io';
import 'package:farda/features/consumer/data/refill_agent.dart';
import '../consumer_v2/refills/refill_agent_test.dart' show FakeAgent;

import 'package:farda/consumer_v2/screens/refills/refills_handoff_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Export actual Flutter renders only on explicit visual-QA runs. Normal CI
// exercises the same layouts and interactions without date/pixel baselines.
const _exportVisuals = bool.fromEnvironment('UPDATE_VISUALS');

Future<void> _capture(WidgetTester tester, String name) async {
  expect(tester.takeException(), isNull);
  if (!_exportVisuals) return;
  try {
    debugDisableShadows = false;
    await tester.pump();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/$name.png'),
    );
  } finally {
    debugDisableShadows = true;
  }
}

void main() {
  for (final stateName in [
    'eligible',
    'unavailable',
    'unknown',
    'sent',
    'ready',
  ]) {
    for (final narrow in [false, true]) {
      testWidgets('${narrow ? 320 : 390} refill agent $stateName', (
        tester,
      ) async {
        final fonts = FontLoader('Outfit');
        for (final weight in [
          'Light',
          'Regular',
          'Medium',
          'SemiBold',
          'Bold',
        ]) {
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
        tester.view.physicalSize = Size(narrow ? 320 : 390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final agent = FakeAgent();
        agent.state = RefillAgentState(
          prescriptionId: 'p1',
          configured: true,
          canSubmit: true,
          environment: 'sandbox',
          review: RefillAgentReview(
            token: 'review-1',
            expiresAt: DateTime.now().add(const Duration(minutes: 5)),
            medicationName:
                'Daily medication · extended release · full saved label',
            instructions:
                'Follow the directions exactly as printed on your prescription label.\nKeep every line, including any special instructions. Ask your pharmacist if the wording is unclear.',
            pharmacyName: 'Your community pharmacy · Main Street location',
            address:
                '123 Example Street, Apartment 14B, San Francisco, CA, 94103, USA',
            consentText:
                'I confirm these details and want to send this refill request.',
          ),
        );

        if (stateName != 'eligible') {
          agent.state = RefillAgentState(
            prescriptionId: 'p1',
            configured: stateName != 'unavailable',
            canSubmit: false,
            environment: stateName == 'unavailable' ? null : 'sandbox',
            latestRequest:
                stateName == 'unavailable'
                    ? null
                    : RefillProviderRequest(
                      id: 'r1',
                      status: stateName,
                      statusLabel:
                          stateName == 'ready'
                              ? 'Ready for pickup'
                              : stateName == 'sent'
                              ? 'Request sent'
                              : 'Checking request',
                      providerConfirmed: stateName != 'unknown',
                      canRefresh: true,
                      updatedAt: DateTime(2026, 10, 16),
                      lastCheckedAt: DateTime(2026, 10, 16, 8, 30),
                    ),
          );
        }
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(fontFamily: 'Outfit'),
            builder:
                (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    padding: const EdgeInsets.only(top: 48, bottom: 20),
                    viewPadding: const EdgeInsets.only(top: 48, bottom: 20),
                    textScaler: TextScaler.linear(narrow ? 1.3 : 1),
                  ),
                  child: child!,
                ),
            home: RefillsHandoffScreen(
              prescriptionId: 'p1',
              agentRepository: agent,
              medicationName: 'Daily medication · extended release',
              rxLabel: 'Saved by you',
              rxNumber: 'RX48210012',
              directions:
                  'Follow the directions on your prescription label. Check with your pharmacy if any wording is unclear.',
              pharmacy: 'Your community pharmacy',
              actionLabel: 'Save my refill plan',
              onSavePlan: () async => null,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final prefix = narrow ? '320-large-text' : '390';
        await _capture(tester, '$prefix-refill-agent-$stateName');
        if (stateName == 'eligible') {
          await tester.scrollUntilVisible(
            find.byKey(const Key('refill-agent-review')),
            150,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.tap(find.byKey(const Key('refill-agent-review')));
          await tester.pumpAndSettle();
          await _capture(tester, '$prefix-refill-agent-review');
          await tester.ensureVisible(
            find.byKey(const Key('refill-agent-consent')),
          );
          expect(tester.takeException(), isNull);
          await _capture(tester, '$prefix-refill-agent-review-consent');
          await tester.tap(find.text('Not now'));
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.text('Ask about this refill'),
            180,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.tap(find.text('Ask about this refill'));
          await tester.pumpAndSettle();
          await tester.ensureVisible(
            find.byKey(const Key('refill-agent-question')),
          );
          await tester.enterText(
            find.byKey(const Key('refill-agent-question')),
            'What is the next step?',
          );
          await tester.ensureVisible(
            find.byKey(const Key('refill-agent-ai-consent')),
          );
          await tester.tap(find.byKey(const Key('refill-agent-ai-consent')));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.byKey(const Key('refill-agent-ask')));
          await tester.tap(find.byKey(const Key('refill-agent-ask')));
          await tester.pumpAndSettle();
          expect(find.text('Check with your pharmacist'), findsOneWidget);
          await tester.ensureVisible(find.text('Guided help · nothing sent'));
          await _capture(tester, '$prefix-refill-agent-helper');
        }
      });
    }
  }
}
