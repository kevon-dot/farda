import 'circle_models.dart';

/// Separate capability so basic Circle remains available without alerts.
abstract interface class CircleAlertsRepository {
  Future<CircleAlertPolicy> loadCircleAlertPolicy(
    String grantId, {
    bool recipient = false,
  });
  Future<void> saveCircleAlertPolicy(String grantId, CircleAlertPolicy policy);
  Future<void> setCircleAlertConsent(String grantId, bool consented);
  Future<List<CircleAlert>> loadCircleAlerts();
  Future<void> readCircleAlert(String id);
}

class CircleAlertPolicy {
  const CircleAlertPolicy({
    this.enabled = false,
    this.recipientConsented = false,
    this.gracePeriodMinutes = 60,
    this.quietHoursStart = '22:00',
    this.quietHoursEnd = '08:00',
    this.timeZone = 'UTC',
  });
  final bool enabled, recipientConsented;
  final int gracePeriodMinutes;
  final String quietHoursStart, quietHoursEnd, timeZone;
  factory CircleAlertPolicy.fromJson(Map<String, dynamic> j) =>
      CircleAlertPolicy(
        enabled: j['enabled'] == true,
        recipientConsented: j['recipientConsented'] == true,
        gracePeriodMinutes: j['gracePeriodMinutes'] as int? ?? 60,
        quietHoursStart: j['quietHoursStart'] as String? ?? '22:00',
        quietHoursEnd: j['quietHoursEnd'] as String? ?? '08:00',
        timeZone: j['timeZone'] as String? ?? 'UTC',
      );
  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'gracePeriodMinutes': gracePeriodMinutes,
    'quietHoursStart': quietHoursStart,
    'quietHoursEnd': quietHoursEnd,
    'timeZone': timeZone,
  };
}

class CircleAlert {
  const CircleAlert({
    required this.id,
    required this.owner,
    required this.createdAt,
    this.readAt,
    this.scheduledFor,
  });
  final String id;
  final CirclePerson owner;
  final DateTime createdAt;
  final DateTime? readAt, scheduledFor;
  factory CircleAlert.fromJson(Map<String, dynamic> j) => CircleAlert(
    id: j['id'] as String,
    owner: CirclePerson.fromJson(Map<String, dynamic>.from(j['owner'] as Map)),
    createdAt: DateTime.parse(j['createdAt'] as String),
    scheduledFor: DateTime.tryParse(j['scheduledFor'] as String? ?? ''),
    readAt: DateTime.tryParse(j['readAt'] as String? ?? ''),
  );
}
