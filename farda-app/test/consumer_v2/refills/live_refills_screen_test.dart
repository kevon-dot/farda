import 'package:farda/consumer_v2/screens/refills/farda_refills_screen.dart';
import 'package:farda/features/consumer/data/consumer_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ConsumerSnapshot _snapshot({
  List<ConsumerPrescription> prescriptions = const [],
  List<ConsumerInventory> inventory = const [],
  bool inventoryEnabled = false,
}) => ConsumerSnapshot(
  prescriptions: prescriptions,
  inventory: inventory,
  capabilities: ConsumerCapabilities(inventoryEnabled: inventoryEnabled),
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
    await tester.ensureVisible(find.text('Update my count'));
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
}
