import 'dart:convert';

/// A single dose/interaction event read off a vial over BLE during a log sync
/// (GTM-514).
///
/// The firmware buffers events while offline and hands them to the app in one
/// `SYNC_DATA[...]` payload (see [DoseLogParser]). The app then relays each
/// event to the Vial ingestion endpoint (see `DeviceRepo.ingestEvent`).
///
/// Wire format expected by the Vial backend (smart-vial-backend
/// `utils/eventValidation.js`):
/// ```
/// { device_id, event, event_id, timestamp, payload }
/// ```
/// where `event` is an uppercase event type (OPEN/CLOSE/...), `timestamp` is
/// unix SECONDS, and `event_id` is the idempotency key the backend dedupes on
/// (`Event.idempotency_key`). We compute a STABLE [eventId] so a re-sync of the
/// same on-device log never double-counts.
class DoseLogEvent {
  /// The vial this event came from (#23 deviceId linkage). Populated from the
  /// connected BLE device's remoteId when the event is parsed.
  final String deviceId;

  /// Uppercase event type, e.g. `OPEN`, `CLOSE`, `TILT`. Backend rejects
  /// unknown types, so we normalise to uppercase here.
  final String event;

  /// Device timestamp in unix SECONDS, if the firmware stamped the event.
  final int? timestamp;

  /// Optional monotonic sequence number the firmware assigns per event. When
  /// present it makes the idempotency key collision-proof even for two events
  /// of the same type at the same second.
  final int? sequence;

  /// Type-specific payload (duration, sensor_value, ...). Passed through to the
  /// backend, which keeps it lenient.
  final Map<String, dynamic> payload;

  const DoseLogEvent({
    required this.deviceId,
    required this.event,
    this.timestamp,
    this.sequence,
    this.payload = const {},
  });

  /// Parses one raw log entry as emitted by the firmware. Tolerates the field
  /// naming the firmware uses (`ts`/`timestamp`, `seq`/`sequence`,
  /// `type`/`event`). [deviceId] is supplied by the caller because the firmware
  /// log entries are per-device and don't repeat the id.
  ///
  /// Returns `null` for an entry that has no usable event type, so a single
  /// malformed row can't poison the whole batch.
  static DoseLogEvent? fromDeviceJson(
    Map<String, dynamic> json,
    String deviceId,
  ) {
    final rawType = (json['event'] ?? json['type'] ?? json['e'])?.toString();
    if (rawType == null || rawType.trim().isEmpty) return null;

    final ts = _asInt(json['timestamp'] ?? json['ts'] ?? json['t']);
    final seq = _asInt(json['sequence'] ?? json['seq'] ?? json['s']);

    final rawPayload = json['payload'] ?? json['data'];
    final payload = rawPayload is Map<String, dynamic>
        ? rawPayload
        : <String, dynamic>{};

    return DoseLogEvent(
      deviceId: deviceId,
      event: rawType.trim().toUpperCase(),
      timestamp: ts,
      sequence: seq,
      payload: payload,
    );
  }

  static int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }

  /// Stable, idempotent event id used for backend dedupe (A3 / ingestion
  /// `idempotency_key`) AND local queue dedupe.
  ///
  /// It is derived purely from the event's own identity — device, type,
  /// timestamp and (when present) firmware sequence — so re-reading the same
  /// on-device log yields the SAME id and the backend's
  /// `Event.findOne({ idempotency_key })` short-circuits the duplicate. It must
  /// NOT depend on wall-clock-at-upload or a random nonce, or re-sync would
  /// double-count.
  String get eventId {
    final parts = [
      deviceId,
      event,
      timestamp?.toString() ?? 'na',
      sequence?.toString() ?? 'na',
    ];
    // When neither a timestamp nor a sequence is available we fall back to a
    // hash of the payload so otherwise-identical-looking rows still differ.
    if (timestamp == null && sequence == null && payload.isNotEmpty) {
      parts.add(jsonEncode(payload));
    }
    return 'evt_${_fnv1a(parts.join('|'))}';
  }

  /// Builds the exact JSON body the Vial ingestion endpoint expects. Extracted
  /// so the payload shape is unit-testable without any network.
  Map<String, dynamic> toIngestBody() {
    return {
      'device_id': deviceId,
      'event': event,
      'event_id': eventId,
      if (timestamp != null) 'timestamp': timestamp,
      'payload': payload,
    };
  }

  /// Round-trips for offline-queue persistence (SharedPreferences JSON).
  Map<String, dynamic> toQueueJson() {
    return {
      'device_id': deviceId,
      'event': event,
      'timestamp': timestamp,
      'sequence': sequence,
      'payload': payload,
    };
  }

  factory DoseLogEvent.fromQueueJson(Map<String, dynamic> json) {
    return DoseLogEvent(
      deviceId: json['device_id']?.toString() ?? '',
      event: (json['event']?.toString() ?? '').toUpperCase(),
      timestamp: _asInt(json['timestamp']),
      sequence: _asInt(json['sequence']),
      payload: json['payload'] is Map<String, dynamic>
          ? json['payload'] as Map<String, dynamic>
          : <String, dynamic>{},
    );
  }

  /// 32-bit FNV-1a hash rendered as hex. Tiny, dependency-free, deterministic —
  /// good enough for a dedupe key (the backend index enforces true uniqueness).
  static String _fnv1a(String input) {
    const int fnvPrime = 0x01000193;
    const int fnvOffset = 0x811c9dc5;
    const int mask = 0xFFFFFFFF;
    int hash = fnvOffset;
    for (final codeUnit in utf8.encode(input)) {
      hash = (hash ^ codeUnit) & mask;
      hash = (hash * fnvPrime) & mask;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}
