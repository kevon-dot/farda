import 'dart:async';

import 'ble_sync_codec.dart';
import 'device_observation.dart';
import 'device_outbox.dart';

abstract interface class BleSyncTransport {
  Stream<List<int>> get notifications;
  Future<void> setNotifications(bool enabled);
  Future<void> write(List<int> value);
}

class DeviceSyncResult {
  const DeviceSyncResult({
    required this.persisted,
    required this.serverCommitted,
  });
  final int persisted;
  final int serverCommitted;
  // Firmware ACK 0x31 currently has no proven batch/range ownership contract.
  bool get deviceDeletionAcknowledged => false;
}

/// Independent of widgets and platform Bluetooth code. Firmware observations
/// must already contain the agreed stable identity; older unversioned logs are
/// rejected and kept on the device. No deletion opcode is exposed or written.
class BleSyncService {
  BleSyncService({
    required this.transport,
    required this.outbox,
    required this.sync,
    this.timeout = const Duration(seconds: 12),
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  final BleSyncTransport transport;
  final DeviceOutbox outbox;
  final DeviceOutboxSync sync;
  final Duration timeout;
  final DateTime Function() clock;
  bool _running = false;

  Future<DeviceSyncResult> receive({
    required String userId,
    required String deviceId,
    required String ownershipEpoch,
    required DateTime claimedAt,
    required List<int> authKey,
  }) async {
    if (_running) throw StateError('Device sync is already running');
    if (authKey.length != 32 || authKey.any((byte) => byte < 0 || byte > 255)) {
      throw ArgumentError('A provisioned 32-byte device key is required');
    }
    _running = true;
    final codec = BleSyncCodec(frameTimeout: timeout);
    final frame = Completer<List<Map<String, dynamic>>>();
    StreamSubscription<List<int>>? subscription;
    Timer? timer;
    try {
      // Subscribe before enabling notifications/requesting a frame.
      subscription = transport.notifications.listen(
        (bytes) {
          if (frame.isCompleted) return;
          try {
            final value = codec.add(bytes, now: clock());
            if (value != null) frame.complete(value);
          } catch (error, stack) {
            frame.completeError(error, stack);
          }
        },
        onError: (Object error, StackTrace stack) {
          if (!frame.isCompleted) frame.completeError(error, stack);
        },
        onDone: () {
          if (!frame.isCompleted) {
            frame.completeError(StateError('Device disconnected'));
          }
        },
      );
      // Install the consumer immediately so an early stream error is handled.
      final received = frame.future;
      final processing = received.then((raw) async {
        final observations = raw.map(DeviceObservation.fromJson).toList();
        for (final observation in observations) {
          observation.validateTime(receivedAt: clock(), claimedAt: claimedAt);
        }
        if (observations.any(
          (event) =>
              event.deviceId != deviceId ||
              event.ownershipEpoch != ownershipEpoch,
        )) {
          throw const FormatException(
            'Observation belongs to another device or ownership epoch',
          );
        }
        await outbox.enqueue(userId, observations);
        final committed = await sync.flush(userId);
        return DeviceSyncResult(
          persisted: observations.length,
          serverCommitted: committed,
        );
      });
      // Handle failures while setup is still awaiting without losing the error
      // which is returned through processing below.
      unawaited(
        processing.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
      );
      timer = Timer(timeout, () {
        if (!frame.isCompleted) {
          frame.completeError(TimeoutException('Device sync timed out'));
        }
      });
      await transport.setNotifications(true).timeout(timeout);
      await transport.write([0x30, ...authKey]).timeout(timeout);
      return await processing;
    } finally {
      timer?.cancel();
      if (!frame.isCompleted) {
        frame.completeError(StateError('Device sync closed'));
      }
      await subscription?.cancel();
      try {
        await transport.setNotifications(false).timeout(timeout);
      } catch (_) {
        /* connection may already be gone */
      }
      _running = false;
    }
  }
}
