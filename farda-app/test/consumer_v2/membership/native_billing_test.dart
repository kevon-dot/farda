import 'dart:async';
import 'package:farda/application/authentication/storage/auth_storage.dart';
import 'package:farda/consumer_v2/screens/membership/farda_membership_screen.dart';
import 'package:farda/features/consumer/data/billing.dart';
import 'package:farda/features/consumer/data/native_billing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'membership_screen_test.dart' show BillingFake;

class NativeRepo extends BillingFake implements NativeBillingRepository {
  int syncs = 0, prepares = 0;
  Object? prepareError;
  bool enabled = true;
  @override
  Future<NativeBillingConfig> loadNativeBillingConfig(String platform) async =>
      NativeBillingConfig(
        enabled: enabled,
        appUserId: 'opaque',
        apiKey: 'public',
        products: const {'plus-year': 'plus'},
        termsUrl: Uri.parse('https://example.com/terms'),
        privacyUrl: Uri.parse('https://example.com/privacy'),
        supportUrl: Uri.parse('https://support.example.com/help'),
      );
  @override
  Future<NativeBillingConfig> prepareNativeBilling(
    String platform,
    Future<bool> Function() check,
  ) async {
    prepares++;
    if (prepareError != null) throw prepareError!;
    return loadNativeBillingConfig(platform);
  }

  @override
  Future<BillingStatus> syncNativeBilling(Future<bool> Function() check) async {
    if (!await check()) throw StateError('stale');
    syncs++;
    return status;
  }
}

class StoreFake implements NativePurchaseAdapter {
  int buys = 0, restores = 0, resets = 0;
  Completer<void>? purchaseResult;
  Object? error;
  @override
  Future<List<NativeOffer>> configure(NativeBillingConfig config) async => [
    const NativeOffer(
      id: 'plus-year',
      tier: 'plus',
      annual: true,
      price: '€129,99',
      package: 'package',
    ),
  ];
  @override
  Future<void> purchase(NativeOffer offer) async {
    buys++;
    if (error != null) throw error!;
    await purchaseResult?.future;
  }

  @override
  Future<void> restore() async {
    restores++;
  }

  @override
  Future<void> reset() async {
    resets++;
  }
}

void main() {
  Future<void> show(WidgetTester t, NativeRepo repo, StoreFake store) async {
    await t.pumpWidget(
      MaterialApp(
        home: FardaMembershipScreen(repository: repo, nativeAdapter: store),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets('store price, purchase and restore remain server authoritative', (
    t,
  ) async {
    final repo = NativeRepo();
    final store = StoreFake();
    await show(t, repo, store);
    expect(find.text('€129,99 / year'), findsOneWidget);
    expect(find.textContaining('149.99'), findsNothing);
    await t.scrollUntilVisible(find.text('Support'), 250);
    expect(find.text('Terms of service'), findsOneWidget);
    expect(find.text('Privacy policy'), findsOneWidget);
    expect(find.text('Support'), findsOneWidget);
    await t.scrollUntilVisible(find.text('Continue with Plus'), 250);
    await t.tap(find.text('Continue with Plus'));
    await t.pumpAndSettle();
    expect(store.buys, 1);
    expect(repo.syncs, 1);
    expect(repo.checkouts, 0);
    expect(find.text('Your membership.'), findsNothing);
    repo.status = const BillingStatus(tier: 'plus', status: 'active');
    await t.ensureVisible(find.text('Restore purchases'));
    await t.pumpAndSettle();
    await t.tap(find.text('Restore purchases'));
    await t.pumpAndSettle();
    expect(store.restores, 1);
    expect(repo.syncs, 2);
    await t.scrollUntilVisible(find.text('Your membership.'), -250);
    expect(find.text('Your membership.'), findsOneWidget);
  });
  testWidgets(
    'account change during store purchase never reconciles stale purchase',
    (t) async {
      final repo = NativeRepo();
      final store = StoreFake()..purchaseResult = Completer<void>();
      await show(t, repo, store);
      await t.scrollUntilVisible(find.text('Continue with Plus'), 250);
      await t.tap(find.text('Continue with Plus'));
      await t.pump();
      AuthStorage.sessionRevision.value++;
      await t.pumpAndSettle();
      store.purchaseResult!.complete();
      await t.pumpAndSettle();
      expect(repo.syncs, 0);
      expect(store.resets, greaterThan(0));
    },
  );
  testWidgets('server prepare failure prevents store purchase', (t) async {
    final repo =
        NativeRepo()..prepareError = StateError('checkout_in_progress');
    final store = StoreFake();
    await show(t, repo, store);
    await t.scrollUntilVisible(find.text('Continue with Plus'), 250);
    expect(
      t
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Continue with Plus'),
          )
          .onPressed,
      isNotNull,
    );
    await t.tap(find.text('Continue with Plus'));
    await t.pumpAndSettle();
    expect(repo.prepares, 1);
    expect(store.buys, 0);
    expect(repo.syncs, 0);
    expect(repo.checkouts, 0);
    expect(
      find.textContaining('couldn’t confirm your store membership'),
      findsOneWidget,
    );
  });
  testWidgets('cancellation does not sync or claim membership', (t) async {
    final repo = NativeRepo();
    final store = StoreFake()..error = PlatformException(code: '1');
    await show(t, repo, store);
    await t.scrollUntilVisible(find.text('Continue with Plus'), 250);
    await t.tap(find.text('Continue with Plus'));
    await t.pumpAndSettle();
    expect(repo.syncs, 0);
    expect(find.textContaining('Purchase cancelled'), findsOneWidget);
  });
  testWidgets('unconfigured store hides prices and disables purchases', (
    t,
  ) async {
    final repo = NativeRepo()..enabled = false;
    final store = StoreFake();
    await show(t, repo, store);
    expect(find.text('Price unavailable'), findsOneWidget);
    await t.scrollUntilVisible(find.text('Purchases unavailable'), 250);
    expect(
      t
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Purchases unavailable'),
          )
          .onPressed,
      isNull,
    );
    expect(store.buys, 0);
  });
}
