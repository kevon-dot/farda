import 'package:flutter/material.dart';
import 'package:farda/features/consumer/data/consumer_models.dart';

import 'refill_station_screen.dart';
import 'refill_station_state.dart';
import 'live_refills_screen.dart';

export 'refill_station_screen.dart'
    show PharmacyContactCallback, RefillStationKeys;
export 'refill_station_state.dart'
    show
        RefillClock,
        RefillJourneyStage,
        RefillStationController,
        RefillStationState;

/// Stable integration entry point for the consumer-v2 refill experience.
class FardaRefillsScreen extends StatelessWidget {
  const FardaRefillsScreen({
    super.key,
    this.controller,
    this.initialState,
    this.onStateChanged,
    this.onOpenPharmacyContact,
    this.onReviewVial,
    this.snapshot,
    this.onUpdateInventory,
    this.onUpdateRefill,
    this.onReconcileReceipt,
    this.onOpenRefillTools,
    this.onOpenProfile,
  }) : assert(controller == null || initialState == null);

  final RefillStationController? controller;
  final RefillStationState? initialState;
  final ValueChanged<RefillStationState>? onStateChanged;
  final PharmacyContactCallback? onOpenPharmacyContact;
  final VoidCallback? onReviewVial;

  /// Non-null on the authenticated route. A null snapshot preserves the
  /// isolated design preview, which intentionally uses local sample state.
  final ConsumerSnapshot? snapshot;
  final Future<String?> Function(String prescriptionId, int quantity)?
  onUpdateInventory;
  final Future<String?> Function(
    String prescriptionId,
    RefillStage stage, {
    bool startNew,
  })?
  onUpdateRefill;
  final Future<String?> Function(
    String prescriptionId, {
    required int quantity,
    required bool alreadyIncluded,
  })?
  onReconcileReceipt;
  final VoidCallback? onOpenRefillTools;
  final VoidCallback? onOpenProfile;

  @override
  Widget build(BuildContext context) {
    if (snapshot != null) {
      return LiveRefillsScreen(
        snapshot: snapshot!,
        onUpdateInventory: onUpdateInventory,
        onUpdateRefill: onUpdateRefill,
        onReconcileReceipt: onReconcileReceipt,
        onOpenRefillTools: onOpenRefillTools,
        onOpenProfile: onOpenProfile,
      );
    }
    return RefillStationScreen(
      controller: controller,
      initialState: initialState,
      onStateChanged: onStateChanged,
      onOpenPharmacyContact: onOpenPharmacyContact,
      onReviewVial: onReviewVial,
      onOpenProfile: onOpenProfile,
    );
  }
}
