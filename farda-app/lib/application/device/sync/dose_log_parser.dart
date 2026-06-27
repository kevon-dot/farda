import 'dart:convert';

import 'package:farda/application/device/model/dose_log_event.dart';

/// Pure parser for the BLE dose-log sync stream (GTM-514).
///
/// The firmware streams a single framed message over the notify characteristic:
///
///   `SYNC_DATA[ {..}, {..}, ... ]`
///
/// i.e. the literal prefix `SYNC_DATA` followed by a JSON array of log entries.
/// Because BLE delivers the payload in MTU-sized chunks, the caller accumulates
/// chunks into a buffer and asks [isComplete] whether the frame has fully
/// arrived before handing the buffer here. Keeping this logic pure (no BLE, no
/// I/O) makes the parse → event mapping unit-testable in CI.
class DoseLogParser {
  static const String syncPrefix = 'SYNC_DATA';

  /// True once the accumulated [buffer] holds a complete `SYNC_DATA[...]` frame.
  /// Used by the BLE notify listener to know when to stop accumulating.
  static bool isComplete(String buffer) {
    final trimmed = buffer.trim();
    return trimmed.startsWith(syncPrefix) && trimmed.endsWith(']');
  }

  /// Parses a complete sync [buffer] into typed [DoseLogEvent]s, stamping each
  /// with [deviceId] (#23 linkage). Malformed individual rows are skipped, not
  /// fatal; a buffer that isn't a valid `SYNC_DATA[...]` frame yields an empty
  /// list. Never throws.
  static List<DoseLogEvent> parse(String buffer, String deviceId) {
    final trimmed = buffer.trim();
    if (!trimmed.startsWith(syncPrefix)) return const [];

    final jsonStr = trimmed.substring(syncPrefix.length).trim();
    if (jsonStr.isEmpty) return const [];

    dynamic decoded;
    try {
      decoded = jsonDecode(jsonStr);
    } catch (_) {
      return const [];
    }
    if (decoded is! List) return const [];

    final events = <DoseLogEvent>[];
    for (final entry in decoded) {
      if (entry is! Map<String, dynamic>) continue;
      final event = DoseLogEvent.fromDeviceJson(entry, deviceId);
      if (event != null) events.add(event);
    }
    return events;
  }
}
