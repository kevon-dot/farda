import 'package:flutter/foundation.dart';

/// The locally reported progress of a refill.
///
/// These values deliberately describe user actions rather than pharmacy or
/// prescriber confirmations. A production integration can hydrate this state,
/// but this feature does not infer fulfillment from a handoff.
enum RefillJourneyStage {
  planAhead,
  handoffPrepared,
  pharmacyContacted,
  ready,
  received,
  reconciled,
}

@immutable
class RefillStationState {
  const RefillStationState({
    required this.medicationName,
    required this.pharmacyName,
    required this.rxLastFour,
    required this.inventoryUnits,
    required this.dailyUnits,
    required this.stage,
    this.refillsRemaining,
    this.receivedQuantity,
    this.receiptRecordedAt,
    this.inventoryReconciledAt,
    this.pharmacyStatusUpdatedAt,
    this.targetSupplyDays = 30,
  }) : assert(inventoryUnits >= 0 && inventoryUnits <= 999),
       assert(dailyUnits > 0),
       assert(targetSupplyDays > 0),
       assert(rxLastFour.length == 4);

  factory RefillStationState.sample() {
    return const RefillStationState(
      medicationName: 'Daily medication',
      pharmacyName: 'Your pharmacy',
      rxLastFour: '4821',
      inventoryUnits: 6,
      dailyUnits: 1,
      stage: RefillJourneyStage.planAhead,
    );
  }

  final String medicationName;
  final String pharmacyName;
  final String rxLastFour;
  final int inventoryUnits;
  final int dailyUnits;
  final int? refillsRemaining;
  final int targetSupplyDays;
  final RefillJourneyStage stage;
  final int? receivedQuantity;
  final DateTime? receiptRecordedAt;
  final DateTime? inventoryReconciledAt;
  final DateTime? pharmacyStatusUpdatedAt;

  /// Full days represented by the user-entered count and saved schedule.
  /// Flooring avoids overstating the supply estimate.
  int get estimatedDays => inventoryUnits ~/ dailyUnits;

  double get supplyProgress =>
      (estimatedDays / targetSupplyDays).clamp(0.0, 1.0).toDouble();

  bool get hasReceipt =>
      stage == RefillJourneyStage.received ||
      stage == RefillJourneyStage.reconciled;

  bool get inventoryIsReconciled => stage == RefillJourneyStage.reconciled;

  RefillStationState copyWith({
    String? medicationName,
    String? pharmacyName,
    String? rxLastFour,
    int? inventoryUnits,
    int? dailyUnits,
    int? refillsRemaining,
    int? targetSupplyDays,
    RefillJourneyStage? stage,
    int? receivedQuantity,
    DateTime? receiptRecordedAt,
    DateTime? inventoryReconciledAt,
    DateTime? pharmacyStatusUpdatedAt,
  }) {
    return RefillStationState(
      medicationName: medicationName ?? this.medicationName,
      pharmacyName: pharmacyName ?? this.pharmacyName,
      rxLastFour: rxLastFour ?? this.rxLastFour,
      inventoryUnits: inventoryUnits ?? this.inventoryUnits,
      dailyUnits: dailyUnits ?? this.dailyUnits,
      refillsRemaining: refillsRemaining ?? this.refillsRemaining,
      targetSupplyDays: targetSupplyDays ?? this.targetSupplyDays,
      stage: stage ?? this.stage,
      receivedQuantity: receivedQuantity ?? this.receivedQuantity,
      receiptRecordedAt: receiptRecordedAt ?? this.receiptRecordedAt,
      inventoryReconciledAt:
          inventoryReconciledAt ?? this.inventoryReconciledAt,
      pharmacyStatusUpdatedAt:
          pharmacyStatusUpdatedAt ?? this.pharmacyStatusUpdatedAt,
    );
  }
}

typedef RefillClock = DateTime Function();

/// Owns only presentation state for the Refill Station.
///
/// Supply and pharmacy events remain explicit user reports. The controller
/// never calls a pharmacy, changes a prescription, or treats a handoff as an
/// order submission.
class RefillStationController extends ChangeNotifier {
  RefillStationController({
    RefillStationState? initialState,
    RefillClock? clock,
  }) : _state = initialState ?? RefillStationState.sample(),
       _clock = clock ?? DateTime.now;

  RefillStationState _state;
  final RefillClock _clock;

  RefillStationState get state => _state;

  bool prepareHandoff() {
    if (_state.stage != RefillJourneyStage.planAhead) return false;
    _replace(_state.copyWith(stage: RefillJourneyStage.handoffPrepared));
    return true;
  }

  bool markPharmacyContacted() {
    if (_state.stage != RefillJourneyStage.handoffPrepared) return false;
    _replace(
      _state.copyWith(
        stage: RefillJourneyStage.pharmacyContacted,
        pharmacyStatusUpdatedAt: _clock(),
      ),
    );
    return true;
  }

  bool markStillWaiting() {
    if (_state.stage != RefillJourneyStage.pharmacyContacted) return false;
    _replace(_state.copyWith(pharmacyStatusUpdatedAt: _clock()));
    return true;
  }

  bool markReady() {
    if (_state.stage != RefillJourneyStage.pharmacyContacted) return false;
    _replace(
      _state.copyWith(
        stage: RefillJourneyStage.ready,
        pharmacyStatusUpdatedAt: _clock(),
      ),
    );
    return true;
  }

  bool markReceived() {
    if (_state.stage != RefillJourneyStage.pharmacyContacted &&
        _state.stage != RefillJourneyStage.ready) {
      return false;
    }
    _replace(
      _state.copyWith(
        stage: RefillJourneyStage.received,
        receiptRecordedAt: _clock(),
      ),
    );
    return true;
  }

  bool reconcileReceivedSupply(int quantity) {
    if (_state.stage != RefillJourneyStage.received ||
        quantity < 1 ||
        quantity > 999 ||
        _state.inventoryUnits + quantity > 999) {
      return false;
    }
    _replace(
      _state.copyWith(
        inventoryUnits: _state.inventoryUnits + quantity,
        stage: RefillJourneyStage.reconciled,
        receivedQuantity: quantity,
        inventoryReconciledAt: _clock(),
      ),
    );
    return true;
  }

  bool correctInventoryCount(int count) {
    if (count < 0 || count > 999) return false;
    _replace(_state.copyWith(inventoryUnits: count));
    return true;
  }

  void _replace(RefillStationState next) {
    _state = next;
    notifyListeners();
  }
}
