import 'package:flutter/material.dart';

import 'refill_station_screen.dart';
import 'refill_station_state.dart';

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
  }) : assert(controller == null || initialState == null);

  final RefillStationController? controller;
  final RefillStationState? initialState;
  final ValueChanged<RefillStationState>? onStateChanged;
  final PharmacyContactCallback? onOpenPharmacyContact;
  final VoidCallback? onReviewVial;

  @override
  Widget build(BuildContext context) {
    return RefillStationScreen(
      controller: controller,
      initialState: initialState,
      onStateChanged: onStateChanged,
      onOpenPharmacyContact: onOpenPharmacyContact,
      onReviewVial: onReviewVial,
    );
  }
}
