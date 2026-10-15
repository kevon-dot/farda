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
    inventoryEnabled: inventoryEnabled,
    refillsEnabled: refillsEnabled,
  ),
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
    final viewportHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    if (tester.getCenter(target).dy > viewportHeight - 80) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -300));
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'authenticated empty account has no sample prescription or count',
    (tester) async {
      await pump(tester, FardaRefillsScreen(snapshot: _snapshot()));
      expect(find.text('No prescriptions yet'), findsOneWidget);
      expect(find.text('Daily medication'), findsNothing);
      expect(find.textContaining('4821'), findsNothing);
      expect(find.text('Update my count'), findsNothing);
    },
  );

  testWidgets('empty account exposes direct medication onboarding', (
    tester,
  ) async {
    var added = 0;
    var tools = 0;
    await pump(
      tester,
      FardaRefillsScreen(
        snapshot: _snapshot(),
        onAddPrescription: () => added++,
        onOpenRefillTools: () => tools++,
      ),
    );
    await tester.tap(find.text('Add medication'));
    await tester.pumpAndSettle();
    expect(added, 1);
    expect(tools, 0);
    expect(find.text('Open account tools'), findsNothing);
  });

  testWidgets(
    'preparing a request stays available without refill write capability',
    (tester) async {
      var openedTools = false;
      await pump(
        tester,
        FardaRefillsScreen(
          snapshot: _snapshot(prescriptions: const [_rx]),
          onOpenRefillTools: () => openedTools = true,
        ),
      );
      await reveal(tester, find.text('Prepare refill'));
      await tester.tap(find.text('Prepare refill'));
      await tester.pumpAndSettle();
      expect(find.text('Known pharmacy'), findsOneWidget);
      expect(find.text('Rx RX9876'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Review refill request'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Review refill request'));
      await tester.pumpAndSettle();
      expect(find.text('Your refill request'), findsOneWidget);
      expect(find.text('Save my refill plan'), findsNothing);
      expect(openedTools, false);
    },
  );

  testWidgets(
    'a saved plan can prepare a request without resetting its stage',
    (tester) async {
      var writes = 0;
      await pump(
        tester,
        FardaRefillsScreen(
          snapshot: _snapshot(
            prescriptions: const [_rx],
            inventory: const [
              ConsumerInventory(
                prescriptionId: 'rx-42',
                refillId: 'refill-1',
                stage: RefillStage.contacted,
              ),
            ],
            refillsEnabled: true,
          ),
          onUpdateRefill: (_, __, {startNew = false}) async {
            writes++;
            return null;
          },
        ),
      );
      await reveal(tester, find.text('Prepare refill request'));
      await tester.tap(find.text('Prepare refill request'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Review refill request'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Review refill request'));
      await tester.pumpAndSettle();
      expect(find.text('Your refill request'), findsOneWidget);
      expect(find.text('Save my refill plan'), findsNothing);
      expect(writes, 0);
    },
  );

  testWidgets('unknown and stale supply do not invent a days-left estimate', (
    tester,
  ) async {
    await pump(
      tester,
      FardaRefillsScreen(
        snapshot: _snapshot(
          prescriptions: const [_rx],
          inventory: const [
            ConsumerInventory(
              prescriptionId: 'rx-42',
              quantity: 12,
              dailyUnits: 1,
              stale: true,
            ),
          ],
        ),
      ),
    );
    expect(find.text('Account medication'), findsOneWidget);
    expect(
      find.textContaining('Known pharmacy · Rx ending 9876'),
      findsOneWidget,
    );
    expect(find.text('12'), findsOneWidget);
    expect(find.text('COUNT NEEDS REFRESH'), findsOneWidget);
    expect(find.text('12 days estimated'), findsNothing);
    expect(find.textContaining('out of date'), findsOneWidget);
    expect(find.text('I received my refill'), findsNothing);
  });

  testWidgets(
    'a rejected count remains editable, accepted count calls API once',
    (tester) async {
      final writes = <int>[];
      var fail = true;
      await pump(
        tester,
        FardaRefillsScreen(
          snapshot: _snapshot(
            prescriptions: const [_rx],
            inventoryEnabled: true,
          ),
          onUpdateInventory: (id, count) async {
            expect(id, 'rx-42');
            writes.add(count);
            if (fail) return 'The server did not save your count.';
            return null;
          },
        ),
      );
      await reveal(tester, find.text('Update my count'));
      await tester.tap(find.text('Update my count'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('live-refill-count-input')),
        '8',
      );
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
    },
  );

  testWidgets('capability-disabled account cannot submit count', (
    tester,
  ) async {
    await pump(
      tester,
      FardaRefillsScreen(
        snapshot: _snapshot(prescriptions: const [_rx]),
        onUpdateInventory: (_, __) async => null,
      ),
    );
    expect(
      find.text('Count updates are unavailable for this account.'),
      findsOneWidget,
    );
    final button = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Update my count'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('count input honors the repository upper bound', (tester) async {
    final writes = <int>[];
    await pump(
      tester,
      FardaRefillsScreen(
        snapshot: _snapshot(prescriptions: const [_rx], inventoryEnabled: true),
        onUpdateInventory: (_, count) async {
          writes.add(count);
          return null;
        },
      ),
    );
    await reveal(tester, find.text('Update my count'));
    await tester.tap(find.text('Update my count'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('live-refill-count-input')),
      '100001',
    );
    await tester.tap(find.byKey(const Key('live-refill-save-count')));
    await tester.pumpAndSettle();
    expect(find.textContaining('0 to 100,000'), findsOneWidget);
    expect(writes, isEmpty);
    await tester.enterText(
      find.byKey(const Key('live-refill-count-input')),
      '100000',
    );
    await tester.tap(find.byKey(const Key('live-refill-save-count')));
    await tester.pumpAndSettle();
    expect(writes, [100000]);
  });

  testWidgets('plan is reported only after accepted write', (tester) async {
    final writes = <RefillStage>[];
    var fail = true;
    await pump(
      tester,
      FardaRefillsScreen(
        snapshot: _snapshot(prescriptions: const [_rx], refillsEnabled: true),
        onUpdateRefill: (id, stage, {startNew = false}) async {
          expect(id, 'rx-42');
          expect(startNew, false);
          writes.add(stage);
          return fail ? 'The server did not save this plan.' : null;
        },
      ),
    );
    await reveal(tester, find.text('Prepare refill'));
    await tester.tap(find.text('Prepare refill'));
    await tester.pumpAndSettle();
    expect(find.text('Let’s get\nyou ready.'), findsOneWidget);
    expect(
      find.textContaining('No refill order is submitted.'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('Save my refill plan'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Save my refill plan'));
    await tester.pumpAndSettle();
    expect(writes, [RefillStage.planning]);
    expect(find.text('The server did not save this plan.'), findsOneWidget);
    expect(find.text('Let’s get\nyou ready.'), findsOneWidget);
    fail = false;
    await tester.scrollUntilVisible(
      find.text('Save my refill plan'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Save my refill plan'));
    await tester.pumpAndSettle();
    expect(writes, [RefillStage.planning, RefillStage.planning]);
    expect(find.text('Your refill plan was saved.'), findsOneWidget);
  });

  testWidgets(
    'receipt requires count, quantity, and explicit inclusion choice',
    (tester) async {
      final receipts = <(int, bool)>[];
      var fail = true;
      Future<String?> reconcile(
        String id, {
        required int quantity,
        required bool alreadyIncluded,
      }) async {
        expect(id, 'rx-42');
        receipts.add((quantity, alreadyIncluded));
        return fail ? 'Supply changed. Refresh before retrying.' : null;
      }

      final received = ConsumerInventory(
        prescriptionId: 'rx-42',
        refillId: 'refill-1',
        stage: RefillStage.received,
        quantity: 12,
      );
      await pump(
        tester,
        FardaRefillsScreen(
          snapshot: _snapshot(
            prescriptions: const [_rx],
            inventory: [received],
            refillsEnabled: true,
          ),
          onUpdateRefill: (_, __, {startNew = false}) async => null,
          onReconcileReceipt: reconcile,
        ),
      );
      await reveal(tester, find.text('Reconcile my refill'));
      await tester.tap(find.text('Reconcile my refill'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('live-refill-confirm-receipt')));
      await tester.pumpAndSettle();
      expect(find.textContaining('actual quantity received'), findsOneWidget);
      expect(receipts, isEmpty);
      await tester.enterText(
        find.byKey(const Key('live-refill-receipt-quantity')),
        '5',
      );
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
      expect(
        find.text('Supply changed. Refresh before retrying.'),
        findsOneWidget,
      );
      fail = false;
      await tester.tap(find.byKey(const Key('live-refill-confirm-receipt')));
      await tester.pumpAndSettle();
      expect(receipts, [(5, false), (5, false)]);
      expect(
        find.text('Your receipt and count were reconciled.'),
        findsOneWidget,
      );
    },
  );

  for (final reconciled in [true, false]) {
    testWidgets(
      'received refill starts a new plan with explicit ${reconciled ? 'reconciled' : 'skip'} path',
      (tester) async {
        final writes = <(RefillStage, bool)>[];
        await pump(
          tester,
          FardaRefillsScreen(
            snapshot: _snapshot(
              prescriptions: const [_rx],
              inventory: [
                ConsumerInventory(
                  prescriptionId: 'rx-42',
                  refillId: 'refill-1',
                  stage: RefillStage.received,
                  quantity: 12,
                  receiptReconciled: reconciled,
                ),
              ],
              refillsEnabled: true,
            ),
            onUpdateRefill: (_, stage, {startNew = false}) async {
              writes.add((stage, startNew));
              return null;
            },
          ),
        );
        await reveal(tester, find.text('Plan my next refill'));
        await tester.tap(find.text('Plan my next refill').first);
        await tester.pumpAndSettle();
        if (!reconciled) {
          expect(find.textContaining('skips that receipt'), findsOneWidget);
        }
        expect(writes, isEmpty);
        await tester.tap(find.byKey(const Key('live-refill-confirm-stage')));
        await tester.pumpAndSettle();
        expect(writes, [(RefillStage.planning, true)]);
      },
    );
  }

  testWidgets('unknown count blocks receipt reconciliation', (tester) async {
    await pump(
      tester,
      FardaRefillsScreen(
        snapshot: _snapshot(
          prescriptions: const [_rx],
          inventory: const [
            ConsumerInventory(
              prescriptionId: 'rx-42',
              refillId: 'refill-1',
              stage: RefillStage.received,
            ),
          ],
          refillsEnabled: true,
        ),
        onUpdateRefill: (_, __, {startNew = false}) async => null,
        onReconcileReceipt:
            (_, {required quantity, required alreadyIncluded}) async => null,
      ),
    );
    await reveal(tester, find.text('Reconcile my refill'));
    await tester.tap(find.text('Reconcile my refill'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Save a current supply count'), findsOneWidget);
    expect(find.byKey(const Key('live-refill-confirm-receipt')), findsNothing);
  });

  testWidgets('narrow view keeps the reported journey and action readable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder:
            (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.2)),
              child: child!,
            ),
        home: FardaRefillsScreen(
          snapshot: _snapshot(
            prescriptions: const [_rx],
            inventory: const [
              ConsumerInventory(
                prescriptionId: 'rx-42',
                refillId: 'refill-1',
                stage: RefillStage.contacted,
                quantity: 12,
              ),
            ],
            refillsEnabled: true,
          ),
          onUpdateRefill: (_, __, {startNew = false}) async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await reveal(tester, find.text('I was told it is ready'));
    expect(find.text('12'), findsOneWidget);
    expect(find.text('You reported contacting your pharmacy.'), findsOneWidget);
    expect(find.text('I was told it is ready'), findsOneWidget);
    final layoutError = tester.takeException();
    expect(
      layoutError,
      isNull,
      reason: layoutError is FlutterError ? layoutError.toStringDeep() : null,
    );
  });

  testWidgets('receipt choice remains visible in a narrow large-text dialog', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder:
            (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!,
            ),
        home: FardaRefillsScreen(
          snapshot: _snapshot(
            prescriptions: const [_rx],
            inventory: const [
              ConsumerInventory(
                prescriptionId: 'rx-42',
                refillId: 'refill-1',
                stage: RefillStage.received,
                quantity: 12,
              ),
            ],
            refillsEnabled: true,
          ),
          onUpdateRefill: (_, __, {startNew = false}) async => null,
          onReconcileReceipt:
              (_, {required quantity, required alreadyIncluded}) async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Reconcile my refill'));
    await tester.tap(find.text('Reconcile my refill'));
    await tester.pumpAndSettle();
    expect(find.text('Yes, already included'), findsOneWidget);
    expect(find.text('No, add received quantity'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
