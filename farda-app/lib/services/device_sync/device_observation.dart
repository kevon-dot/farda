import 'dart:convert';

/// Physical evidence only. This model has no dose status or 'taken' setter.
class DeviceObservation {
  DeviceObservation._(
    this.deviceId,
    this.eventId,
    this.ownershipEpoch,
    this.bootId,
    this.sequence,
    this.event,
    this.timestamp,
    this.payload,
  );

  final String deviceId;
  final String eventId;
  final String ownershipEpoch;
  final String bootId;
  final int sequence;
  final String event;
  final int timestamp;
  final Map<String, dynamic> payload;

  static String _id(dynamic value, String name) {
    if (value is! String ||
        !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$').hasMatch(value)) {
      throw FormatException('Invalid $name');
    }
    return value;
  }

  factory DeviceObservation.fromJson(Map<String, dynamic> json) {
    const fields = {
      'device_id',
      'event_id',
      'ownership_epoch',
      'boot_id',
      'sequence',
      'event',
      'timestamp',
      'payload',
    };
    if (json.keys.any((key) => !fields.contains(key))) {
      throw const FormatException('Unknown observation field');
    }
    final sequence = json['sequence'];
    final timestamp = json['timestamp'];
    final payload = json['payload'];
    final event = json['event'];
    if (sequence is! int ||
        sequence < 0 ||
        sequence > 9007199254740991 ||
        timestamp is! int ||
        timestamp < 946684800 ||
        timestamp > 4102444800 ||
        payload is! Map<String, dynamic> ||
        utf8.encode(jsonEncode(payload)).length > 4096 ||
        event is! String ||
        !allowedEvents.contains(event)) {
      throw const FormatException('Unsupported device observation');
    }
    _validatePayload(payload);
    final battery = payload['battery'];
    if (battery != null &&
        (battery is! num ||
            !battery.isFinite ||
            battery < 0 ||
            battery > 100)) {
      throw const FormatException('Invalid battery level');
    }
    return DeviceObservation._(
      _id(json['device_id'], 'device ID'),
      _id(json['event_id'], 'event ID'),
      _id(json['ownership_epoch'], 'ownership epoch'),
      _id(json['boot_id'], 'boot ID'),
      sequence,
      event,
      timestamp,
      _freeze(payload) as Map<String, dynamic>,
    );
  }

  static const allowedEvents = {
    'OPEN',
    'CLOSE',
    'PILL_CHANGE',
    'MANY_PILLS_CHANGE',
    'OUTSIDE_WINDOW_CHANGE',
    'BLE_LOCK_CMD',
    'BLE_UNLOCK_CMD',
    'EMERGENCY_UNLOCK',
    'SAFETY_TIMEOUT',
    'VIAL_RESTARTED',
    'LOW_BATTERY_5',
    'LOW_BATTERY_2',
  };

  static void _validatePayload(Object? value, [int depth = 0]) {
    if (depth > 4) throw const FormatException('Payload nesting exceeds bound');
    if (value is Map) {
      if (value.length > 32) {
        throw const FormatException('Payload exceeds bound');
      }
      for (final entry in value.entries) {
        if (entry.key is! String ||
            !RegExp(
              r'^[a-zA-Z][a-zA-Z0-9_]{0,63}$',
            ).hasMatch(entry.key as String) ||
            RegExp(
              r'secret|auth|token|password|api_?key|credential',
              caseSensitive: false,
            ).hasMatch(entry.key as String)) {
          throw const FormatException('Unsupported payload key');
        }
        _validatePayload(entry.value, depth + 1);
      }
    } else if (value is List) {
      if (value.length > 32) {
        throw const FormatException('Payload exceeds bound');
      }
      for (final item in value) {
        _validatePayload(item, depth + 1);
      }
    } else if (value is String) {
      if (value.length > 512) {
        throw const FormatException('Payload text exceeds bound');
      }
    } else if (value is num) {
      if (!value.isFinite) throw const FormatException('Invalid sensor value');
    } else if (value != null && value is! bool) {
      throw const FormatException('Unsupported sensor value');
    }
  }

  /// Admission-time clock validation. Stored records remain readable after a
  /// phone clock change; a retry never rewrites the device's original time.
  void validateTime({required DateTime receivedAt, DateTime? claimedAt}) {
    if (timestamp > receivedAt.millisecondsSinceEpoch ~/ 1000 + 300 ||
        (claimedAt != null &&
            timestamp * 1000 < claimedAt.millisecondsSinceEpoch)) {
      throw const FormatException('Device clock or ownership time is invalid');
    }
  }

  Map<String, dynamic> toJson() => {
    'device_id': deviceId,
    'event_id': eventId,
    'ownership_epoch': ownershipEpoch,
    'boot_id': bootId,
    'sequence': sequence,
    'event': event,
    'timestamp': timestamp,
    'payload': payload,
  };
  Map<String, dynamic> toRequest() => Map.of(toJson())..remove('device_id');

  /// Stable firmware identity is required. Never derive an event ID from a
  /// timestamp, random phone UUID, BLE address or sensor value.
  String get key => '$deviceId/$ownershipEpoch/$bootId/$sequence';
  String get canonical => jsonEncode(_canonicalize(toJson()));

  static Object? _freeze(Object? value) {
    if (value is Map) {
      return Map<String, dynamic>.unmodifiable({
        for (final entry in value.entries)
          entry.key as String: _freeze(entry.value),
      });
    }
    if (value is List) return List<Object?>.unmodifiable(value.map(_freeze));
    return value;
  }

  static Object? _canonicalize(Object? value) {
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: _canonicalize(value[key])};
    }
    if (value is List) return value.map(_canonicalize).toList();
    return value;
  }
}

class DeviceReceipt {
  const DeviceReceipt(this.json);
  final Map<String, dynamic> json;

  bool commits(DeviceObservation observation) {
    final receipt = json['receipt'];
    return {'stored', 'duplicate'}.contains(json['status']) &&
        json['evidence_type'] == 'vial_observation' &&
        receipt is Map &&
        receipt['committed'] == true &&
        receipt['event_id'] == observation.eventId &&
        receipt['device_id'] == observation.deviceId &&
        receipt['ownership_epoch'] == observation.ownershipEpoch &&
        receipt['boot_id'] == observation.bootId &&
        receipt['sequence'] == observation.sequence;
  }
}
