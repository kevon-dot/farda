/// GTM-517 — client model of the caregiver device-summary payload.
///
/// Mirrors the shape returned by `GET /api/caregiver/devices` (per-device) and
/// `GET /api/caregiver/devices/:id/summary` on the Vial backend. The backend
/// only serves these for an ACCEPTED grant, so merely holding this model implies
/// the server already authorized the read.
class CaregiverDeviceSummary {
  final String? deviceId;
  final String? deviceName;
  final num? batteryPercent;
  final bool isOnline;

  /// ISO-8601 timestamp string of the last time the device was seen, or null.
  final String? lastSeen;

  /// Most-recent events (newest first). Used to derive adherence/missed-dose
  /// status. Each entry is the raw event map from the backend.
  final List<Map<String, dynamic>> recentEvents;

  final int totalEvents;

  const CaregiverDeviceSummary({
    this.deviceId,
    this.deviceName,
    this.batteryPercent,
    this.isOnline = false,
    this.lastSeen,
    this.recentEvents = const [],
    this.totalEvents = 0,
  });

  factory CaregiverDeviceSummary.fromJson(Map<String, dynamic> json) {
    // The list endpoint flattens device fields onto each entry; the single
    // summary endpoint nests them under a `device` object. Accept both.
    final device =
        json['device'] is Map<String, dynamic> ? json['device'] as Map<String, dynamic> : json;

    final rawEvents = json['recent_events'];
    final events = rawEvents is List
        ? rawEvents.whereType<Map<String, dynamic>>().toList()
        : <Map<String, dynamic>>[];

    return CaregiverDeviceSummary(
      deviceId: device['device_id']?.toString(),
      deviceName: device['device_name']?.toString(),
      batteryPercent: device['battery_percent'] is num
          ? device['battery_percent'] as num
          : null,
      isOnline: device['is_online'] == true,
      lastSeen: device['last_seen']?.toString(),
      recentEvents: events,
      totalEvents: json['total_events'] is int ? json['total_events'] as int : 0,
    );
  }
}
