import 'package:farda/consumer_v2/screens/refills/farda_refills_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RefillStationController', () {
    test('derives a conservative supply estimate from count and schedule', () {
      const state = RefillStationState(
        medicationName: 'Example medication',
        pharmacyName: 'Example pharmacy',
        rxLastFour: '1234',
        inventoryUnits: 13,
        dailyUnits: 2,
        stage: RefillJourneyStage.planAhead,
      );

      expect(state.estimatedDays, 6);
      expect(state.supplyProgress, closeTo(0.2, 0.001));
    });

    test('keeps handoff, receipt, and inventory updates separate', () {
      final now = DateTime(2026, 10, 15, 9, 30);
      final controller = RefillStationController(clock: () => now);
      addTearDown(controller.dispose);

      expect(controller.prepareHandoff(), isTrue);
      expect(
        controller.state.stage,
        RefillJourneyStage.handoffPrepared,
      );
      expect(controller.state.receiptRecordedAt, isNull);

      expect(controller.markPharmacyContacted(), isTrue);
      expect(controller.markReady(), isTrue);
      expect(controller.markReceived(), isTrue);
      expect(controller.state.stage, RefillJourneyStage.received);
      expect(controller.state.receiptRecordedAt, now);
      expect(controller.state.inventoryUnits, 6);

      expect(controller.reconcileReceivedSupply(30), isTrue);
      expect(controller.state.stage, RefillJourneyStage.reconciled);
      expect(controller.state.receivedQuantity, 30);
      expect(controller.state.inventoryUnits, 36);
      expect(controller.state.inventoryReconciledAt, now);
    });

    test('rejects impossible or repeated supply reconciliation', () {
      final controller = RefillStationController();
      addTearDown(controller.dispose);

      expect(controller.reconcileReceivedSupply(30), isFalse);
      controller
        ..prepareHandoff()
        ..markPharmacyContacted()
        ..markReceived();

      expect(controller.reconcileReceivedSupply(0), isFalse);
      expect(controller.reconcileReceivedSupply(1000), isFalse);
      expect(controller.reconcileReceivedSupply(30), isTrue);
      expect(controller.reconcileReceivedSupply(30), isFalse);
      expect(controller.state.inventoryUnits, 36);
    });
  });
}
