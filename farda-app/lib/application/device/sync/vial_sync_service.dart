import 'package:farda/application/authentication/storage/auth_storage.dart';
import 'package:farda/application/device/model/dose_log_event.dart';
import 'package:farda/application/device/repo/device_repo.dart';
import 'package:farda/application/device/sync/dose_log_parser.dart';
import 'package:farda/application/device/sync/dose_sync_queue.dart';
import 'package:farda/utilities/logger_service.dart';
import 'package:http/http.dart' as http;

/// Orchestrates the vial dose-log sync → parse → upload → buffer/retry pipeline
/// (GTM-514).
///
/// Flow:
///   1. The BLE layer accumulates a `SYNC_DATA[...]` frame and hands the raw
///      buffer here together with the connected device's id (#23).
///   2. [DoseLogParser] turns it into typed [DoseLogEvent]s.
///   3. We enqueue them (de-duped) into [DoseSyncQueue], then [flush] attempts
///      to relay each to the Vial ingestion endpoint via [DeviceRepo.ingestEvent].
///   4. Delivered events are dropped from the queue; transient failures stay
///      buffered for the next sync (offline buffering + retry).
///
/// Idempotency: every event carries a STABLE [DoseLogEvent.eventId], so the
/// backend (and the local queue) drop duplicates — re-syncing the same on-device
/// log can't double-count.
///
/// HARDWARE FLAG: steps that actually move bytes over BLE (reading the
/// `SYNC_DATA` frame, sending the ACK that clears the device log) require a real
/// vial and are validated in GTM-513 / the on-device task. This service is the
/// pure app-side plumbing and is driven from
/// `screen_setup_vial.dart`'s `triggerLogSync`.
class VialSyncService {
  VialSyncService({DeviceRepo? deviceRepo})
      : _repo = deviceRepo ?? DeviceRepo();

  final DeviceRepo _repo;

  /// Parses a complete `SYNC_DATA[...]` [buffer] read off [deviceId], buffers
  /// the events, then flushes the queue. Returns the [SyncFlushResult] of the
  /// flush. Safe to call repeatedly (idempotent).
  Future<SyncFlushResult> handleSyncBuffer(
    String buffer,
    String deviceId,
  ) async {
    final events = DoseLogParser.parse(buffer, deviceId);
    Log.i("VialSync: parsed ${events.length} dose-log events for $deviceId");
    if (events.isNotEmpty) {
      await DoseSyncQueue.enqueue(events);
    }
    return flush();
  }

  /// Attempts to upload every buffered event. Delivered events are removed from
  /// the queue; events whose upload should be retried are left in place. Returns
  /// counts so the caller can decide whether to send the BLE ACK (which clears
  /// the on-device log) — only ACK when nothing is left pending.
  Future<SyncFlushResult> flush() async {
    final queued = await DoseSyncQueue.load();
    if (queued.isEmpty) {
      return const SyncFlushResult(delivered: 0, retryable: 0, attempted: 0);
    }

    final delivered = <String>{};
    int retryable = 0;

    for (final event in queued) {
      final http.Response? resp =
          await _repo.ingestEvent(event.deviceId, event.toIngestBody());
      final status = resp?.statusCode;

      if (DoseSyncQueue.isDelivered(status)) {
        delivered.add(event.eventId);
      } else if (DoseSyncQueue.shouldRetry(status)) {
        retryable++;
      } else {
        // Terminal non-2xx (e.g. 401/403 after refresh): stop hammering it,
        // drop from the queue so it doesn't block other events forever.
        delivered.add(event.eventId);
      }
    }

    if (delivered.isNotEmpty) {
      await DoseSyncQueue.removeDelivered(delivered);
    }

    final result = SyncFlushResult(
      delivered: delivered.length,
      retryable: retryable,
      attempted: queued.length,
    );
    Log.i(
      "VialSync: flush attempted=${result.attempted} "
      "delivered=${result.delivered} retryable=${result.retryable}",
    );
    return result;
  }

  /// The user id the uploaded events belong to (#23 user/prescription linkage).
  /// The Vial backend derives ownership from the better-auth session attached by
  /// [DeviceRepo]/[ApiService], so the id is informational here (logging /
  /// future per-user bookkeeping) and never trusted from the client.
  static Future<String?> currentUserId() async {
    final session = await AuthStorage.getSession();
    return session['id'];
  }
}

/// Outcome of a [VialSyncService.flush]. `retryable == 0` means the on-device
/// log is fully relayed and it's safe to ACK (clear) it over BLE.
class SyncFlushResult {
  final int delivered;
  final int retryable;
  final int attempted;

  const SyncFlushResult({
    required this.delivered,
    required this.retryable,
    required this.attempted,
  });

  /// True when nothing is left to retry — safe to send the BLE ACK that clears
  /// the device-side log.
  bool get fullyFlushed => retryable == 0;
}
