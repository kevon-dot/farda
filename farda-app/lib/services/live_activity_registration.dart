import 'dart:async';
import 'dart:math';

import 'package:farda/application/authentication/storage/session_store.dart';

import 'live_activity_service.dart';

abstract interface class LiveActivityRegistrationRepository {
  Future<void> registerPushToStartToken({
    required String installationId,
    required String token,
  });
  Future<void> registerActivityToken({
    required String installationId,
    required String activityId,
    required String occurrenceId,
    required String token,
  });
  Future<void> revokeLiveActivityInstallation(String installationId);
}

/// Serializes native token rotations into authenticated, idempotent PUTs. The
/// installation ID lives in device-only protected storage and is removed by
/// the shared private-data cleanup on logout/account switching.
class LiveActivityTokenRegistrar {
  LiveActivityTokenRegistrar({
    required this.repository,
    required this.sessions,
    this.onRegistered,
    String Function()? createInstallationId,
  }) : _createInstallationId = createInstallationId ?? _randomInstallationId;

  static const _installationKey = 'farda.private.live_activity_installation.v1';
  final LiveActivityRegistrationRepository repository;
  final SessionStore sessions;
  final FutureOr<void> Function()? onRegistered;
  final String Function() _createInstallationId;
  Future<void> _tail = Future.value();

  Future<void> handle(LiveActivityEvent event) {
    final next = _tail.then((_) => _register(event));
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  Future<String> _installationId(String userId) =>
      sessions.forUser(userId, (store) async {
        final existing = await store.read(_installationKey);
        if (existing != null && _validInstallationId(existing)) return existing;
        final created = _createInstallationId();
        if (!_validInstallationId(created)) {
          throw StateError('Installation identifier generation failed');
        }
        await store.write(_installationKey, created);
        return created;
      });

  Future<void> _register(LiveActivityEvent event) async {
    if (event.type != 'pushToStartToken' && event.type != 'pushToken') return;
    final token = event.token;
    if (token == null || !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(token)) {
      throw const FormatException('Invalid Live Activity token');
    }
    final session = await sessions.read();
    if (session == null) {
      throw StateError('An authenticated session is required');
    }
    final installationId = await _installationId(session.userId);
    if (event.type == 'pushToStartToken') {
      await repository.registerPushToStartToken(
        installationId: installationId,
        token: token,
      );
    } else {
      final activityId = event.activityId;
      final occurrenceId = event.occurrenceId;
      if (!_validOpaqueId(activityId) || !_validOpaqueId(occurrenceId)) {
        throw const FormatException('Invalid Live Activity reference');
      }
      await repository.registerActivityToken(
        installationId: installationId,
        activityId: activityId!,
        occurrenceId: occurrenceId!,
        token: token,
      );
    }
    await onRegistered?.call();
  }

  Future<void> revoke() async {
    await _tail;
    final session = await sessions.read();
    if (session == null) return;
    final installationId = await sessions.forUser(
      session.userId,
      (store) => store.read(_installationKey),
    );
    if (installationId == null || !_validInstallationId(installationId)) return;
    await repository.revokeLiveActivityInstallation(installationId);
  }

  static bool _validOpaqueId(String? value) =>
      value != null && RegExp(r'^[A-Za-z0-9._:-]{1,128}$').hasMatch(value);
  static bool _validInstallationId(String value) => RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  ).hasMatch(value);

  static String _randomInstallationId() {
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex =
        bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
