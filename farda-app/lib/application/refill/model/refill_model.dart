/// Models for the refill prediction + pharmacy-readiness feature (GTM-541).
///
/// PURE Dart (no Flutter / plugin imports) so the prediction helper and the
/// event-payload builder can be unit-tested under `flutter test` without
/// touching platform channels, matching `test/models_test.dart`.

/// Where the remaining-pill count came from. Mirrors the backend
/// `RemainingSource`: a precise weight-sensor reading vs the qty−doses estimate.
enum RemainingSource { measured, estimated }

RemainingSource _sourceFromWire(String? v) {
  return v == 'measured' ? RemainingSource.measured : RemainingSource.estimated;
}

/// The refill-event types the backend accepts. Kept in sync with the backend
/// `REFILL_EVENT_TYPES` so the analytics vocabulary stays stable.
enum RefillEventType {
  requested,
  completed,
  delayed;

  /// The wire value sent to the backend (uppercase, matching Prisma/zod).
  String get wire => name.toUpperCase();
}

/// A single per-prescription refill prediction, as returned by the backend
/// `GET /refills` endpoint (one entry per prescription).
class RefillModel {
  final String prescriptionId;
  final String? rxNumber;
  final String? storeNumber;
  final String? pharmacyName;
  final String? medicineName;

  /// Remaining pills (clamped at 0). Null when it cannot be determined.
  final int? remaining;
  final RemainingSource remainingSource;
  final double dailyRate;

  /// Whole days of supply left. Null when remaining/rate are unknown.
  final int? daysLeft;

  /// Date the supply is predicted to run out. Null when unknown.
  final DateTime? predictedDepletion;

  /// Date the user should request a refill (depletion − lead time). Null when
  /// unknown.
  final DateTime? refillDue;

  /// True when refillDue is today or in the past (act now).
  final bool isRefillDue;

  RefillModel({
    required this.prescriptionId,
    this.rxNumber,
    this.storeNumber,
    this.pharmacyName,
    this.medicineName,
    this.remaining,
    this.remainingSource = RemainingSource.estimated,
    this.dailyRate = 0,
    this.daysLeft,
    this.predictedDepletion,
    this.refillDue,
    this.isRefillDue = false,
  });

  factory RefillModel.fromJson(Map<String, dynamic> json) {
    return RefillModel(
      prescriptionId: json['prescriptionId']?.toString() ?? '',
      rxNumber: json['rxNumber']?.toString(),
      storeNumber: json['storeNumber']?.toString(),
      pharmacyName: json['pharmacyName']?.toString(),
      medicineName: json['medicineName']?.toString(),
      remaining: _asInt(json['remaining']),
      remainingSource: _sourceFromWire(json['remainingSource']?.toString()),
      dailyRate: _asDouble(json['dailyRate']) ?? 0,
      daysLeft: _asInt(json['daysLeft']),
      predictedDepletion: _asDate(json['predictedDepletion']),
      refillDue: _asDate(json['refillDue']),
      isRefillDue: json['isRefillDue'] == true,
    );
  }

  /// True when the prediction has enough data to show a depletion forecast.
  bool get hasForecast => daysLeft != null && refillDue != null;

  static int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  static double? _asDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static DateTime? _asDate(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString());
  }
}

/// Refill-adherence metrics, as returned by `GET /refills/metrics`.
class RefillMetrics {
  final int requested;
  final int completed;
  final int delayed;

  /// completed / requested, in [0, 1]. Null when nothing was requested.
  final double? completionRate;

  const RefillMetrics({
    this.requested = 0,
    this.completed = 0,
    this.delayed = 0,
    this.completionRate,
  });

  factory RefillMetrics.fromJson(Map<String, dynamic> json) {
    return RefillMetrics(
      requested: RefillModel._asInt(json['requested']) ?? 0,
      completed: RefillModel._asInt(json['completed']) ?? 0,
      delayed: RefillModel._asInt(json['delayed']) ?? 0,
      completionRate: RefillModel._asDouble(json['completionRate']),
    );
  }
}

/// PURE prediction + payload helpers. Static so they can be unit-tested without
/// HTTP, mirroring `ReminderScheduler.buildEventPayload`.
class RefillCalc {
  /// Default days of runway we want the user to refill BEFORE depletion. Kept
  /// in sync with the backend `DEFAULT_REFILL_LEAD_DAYS`.
  static const int defaultLeadDays = 7;

  /// Client-side mirror of the backend depletion math, so the app can show a
  /// prediction for a freshly-saved prescription before the next `/refills`
  /// fetch, and so the helper is unit-testable. Returns a record of the derived
  /// values. `remaining`/`daysLeft`/dates are null when inputs are insufficient.
  ///
  /// HARDWARE FLAG: pass [measuredRemaining] (weight-sensor count) to override
  /// the qty−doses estimate once real weight capture lands.
  static ({
    int? remaining,
    RemainingSource source,
    int? daysLeft,
    DateTime? predictedDepletion,
    DateTime? refillDue,
    bool isRefillDue,
  }) predict({
    required int? initialQty,
    required int dosesTaken,
    required double dailyRate,
    int? measuredRemaining,
    int leadDays = defaultLeadDays,
    DateTime? now,
  }) {
    final reference = _dateOnly(now ?? DateTime.now());
    final rate = dailyRate > 0 ? dailyRate : 0;

    int? remaining;
    RemainingSource source;
    if (measuredRemaining != null && measuredRemaining >= 0) {
      remaining = measuredRemaining;
      source = RemainingSource.measured;
    } else if (initialQty != null) {
      remaining = initialQty - (dosesTaken < 0 ? 0 : dosesTaken);
      if (remaining < 0) remaining = 0;
      source = RemainingSource.estimated;
    } else {
      remaining = null;
      source = RemainingSource.estimated;
    }

    if (remaining == null || rate <= 0) {
      return (
        remaining: remaining,
        source: source,
        daysLeft: null,
        predictedDepletion: null,
        refillDue: null,
        isRefillDue: remaining != null && remaining <= 0,
      );
    }

    final daysLeft = (remaining / rate).floor();
    final depletion = reference.add(Duration(days: daysLeft));
    final refillDue = depletion.subtract(Duration(days: leadDays));
    final isRefillDue = !refillDue.isAfter(reference);

    return (
      remaining: remaining,
      source: source,
      daysLeft: daysLeft,
      predictedDepletion: depletion,
      refillDue: refillDue,
      isRefillDue: isRefillDue,
    );
  }

  /// Builds the JSON body for `POST /refills/events`. Pure + testable. Omits
  /// null fields so the backend's optional-field zod schema accepts it.
  static Map<String, dynamic> buildEventPayload({
    required RefillEventType eventType,
    String? prescriptionId,
    String? outcome,
    DateTime? refillDueDate,
    DateTime? occurredAt,
    String channel = 'MANUAL',
    Map<String, dynamic>? metadata,
  }) {
    return <String, dynamic>{
      'eventType': eventType.wire,
      if (prescriptionId != null) 'prescriptionId': prescriptionId,
      if (outcome != null) 'outcome': outcome,
      if (refillDueDate != null)
        'refillDueDate': refillDueDate.toUtc().toIso8601String(),
      'occurredAt': (occurredAt ?? DateTime.now()).toUtc().toIso8601String(),
      'channel': channel,
      if (metadata != null) 'metadata': metadata,
    };
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
}
