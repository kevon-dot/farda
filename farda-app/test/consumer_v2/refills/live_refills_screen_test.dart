import 'package:farda/consumer_v2/screens/refills/farda_refills_screen.dart';
import 'package:farda/features/consumer/data/consumer_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ConsumerSnapshot _snapshot({
  List<ConsumerPrescription> prescriptions = const [],
  List<ConsumerInventory> inventory = const [],
  bool inventoryEnabled = false,
  bool refillsEnabled = false,
}) => ConsumerSnapshot(
  prescriptions: prescriptions,
  inventory: inventory,
  capabilities: ConsumerCapabilities(
    inventoryEnabled: inventoryEnabled, refillsEnabled: refillsEnabled),
  fetchedAt: DateTime(2026, 10, 15),
);

const _rx = ConsumerPrescription(
  id: 'rx-42',
  name: 'Account medication',
  pharmacy: 'Known pharmacy',
  rxNumber: 'RX9876',
);

void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: child));
    await tester.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester tester, Finder target) async {
    // A card can be built below the viewport, so finding its label alone does
    // not mean a tap can reach it. Scroll the page before ensuring visibility.
    await tester.drag(find.byType(ListView).first, const Offset(0, -450));
    await tester.pumpAndSettle();
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
  }

  testWidgets('authenticated empty account has no sample prescription or count',
      (tester) async {
    await pump(tester, FardaRefillsScreen(snapshot: _snapshot()));
    expect(find.text('No prescriptions yet'), findsOneWidget);
    expect(find.text('Daily medication'), findsNothing);
    expect(find.textContaining('4821'), findsNothing);
    expect(find.text('Update my count'), findsNothing);
  });

  testWidgets('unknown and stale supply do not invent a days-left estimate',
      (tester) async {
    await pump(tester, FardaRefillsScreen(
      snapshot: _snapshot(
        prescriptions: const [_rx],
        inventory: const [ConsumerInventory(
          prescriptionId: 'rx-42', quantity: 12, dailyUnits: 1,
          stale: true,
        )],
      ),
    ));
    expect(find.text('Account medication'), findsOneWidget);
    expect(find.text('Known pharmacy'), findsOneWidget);
    expect(find.text('Rx ending 9876'), findsOneWidget);
    expect(find.text('12 at last count'), findsOneWidget);
    expect(find.text('12 days estimated'), findsNothing);
    expect(find.textContaining('out of date'), findsOneWidget);
    expect(find.text('I received my refill'), findsNothing);
  });

  testWidgets('a rejected count remains editable, accepted count calls API once',
      (tester) async {
    final writes = <int>[];
    var fail = true;
    await pump(tester, FardaRefillsScreen(
      snapshot: _snapshot(
        prescriptions: const [_rx], inventoryEnabled: true,
      ),
      onUpdateInventory: (id, count) async {
        expect(id, 'rx-42');
        writes.add(count);
        if (fail) return 'The server did not save your count.';
        return null;
      },
    ));
    await reveal(tester, find.text('Update my count'));
    await tester.tap(find.text('Update my count'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('live-refill-count-input')), '8');
    await tester.tap(find.byKey(const Key('live-refill-save-count')));
    await tester.pumpAndSettle();
    expect(find.text('The server did not save your count.'), findsOneWidget);
    expect(find.byKey(const Key('live-refill-count-input')), findsOneWidget);
    expect(writes, [8]);

    fail = false;
    await tester.tap(find.byKey(const Key('live-refill-save-count')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(writes, [8, 8]);
    expect(find.byKey(const Key('live-refill-count-input')), findsNothing);
    expect(find.text('Your count was saved.'), findsOneWidget);
  });

  testWidgets('capability-disabled account cannot submit count', (tester) async {
    await pump(tester, FardaRefillsScreen(
      snapshot: _snapshot(prescriptions: const [_rx]),
      onUpdateInventory: (_, __) async => null,
    ));
    expect(find.text('Count updates are unavailable for this account.'),
        findsOneWidget);
    final button = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Update my count'));
    expect(button.onPressed, isNull);
  });

  testWidgets('plan is reported only after accepted write', (tester) async {
    final writes = <RefillStage>[];
    var fail = true;
    await pump(tester, FardaRefillsScreen(
      snapshot: _snapshot(prescriptions: const [_rx], refillsEnabled: true),
      onUpdateRefill: (id, stage, {startNew = false}) async {
        expect(id, 'rx-42');
        expect(startNew, false);
        writes.add(stage);
        return fail ? 'The server did not save this plan.' : null;
      },
    ));
    await reveal(tester, find.text('Plan my refill'));
    await tester.tap(find.text('Plan my refill'));
    await tester.pumpAndSettle();
    expect(find.textContaining('does not contact your pharmacy'), findsOneWidget);
    await tester.tap(find.byKey(const Key('live-refill-confirm-stage')));
    await tester.pumpAndSettle();
    expect(writes, [RefillStage.planning]);
    expect(find.text('The server did not save this plan.'), findsOneWidget);
    expect(find.text('No refill plan recorded.'), findsOneWidget);
    fail = false;
    await tester.tap(find.byKey(const Key('live-refill-confirm-stage')));
    await tester.pumpAndSettle();
    expect(writes, [RefillStage.planning, RefillStage.planning]);
    expect(find.text('Your refill update was saved.'), findsOneWidget);
  });

  testWidgets('receipt requires count, quantity, and explicit inclusion choice',
      (tester) async {
    final receipts = <(int, bool)>[];
    var fail = true;
    Future<String?> reconcile(String id,
        {required int quantity, required bool alreadyIncluded}) async {
      expect(id, 'rx-42');
      receipts.add((quantity, alreadyIncluded));
      return fail ? 'Supply changed. Refresh before retrying.' : null;
    }
    final received = ConsumerInventory(
      prescriptionId: 'rx-42', refillId: 'refill-1',
      stage: RefillStage.received, quantity: 12,
    );
    await pump(tester, FardaRefillsScreen(
      snapshot: _snapshot(prescriptions: const [_rx],
        inventory: [received], refillsEnabled: true),
      onUpdateRefill: (_, __, {startNew = false}) async => null,
      onReconcileReceipt: reconcile,
    ));
    await reveal(tester, find.text('Reconcile my refill'));
    await tester.tap(find.text('Reconcile my refill'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('live-refill-confirm-receipt')));
    await tester.pumpAndSettle();
    expect(find.textContaining('actual quantity received'), findsOneWidget);
    expect(receipts, isEmpty);
    await tester.enterText(find.byKey(const Key('live-refill-receipt-quantity')), '5');
    await tester.tap(find.byKey(const Key('live-refill-confirm-receipt')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Choose whether'), findsOneWidget);
    expect(receipts, isEmpty);
    await tester.tap(find.byKey(const Key('live-refill-receipt-add')));
    await tester.pumpAndSettle();
    expect(find.text('Count after reconciliation: 17'), findsOneWidget);
    await tester.tap(find.byKey(const Key('live-refill-confirm-receipt')));
    await tester.pumpAndSettle();
    expect(receipts, [(5, false)]);
    expect(find.text('Supply changed. Refresh before retrying.'), findsOneWidget);
    fail = false;
    await tester.tap(find.byKey(const Key('live-refill-confirm-receipt')));
    await tester.pumpAndSettle();
    expect(receipts, [(5, false), (5, false)]);
    expect(find.text('Your receipt and count were reconciled.'), findsOneWidget);
  });

  testWidgets('unknown count blocks receipt reconciliation', (tester) async {
    await pump(tester, FardaRefillsScreen(
      snapshot: _snapshot(prescriptions: const [_rx],
        inventory: const [ConsumerInventory(prescriptionId: 'rx-42',
          refillId: 'refill-1', stage: RefillStage.received)],
        refillsEnabled: true),
      onUpdateRefill: (_, __, {startNew = false}) async => null,
      onReconcileReceipt: (_, {required quantity, required alreadyIncluded}) async => null,
    ));
    await reveal(tester, find.text('Reconcile my refill'));
    await tester.tap(find.text('Reconcile my refill'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Save a current supply count'), findsOneWidget);
    expect(find.byKey(const Key('live-refill-confirm-receipt')), findsNothing);
  });

  testWidgets('narrow view keeps the reported journey and action readable',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(1.2)),
        child: child!,
      ),
      home: FardaRefillsScreen(
          snapshot: _snapshot(prescriptions: const [_rx],
            inventory: const [ConsumerInventory(
              prescriptionId: 'rx-42', refillId: 'refill-1',
              stage: RefillStage.contacted, quantity: 12)],
            refillsEnabled: true),
          onUpdateRefill: (_, __, {startNew = false}) async => null,
      ),
    ));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('I was told it is ready'));
    expect(find.text('12 at last count'), findsOneWidget);
    expect(find.text('You reported contacting your pharmacy.'), findsOneWidget);
    expect(find.text('I was told it is ready'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
