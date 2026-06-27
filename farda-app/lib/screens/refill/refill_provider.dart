import 'package:farda/application/refill/model/refill_model.dart';
import 'package:farda/application/refill/repo/refill_repo.dart';
import 'package:flutter/foundation.dart';

/// State for the refill prediction + pharmacy-readiness experience (GTM-541).
///
/// Holds the session user's per-prescription refill predictions + adherence
/// metrics. Like the calendar / prescription / caregiver providers it does NOT
/// fetch on construction (its endpoints are authenticated and the bearer token
/// is empty before login); the screen triggers [load] post-auth in initState.
///
/// Capturing refill events (requested/completed) is delegated to [logEvent],
/// which optimistically does NOT mutate local state — the next [load] re-derives
/// the prediction from the backend (the source of truth).
class RefillProvider extends ChangeNotifier {
  RefillProvider({RefillRepo? repo}) : _repo = repo ?? RefillRepo();

  final RefillRepo _repo;

  List<RefillModel> _refills = const [];
  List<RefillModel> get refills => _refills;

  RefillMetrics _metrics = const RefillMetrics();
  RefillMetrics get metrics => _metrics;

  bool _loading = false;
  bool get isLoading => _loading;

  String? _error;
  String? get error => _error;

  /// Prescriptions that are due (or past due) for a refill, surfaced first.
  List<RefillModel> get dueRefills =>
      _refills.where((r) => r.isRefillDue).toList();

  /// True when at least one prescription needs a refill now — drives the
  /// in-app refill-reminder banner.
  bool get hasDueRefills => _refills.any((r) => r.isRefillDue);

  /// Loads predictions + adherence metrics. Tolerant of partial failure: a null
  /// response leaves the previous state intact.
  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final refills = await _repo.fetchRefills();
      if (refills != null) _refills = refills;

      final metrics = await _repo.fetchMetrics();
      if (metrics != null) _metrics = metrics;

      if (refills == null) {
        _error = 'Could not load refill predictions.';
      }
    } catch (e) {
      debugPrint('RefillProvider.load error: $e');
      _error = 'Could not load refill predictions.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Captures a refill event to the backend and (on success) refreshes so the
  /// prediction reflects it. Returns true on success.
  Future<bool> logEvent({
    required RefillEventType eventType,
    String? prescriptionId,
    String? outcome,
    DateTime? refillDueDate,
    String channel = 'MANUAL',
    Map<String, dynamic>? metadata,
  }) async {
    final ok = await _repo.logEvent(
      eventType: eventType,
      prescriptionId: prescriptionId,
      outcome: outcome,
      refillDueDate: refillDueDate,
      channel: channel,
      metadata: metadata,
    );
    if (ok) {
      // Re-derive from the backend so adherence metrics + any server-side
      // outcome are reflected.
      await load();
    }
    return ok;
  }

  /// Convenience: capture a "refill requested" for a prediction row, tagging the
  /// non-PHI context (daysLeft + remaining source) the analytics pipeline uses.
  Future<bool> requestRefill(RefillModel refill) {
    return logEvent(
      eventType: RefillEventType.requested,
      prescriptionId: refill.prescriptionId,
      outcome: 'manual',
      refillDueDate: refill.refillDue,
      metadata: {
        if (refill.daysLeft != null) 'daysLeft': refill.daysLeft,
        'remainingSource': refill.remainingSource.name,
      },
    );
  }

  /// Convenience: capture a "refill completed" (picked up / dispensed).
  Future<bool> markRefillCompleted(RefillModel refill) {
    return logEvent(
      eventType: RefillEventType.completed,
      prescriptionId: refill.prescriptionId,
      outcome: 'manual',
      refillDueDate: refill.refillDue,
    );
  }
}
