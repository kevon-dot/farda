/// Models for the reminder + notification engine (GTM-537).
///
/// These are PURE Dart (no Flutter / plugin imports) so the scheduling logic and
/// payload builders can be unit-tested under `flutter test` without touching
/// platform channels, matching `test/models_test.dart`.

/// A single upcoming reminder, derived from a backend Dose (the source of truth
/// for WHEN). The backend `/reminders/schedule` endpoint returns a list of these
/// alongside the user's delivery preferences.
class ReminderModel {
  final String doseId;
  final String? prescriptionId;
  final DateTime scheduledFor;
  final String? medicineName;

  ReminderModel({
    required this.doseId,
    this.prescriptionId,
    required this.scheduledFor,
    this.medicineName,
  });

  factory ReminderModel.fromJson(Map<String, dynamic> json) {
    return ReminderModel(
      doseId: json['doseId']?.toString() ?? '',
      prescriptionId: json['prescriptionId']?.toString(),
      scheduledFor:
          DateTime.parse(json['scheduledFor'].toString()).toLocal(),
      medicineName: json['medicineName']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'doseId': doseId,
        'prescriptionId': prescriptionId,
        'scheduledFor': scheduledFor.toUtc().toIso8601String(),
        'medicineName': medicineName,
      };

  /// A stable, positive 31-bit notification id derived from the dose id, so the
  /// SAME dose always maps to the SAME local-notification id (idempotent
  /// (re)scheduling, and cancel-by-id on dismiss/take). Local notification
  /// plugins require a 32-bit int id, so we fold the string hash into that range.
  int get notificationId {
    var hash = 0;
    for (final codeUnit in doseId.codeUnits) {
      hash = (hash * 31 + codeUnit) & 0x7fffffff;
    }
    // Avoid 0 (some platforms treat it specially).
    return hash == 0 ? 1 : hash;
  }
}

/// The user's delivery preferences: timezone + quiet hours. Quiet hours are
/// minutes-from-local-midnight in [0, 1440); the window may wrap past midnight
/// (start > end). Null bounds mean "no quiet hours".
class ReminderPreferences {
  final String? timezone;
  final int? quietHoursStart;
  final int? quietHoursEnd;

  const ReminderPreferences({
    this.timezone,
    this.quietHoursStart,
    this.quietHoursEnd,
  });

  factory ReminderPreferences.fromJson(Map<String, dynamic> json) {
    return ReminderPreferences(
      timezone: json['timezone']?.toString(),
      quietHoursStart: _asInt(json['quietHoursStart']),
      quietHoursEnd: _asInt(json['quietHoursEnd']),
    );
  }

  Map<String, dynamic> toJson() => {
        'timezone': timezone,
        'quietHoursStart': quietHoursStart,
        'quietHoursEnd': quietHoursEnd,
      };

  static int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }
}

/// The reminder-response event types the backend accepts. Kept in sync with the
/// backend `REMINDER_EVENT_TYPES` so the analytics vocabulary stays stable.
enum ReminderEventType {
  delivered,
  opened,
  snoozed,
  dismissed,
  actioned;

  /// The wire value sent to the backend (uppercase, matching Prisma/zod).
  String get wire => name.toUpperCase();
}
