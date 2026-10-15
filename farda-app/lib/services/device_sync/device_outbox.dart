import 'dart:convert';

import 'package:farda/application/authentication/storage/session_store.dart';
import 'package:farda/utilities/secure_store.dart';

import 'device_observation.dart';

class DeviceOutbox {
  DeviceOutbox(
    this.sessions, {
    this.maxEntries = 256,
    this.maxBytes = 512 * 1024,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;
  final SessionStore sessions;
  final int maxEntries;
  final int maxBytes;
  final DateTime Function() clock;

  String _key(String userId) =>
      '${SessionStore.privatePrefix}device_outbox.v1.${Uri.encodeComponent(userId)}';

  Future<List<DeviceObservation>> _read(
    SecureStore store,
    String userId,
  ) async {
    final raw = await store.read(_key(userId));
    if (raw == null) return [];
    // Corruption must surface. Do not discard the only local observations.
    if (utf8.encode(raw).length > maxBytes) {
      throw StateError('Outbox exceeds its bound');
    }
    final data = jsonDecode(raw);
    if (data is! Map ||
        data['version'] != 1 ||
        data['userId'] != userId ||
        data['events'] is! List) {
      throw const FormatException('Invalid outbox');
    }
    final values = data['events'] as List;
    if (values.length > maxEntries) {
      throw StateError('Outbox exceeds its bound');
    }
    return values
        .map(
          (value) => DeviceObservation.fromJson(
            Map<String, dynamic>.from(value as Map),
          ),
        )
        .toList();
  }

  Future<List<DeviceObservation>> pending(String userId) =>
      sessions.forUser(userId, (store) => _read(store, userId));

  Future<void> _write(
    SecureStore store,
    String userId,
    List<DeviceObservation> events,
  ) async {
    final value = jsonEncode({
      'version': 1,
      'userId': userId,
      'events': events.map((event) => event.toJson()).toList(),
    });
    if (events.length > maxEntries || utf8.encode(value).length > maxBytes) {
      throw StateError('Outbox is full; device data must be retained');
    }
    await store.write(_key(userId), value);
  }

  /// The entire batch is validated and stored before returning. No eviction.
  Future<void> enqueue(String userId, List<DeviceObservation> observations) =>
      sessions.forUser(userId, (store) async {
        final events = await _read(store, userId);
        for (final observation in observations) {
          observation.validateTime(receivedAt: clock());
          final sameKey = events.where(
            (event) =>
                event.key == observation.key ||
                (event.deviceId == observation.deviceId &&
                    event.ownershipEpoch == observation.ownershipEpoch &&
                    event.eventId == observation.eventId),
          );
          if (sameKey.isNotEmpty) {
            if (sameKey.any(
              (event) => event.canonical != observation.canonical,
            )) {
              throw StateError('Conflicting device event identity');
            }
          } else {
            events.add(observation);
          }
        }
        await _write(store, userId, events);
      });

  Future<void> acceptReceipt(
    String userId,
    DeviceObservation observation,
    DeviceReceipt receipt,
  ) => sessions.forUser(userId, (store) async {
    if (!receipt.commits(observation)) {
      throw StateError('Server did not commit this observation');
    }
    final events = await _read(store, userId);
    final matches = events.where((event) => event.key == observation.key);
    if (matches.any((event) => event.canonical != observation.canonical)) {
      throw StateError('Observation changed while uploading');
    }
    events.removeWhere((event) => event.key == observation.key);
    await _write(store, userId, events);
  });
}

abstract interface class ObservationUploader {
  Future<DeviceReceipt> upload(String userId, DeviceObservation observation);
}

class DeviceOutboxSync {
  DeviceOutboxSync(this.outbox, this.uploader);
  final DeviceOutbox outbox;
  final ObservationUploader uploader;
  bool _running = false;

  /// Call on explicit sync/reconnect. Failed uploads remain durable and are
  /// replayed using stable server idempotency identities on the next attempt.
  Future<int> flush(String userId) async {
    if (_running) return 0;
    _running = true;
    var committed = 0;
    try {
      for (final observation in await outbox.pending(userId)) {
        final receipt = await uploader.upload(userId, observation);
        await outbox.acceptReceipt(userId, observation, receipt);
        committed++;
      }
      return committed;
    } finally {
      _running = false;
    }
  }
}
