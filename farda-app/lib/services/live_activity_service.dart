import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum LiveRoutinePhase { headsUp, due, snoozed }

enum LiveRoutineOutcome { confirmed, cancelled }

enum LiveRoutineAction { view, checkIn, snooze }

/// A display projection of an authenticated occurrence, never a dose record.
/// The channel deliberately has no medication name, amount, or phone fields.
class LiveRoutineActivity {
  const LiveRoutineActivity({
    required this.occurrenceId,
    required this.dueAt,
    required this.windowEndsAt,
    required this.updatedAt,
    required this.revision,
    required this.phase,
    this.callAt,
    this.snoozedUntil,
    this.requestPushToken = false,
  });

  final String occurrenceId;
  final DateTime dueAt;
  final DateTime windowEndsAt;
  final DateTime updatedAt;
  final int revision;
  final LiveRoutinePhase phase;
  final DateTime? callAt;
  final DateTime? snoozedUntil;
  final bool requestPushToken;

  DateTime get startsAt => dueAt.subtract(const Duration(minutes: 10));
  bool isVisibleAt(DateTime now) =>
      !now.isBefore(startsAt) && now.isBefore(windowEndsAt);

  LiveRoutineActivity at(DateTime now) => LiveRoutineActivity(
    occurrenceId: occurrenceId,
    dueAt: dueAt,
    windowEndsAt: windowEndsAt,
    updatedAt: updatedAt,
    revision: revision,
    phase:
        snoozedUntil?.isAfter(now) == true
            ? LiveRoutinePhase.snoozed
            : now.isBefore(dueAt)
            ? LiveRoutinePhase.headsUp
            : LiveRoutinePhase.due,
    callAt: snoozedUntil == null ? callAt : null,
    snoozedUntil: snoozedUntil,
    requestPushToken: requestPushToken,
  );

  Map<String, Object> toMap() {
    if (!RegExp(r'^[A-Za-z0-9._:-]{1,128}$').hasMatch(occurrenceId)) {
      throw ArgumentError.value(
        occurrenceId,
        'occurrenceId',
        'Expected an opaque occurrence ID',
      );
    }
    if (revision < 0 ||
        !windowEndsAt.isAfter(dueAt) ||
        windowEndsAt.difference(startsAt) > const Duration(hours: 8)) {
      throw ArgumentError('Invalid revision or Live Activity reminder window');
    }
    if (callAt != null &&
        (callAt!.isBefore(dueAt) || callAt!.isAfter(windowEndsAt))) {
      throw ArgumentError('Call time must be inside the reminder window');
    }
    if (phase == LiveRoutinePhase.snoozed &&
        (snoozedUntil == null || snoozedUntil!.isAfter(windowEndsAt))) {
      throw ArgumentError(
        'A snoozed reminder needs a time within the reminder window',
      );
    }
    return {
      'occurrenceId': occurrenceId,
      'dueAt': dueAt.millisecondsSinceEpoch,
      'windowEndsAt': windowEndsAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
      'revision': revision,
      'phase': phase.name,
      if (callAt != null && phase != LiveRoutinePhase.snoozed)
        'callAt': callAt!.millisecondsSinceEpoch,
      if (snoozedUntil != null)
        'snoozedUntil': snoozedUntil!.millisecondsSinceEpoch,
      'requestPushToken': requestPushToken,
    };
  }
}

class LiveActivityAvailability {
  const LiveActivityAvailability({
    required this.supported,
    required this.enabled,
    this.supportsPushToStart = false,
    this.backgroundDeliveryConfigured = false,
  });
  const LiveActivityAvailability.unavailable()
    : this(supported: false, enabled: false);
  final bool supported;
  final bool enabled;
  final bool supportsPushToStart;
  final bool backgroundDeliveryConfigured;
  factory LiveActivityAvailability.fromMap(Map<Object?, Object?> value) =>
      LiveActivityAvailability(
        supported: value['supported'] == true,
        enabled: value['enabled'] == true,
        supportsPushToStart: value['supportsPushToStart'] == true,
        backgroundDeliveryConfigured:
            value['backgroundDeliveryConfigured'] == true,
      );
}

class LiveActivityEvent {
  LiveActivityEvent(Map<Object?, Object?> value)
    : data = Map.unmodifiable(value);
  final Map<Object?, Object?> data;
  String get type => data['type'] as String? ?? 'unknown';
  String? get occurrenceId => data['occurrenceId'] as String?;
  String? get activityId => data['activityId'] as String?;
  String? get token => data['token'] as String?;
  LiveRoutineAction get action => LiveRoutineAction.values.firstWhere(
    (action) => action.name == data['action'],
    orElse: () => LiveRoutineAction.view,
  );

  // Push tokens must not leak into ordinary UI/error logging.
  @override
  String toString() => 'LiveActivityEvent($type)';
}

class ActiveLiveActivity {
  const ActiveLiveActivity({
    required this.activityId,
    required this.occurrenceId,
    required this.revision,
    required this.state,
  });
  final String activityId;
  final String occurrenceId;
  final int revision;
  final String state;
  factory ActiveLiveActivity.fromMap(Map<Object?, Object?> value) =>
      ActiveLiveActivity(
        activityId: value['activityId'] as String,
        occurrenceId: value['occurrenceId'] as String,
        revision: (value['revision'] as num).toInt(),
        state: value['state'] as String,
      );
}

/// Android, web and iOS <16.2 return unavailable without invoking ActivityKit.
/// Callers retain ordinary reminders when the native surface is unavailable.
class LiveActivityService {
  LiveActivityService({
    MethodChannel? channel,
    EventChannel? eventChannel,
    bool? isIOS,
  }) : _channel = channel ?? const MethodChannel('farda/live_activity'),
       _eventChannel =
           eventChannel ?? const EventChannel('farda/live_activity_events'),
       _isIOS =
           isIOS ?? (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS);

  final MethodChannel _channel;
  final EventChannel _eventChannel;
  final bool _isIOS;
  Stream<LiveActivityEvent>? _events;

  Stream<LiveActivityEvent> get events =>
      _events ??=
          !_isIOS
              ? const Stream<LiveActivityEvent>.empty()
              : _eventChannel.receiveBroadcastStream().map(
                (event) => LiveActivityEvent(event as Map),
              );

  Future<LiveActivityAvailability> availability() async {
    if (!_isIOS) return const LiveActivityAvailability.unavailable();
    try {
      final value = await _channel.invokeMapMethod<Object?, Object?>(
        'availability',
      );
      return value == null
          ? const LiveActivityAvailability.unavailable()
          : LiveActivityAvailability.fromMap(value);
    } on MissingPluginException {
      return const LiveActivityAvailability.unavailable();
    }
  }

  /// Re-emits currently held tokens through the protected event stream after
  /// opt-in or account recovery. Token values never enter the method result.
  Future<void> refreshTokens() async {
    if (_isIOS) await _channel.invokeMethod<void>('refreshTokens');
  }

  Future<Map<Object?, Object?>> upsert(LiveRoutineActivity activity) async {
    if (!_isIOS) return {'status': 'unsupported'};
    return await _channel.invokeMapMethod<Object?, Object?>(
          'upsert',
          activity.toMap(),
        ) ??
        {};
  }

  /// Call only after explicit confirmation has been accepted by the routine
  /// store, or after a cancellation/skip. This affects presentation only.
  Future<Map<Object?, Object?>> end(
    String occurrenceId, {
    required LiveRoutineOutcome outcome,
    required int revision,
  }) async {
    if (!_isIOS) return {'status': 'unsupported'};
    if (!RegExp(r'^[A-Za-z0-9._:-]{1,128}$').hasMatch(occurrenceId) ||
        revision < 0) {
      throw ArgumentError('A valid occurrence and revision are required');
    }
    return await _channel.invokeMapMethod<Object?, Object?>('end', {
          'occurrenceId': occurrenceId,
          'outcome': outcome.name,
          'revision': revision,
        }) ??
        {};
  }

  Future<void> endAll() async {
    if (_isIOS) await _channel.invokeMethod<void>('endAll');
  }

  Future<List<ActiveLiveActivity>> activeActivities() async {
    if (!_isIOS) return [];
    final value =
        await _channel.invokeListMethod<Object?>('activeActivities') ?? [];
    return value
        .map((entry) => ActiveLiveActivity.fromMap(entry as Map))
        .toList(growable: false);
  }

  /// Normally the event stream flushes a cold-start link. This pull method is
  /// available to clients that initialize routing before subscribing to events.
  Future<LiveActivityEvent?> consumePendingOpen() async {
    if (!_isIOS) return null;
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'consumePendingOpen',
    );
    return value == null ? null : LiveActivityEvent(value);
  }
}
