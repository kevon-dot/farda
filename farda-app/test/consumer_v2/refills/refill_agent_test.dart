import 'dart:async';
import 'package:farda/consumer_v2/screens/refills/refill_agent_card.dart';
import 'package:farda/consumer_v2/screens/refills/refill_question_card.dart';
import 'package:farda/features/consumer/data/refill_agent.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

RefillAgentState eligible() => RefillAgentState(
  prescriptionId: 'p1',
  configured: true,
  canSubmit: true,
  environment: 'sandbox',
  review: RefillAgentReview(
    token: 'review-1',
    expiresAt: DateTime.now().add(const Duration(minutes: 5)),
    medicationName: 'Fixture medication',
    pharmacyName: 'Fixture pharmacy',
    address: '123 Example Street',
    consentText: 'I confirm these details.',
  ),
);

class FakeAgent implements RefillAgentRepository, RefillQuestionRepository {
  RefillAgentState state = eligible();
  int submits = 0;
  int refreshes = 0;
  int questions = 0;
  bool failSubmit = false;
  Completer<RefillAgentState>? submission;
  @override
  Future<RefillAgentState> loadRefillAgent(String id) async => state;
  @override
  Future<RefillAgentState> refreshRefillAgent(String id) async {
    refreshes++;
    return state;
  }

  @override
  Future<RefillAgentState> submitRefillAgent(
    String id, {
    required String reviewToken,
    required String idempotencyKey,
  }) async {
    submits++;
    expect(reviewToken, 'review-1');
    expect(idempotencyKey.startsWith('refill-'), isTrue);
    if (failSubmit) throw TimeoutException('unknown');
    return submission?.future ?? state;
  }

  @override
  Future<RefillAgentAnswer> askRefillQuestion(
    String id,
    String question,
  ) async {
    questions++;
    return const RefillAgentAnswer(
      title: 'Check with your pharmacist',
      message: 'Ask your pharmacist about medication instructions.',
      action: 'none',
      source: 'guided',
    );
  }
}

Future<void> pumpCard(WidgetTester tester, FakeAgent agent) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: RefillAgentCard(prescriptionId: 'p1', repository: agent),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> confirm(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('refill-agent-review')));
  await tester.pumpAndSettle();
  final send = tester.widget<FilledButton>(
    find.byKey(const Key('refill-agent-send')),
  );
  expect(send.onPressed, isNull);
  await tester.ensureVisible(find.byKey(const Key('refill-agent-consent')));
  await tester.tap(find.byKey(const Key('refill-agent-consent')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('refill-agent-send')));
}

void main() {
  testWidgets('changing prescription while review is open cancels send', (
    tester,
  ) async {
    final agent = FakeAgent();
    final id = ValueNotifier('p1');
    addTearDown(id.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<String>(
            valueListenable: id,
            builder:
                (_, value, __) =>
                    RefillAgentCard(prescriptionId: value, repository: agent),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('refill-agent-review')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('refill-agent-consent')));
    id.value = 'p2';
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('refill-agent-send')));
    await tester.pumpAndSettle();
    expect(agent.submits, 0);
  });

  testWidgets('provider send requires explicit review and consent', (
    tester,
  ) async {
    final agent = FakeAgent()..submission = Completer();
    await pumpCard(tester, agent);
    expect(agent.submits, 0);
    await confirm(tester);
    await tester.pump();
    expect(agent.submits, 1);
    expect(find.byKey(const Key('refill-agent-review')), findsNothing);
    agent.submission!.complete(
      const RefillAgentState(
        prescriptionId: 'p1',
        configured: true,
        canSubmit: false,
      ),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('uncertain submit blocks resend until explicit status check', (
    tester,
  ) async {
    final agent = FakeAgent()..failSubmit = true;
    await pumpCard(tester, agent);
    await confirm(tester);
    await tester.pumpAndSettle();
    expect(agent.submits, 1);
    expect(find.text('We’re checking your request'), findsOneWidget);
    expect(find.byKey(const Key('refill-agent-review')), findsNothing);
    await tester.tap(find.byKey(const Key('refill-agent-refresh')));
    await tester.pumpAndSettle();
    expect(agent.refreshes, 1);
    expect(agent.submits, 1);
  });

  testWidgets('unknown server request cannot send despite an eligible flag', (
    tester,
  ) async {
    final agent =
        FakeAgent()
          ..state = RefillAgentState(
            prescriptionId: 'p1',
            configured: true,
            canSubmit: true,
            review: eligible().review,
            latestRequest: RefillProviderRequest(
              id: 'r1',
              status: 'unknown',
              statusLabel: 'Unknown',
              providerConfirmed: false,
              canRefresh: true,
              updatedAt: DateTime.now(),
            ),
          );
    await pumpCard(tester, agent);
    expect(find.byKey(const Key('refill-agent-review')), findsNothing);
    expect(find.text('Check status'), findsOneWidget);
  });

  testWidgets('AI helper requires consent and cannot submit a refill', (
    tester,
  ) async {
    final agent = FakeAgent();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RefillQuestionCard(prescriptionId: 'p1', repository: agent),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Ask about this refill'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('refill-agent-question')),
      'Should I change my dose?',
    );
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('refill-agent-ask')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const Key('refill-agent-ai-consent')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('refill-agent-ask')));
    await tester.tap(find.byKey(const Key('refill-agent-ask')));
    await tester.pumpAndSettle();
    expect(agent.questions, 1);
    expect(agent.submits, 0);
    expect(find.text('Check with your pharmacist'), findsOneWidget);
  });
}
