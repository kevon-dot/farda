import 'dart:convert';

import 'package:farda/application/device/model/dose_log_event.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Offline buffer + retry bookkeeping for vial dose-log events (GTM-514).
///
/// When an upload can't reach the Vial ingestion endpoint (device offline, 5xx,
/// network error) the events are queued here and retried on the next sync.
/// Uploads are IDEMPOTENT: dedupe is keyed on [DoseLogEvent.eventId] both
/// locally (we never enqueue the same event twice) and on the backend
/// (`Event.idempotency_key`), so re-syncing the same on-device log can't
/// double-count.
///
/// The pure decision helpers ([mergeForEnqueue], [shouldRetry]) carry the logic
/// and are unit-tested without a plugin channel; [load]/[save] are the thin
/// SharedPreferences persistence layer.
class DoseSyncQueue {
  static const String _prefsKey = 'vial_dose_sync_queue_v1';

  /// HTTP status codes that should NOT be retried: the request was understood
  /// and rejected (or accepted) deterministically, so retrying is pointless and
  /// only wastes battery/bandwidth.
  ///
  /// 200/201 — accepted (incl. "duplicate ignored").
  /// 400      — malformed/unclaimed device; will never succeed unchanged.
  /// 401/403  — auth problem handled by ApiService's refresh-on-401; a still-
  ///            failing auth means the user must re-auth, not that we re-queue.
  static const Set<int> _terminalStatuses = {200, 201, 400, 401, 403};

  /// Merges [incoming] events into an existing [queued] list, dropping any whose
  /// [DoseLogEvent.eventId] is already present (local idempotency). Preserves
  /// insertion order: existing items first, then genuinely new ones. Pure.
  static List<DoseLogEvent> mergeForEnqueue(
    List<DoseLogEvent> queued,
    List<DoseLogEvent> incoming,
  ) {
    final seen = <String>{for (final e in queued) e.eventId};
    final merged = <DoseLogEvent>[...queued];
    for (final e in incoming) {
      if (seen.add(e.eventId)) {
        merged.add(e);
      }
    }
    return merged;
  }

  /// The retry decision for a single upload attempt. Pure so it can be tested
  /// exhaustively.
  ///
  /// * `null` status -> transport failure (offline / DNS / timeout): RETRY.
  /// * terminal status -> do NOT retry (accepted or permanently rejected).
  /// * anything else (e.g. 429, 500, 502, 503) -> RETRY later.
  static bool shouldRetry(int? statusCode) {
    if (statusCode == null) return true;
    if (_terminalStatuses.contains(statusCode)) return false;
    return true;
  }

  /// Whether an upload attempt counts as durably delivered, i.e. the event can
  /// be dropped from the queue. A 2xx (including the backend's idempotent
  /// "Duplicate event ignored" 200) and a 400 (will never succeed) are both
  /// considered done; transient failures are not.
  static bool isDelivered(int? statusCode) {
    if (statusCode == null) return false;
    if (statusCode >= 200 && statusCode < 300) return true;
    // A hard 400 (bad/unclaimed device) is unrecoverable for this event; treat
    // it as terminally handled so it stops clogging the queue.
    return statusCode == 400;
  }

  // ---------------------------------------------------------------------------
  // Persistence (SharedPreferences). Thin; the interesting logic is above.
  // ---------------------------------------------------------------------------

  /// Loads the buffered events. Returns empty on first run or corrupt data.
  static Future<List<DoseLogEvent>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    return decode(raw);
  }

  /// Persists [events] (replacing the stored queue).
  static Future<void> save(List<DoseLogEvent> events) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, encode(events));
  }

  /// Enqueues [incoming] de-duped against what's already stored.
  static Future<List<DoseLogEvent>> enqueue(
    List<DoseLogEvent> incoming,
  ) async {
    final merged = mergeForEnqueue(await load(), incoming);
    await save(merged);
    return merged;
  }

  /// Removes the events whose ids are in [deliveredIds] from the stored queue.
  static Future<List<DoseLogEvent>> removeDelivered(
    Set<String> deliveredIds,
  ) async {
    final remaining =
        (await load()).where((e) => !deliveredIds.contains(e.eventId)).toList();
    await save(remaining);
    return remaining;
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  // --- pure (de)serialisation, testable ---

  static String encode(List<DoseLogEvent> events) {
    return jsonEncode(events.map((e) => e.toQueueJson()).toList());
  }

  static List<DoseLogEvent> decode(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(DoseLogEvent.fromQueueJson)
          .toList();
    } catch (_) {
      return [];
    }
  }
}
