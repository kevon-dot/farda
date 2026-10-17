import 'package:farda/application/authentication/storage/auth_storage.dart';
import 'package:farda/consumer_v2/screens/membership/farda_membership_screen.dart';
import 'package:farda/features/consumer/data/billing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:farda/consumer_v2/screens/membership/membership_offer_gate.dart';

class BillingFake implements BillingRepository {
  BillingStatus status = const BillingStatus();
  bool fail = false;
  int checkouts = 0;
  @override
  Future<BillingCatalog> loadBillingCatalog() async {
    if (fail) throw StateError('offline');
    return BillingCatalog(
      plans: BillingCatalog.proposal.plans,
      checkoutEnabled: true,
    );
  }

  @override
  Future<BillingStatus> loadBillingStatus() async => status;
  @override
  Future<Uri> createBillingCheckout(String key, Uri returnUri) async {
    checkouts++;
    return Uri.parse('https://checkout.stripe.com');
  }

  @override
  Future<Uri> createBillingPortal(Uri returnUri) async =>
      Uri.parse('https://billing.stripe.com');
}

void main() {
  test(
    'onboarding offer is once per account and rejects a stale session',
    () async {
      SharedPreferences.setMockInitialValues({});
      expect(await MembershipOfferGate.claim('owner-a', () => true), isTrue);
      expect(await MembershipOfferGate.claim('owner-a', () => true), isFalse);
      expect(await MembershipOfferGate.claim('owner-b', () => false), isFalse);
      expect(await MembershipOfferGate.claim('owner-b', () => true), isTrue);
      expect(await MembershipOfferGate.claim('', () => true), isFalse);
    },
  );

  testWidgets('onboarding offer can continue free without checkout', (
    tester,
  ) async {
    final repo = BillingFake();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder:
              (context) => TextButton(
                onPressed:
                    () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder:
                            (_) => FardaMembershipScreen(
                              repository: repo,
                              onboardingOffer: true,
                            ),
                      ),
                    ),
                child: const Text('Start'),
              ),
        ),
      ),
    );
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(find.text('Your routine, supported.'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Continue free'), 300);
    await tester.tap(find.text('Continue free'));
    await tester.pumpAndSettle();
    expect(find.text('Start'), findsOneWidget);
    expect(repo.checkouts, 0);
  });

  testWidgets(
    'session revision removes paid state before loading the next account',
    (tester) async {
      final repo =
          BillingFake()
            ..status = const BillingStatus(tier: 'family', status: 'active');
      await tester.pumpWidget(
        MaterialApp(home: FardaMembershipScreen(repository: repo)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Your membership.'), findsOneWidget);
      repo.fail = true;
      AuthStorage.sessionRevision.value++;
      await tester.pumpAndSettle();
      expect(find.text('Your membership.'), findsNothing);
      expect(find.text('active'), findsNothing);
      expect(find.text('A little more support.'), findsOneWidget);
    },
  );

  testWidgets('320px large text keeps native unavailable state readable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = BillingFake();
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: FardaMembershipScreen(repository: repo),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Price unavailable'), 150);
    expect(find.text('Price unavailable'), findsOneWidget);
    expect(find.textContaining('149.99'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('Purchases unavailable'), 300);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Purchases unavailable'),
    );
    expect(button.onPressed, isNull);
    expect(repo.checkouts, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'load failure does not claim free or paid membership and allows retry',
    (tester) async {
      final repo = BillingFake()..fail = true;
      await tester.pumpWidget(
        MaterialApp(home: FardaMembershipScreen(repository: repo)),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Refresh membership'), 350);
      expect(find.textContaining('couldn’t load'), findsOneWidget);
      repo.fail = false;
      await tester.tap(find.text('Refresh membership'));
      await tester.pumpAndSettle();
      expect(find.textContaining('couldn’t load'), findsNothing);
    },
  );
  testWidgets(
    'past-due billing remains manageable without paid access or checkout',
    (tester) async {
      final repo =
          BillingFake()
            ..status = const BillingStatus(
              tier: 'free',
              status: 'past_due',
              source: 'web',
              managementAvailable: true,
            );
      await tester.pumpWidget(
        MaterialApp(home: FardaMembershipScreen(repository: repo)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Your membership.'), findsOneWidget);
      expect(find.text('past due'), findsOneWidget);
      expect(
        find.text(
          'Premium access is not active. Your free essentials remain available.',
        ),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(find.text('Manage membership'), 200);
      expect(find.text('Manage membership'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.textContaining('Open Farda in your browser'),
        150,
      );
      expect(find.textContaining('Open Farda in your browser'), findsOneWidget);
      expect(find.text('Purchases unavailable'), findsNothing);
      expect(find.textContaining('Continue with'), findsNothing);
      expect(repo.checkouts, 0);
    },
  );
  testWidgets(
    'server membership renders management rather than duplicate subscription offer',
    (tester) async {
      final repo =
          BillingFake()
            ..status = const BillingStatus(
              tier: 'family',
              status: 'active',
              familyAlerts: true,
              aiRefillHelp: true,
              managementAvailable: true,
            );
      await tester.pumpWidget(
        MaterialApp(home: FardaMembershipScreen(repository: repo)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Your membership.'), findsOneWidget);
      expect(find.text('active'), findsOneWidget);
      expect(find.text('Purchases unavailable'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Manage membership'),
            )
            .onPressed,
        isNull,
      );
    },
  );
}
