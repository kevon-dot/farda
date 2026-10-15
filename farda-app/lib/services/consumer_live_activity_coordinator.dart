import 'dart:async';

import 'package:flutter/widgets.dart';

import 'live_activity_service.dart';

typedef OpenLiveRoutine = FutureOr<void> Function(
  String occurrenceId,
  LiveRoutineAction action,
);

/// Bridges authenticated consumer snapshots to native display. Foreground
/// timers improve continuity while the app is open; they are not a background
/// delivery mechanism. Server ActivityKit/APNs must provide background starts.
class ConsumerLiveActivityCoordinator with WidgetsBindingObserver {
  ConsumerLiveActivityCoordinator({
    required this.service,
    required this.onOpenRoutine,
    this.onError,
    this.onEvent,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final LiveActivityService service;
  final OpenLiveRoutine onOpenRoutine;
  final void Function(Object error)? onError;
  final void Function(LiveActivityEvent event)? onEvent;
  final DateTime Function() _clock;
  List<LiveRoutineActivity> _occurrences = const [];
  StreamSubscription<LiveActivityEvent>? _subscription;
  Timer? _boundary;
  bool _enabled = false;
  bool _attached = false;
  bool _disposed = false;
  bool _foreground = true;
  int _generation = 0;
  Future<void> _queue = Future.value();

  void attach() {
    if (_attached || _disposed) return;
    _attached = true;
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _subscription = service.events.listen((event) async {
      onEvent?.call(
        event,
      ); // Token registration belongs to an authenticated backend adapter.
      if (event.type == 'openRoutine' && event.occurrenceId != null) {
        try {
          await onOpenRoutine(event.occurrenceId!, event.action);
        } catch (error) {
          onError?.call(error);
        }
      } else if (event.type == 'authorization') {
        unawaited(_scheduleSync());
      }
    }, onError: (Object error) => onError?.call(error));
  }

  /// Supply the complete unresolved occurrence set for the current account,
  /// including upcoming occurrences, after a successful authenticated fetch.
  /// Do not call with an empty list merely because a network request failed.
  Future<void> reconcile({
    required Iterable<LiveRoutineActivity> occurrences,
    required bool enabled,
  }) {
    _occurrences = List.unmodifiable(occurrences);
    _enabled = enabled;
    _generation++;
    return _scheduleSync();
  }

  Future<void> resolve(
    String occurrenceId, {
    required LiveRoutineOutcome outcome,
    required int revision,
  }) async {
    _occurrences = _occurrences
        .where((entry) => entry.occurrenceId != occurrenceId)
        .toList(growable: false);
    _generation++;
    // Serialized behind any previously requested upsert; no pending callback
    // can revive a dose after an explicit terminal update.
    final previous = _queue;
    _queue = () async {
      await previous;
      try {
        await service.end(occurrenceId, outcome: outcome, revision: revision);
      } catch (error) {
        onError?.call(error);
      }
    }();
    await _queue;
    await _scheduleSync();
  }

  Future<void> signOut() async {
    _occurrences = const [];
    _enabled = false;
    _generation++;
    _boundary?.cancel();
    await _scheduleSync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      unawaited(_scheduleSync());
    } else {
      _boundary?.cancel();
    }
  }

  Future<void> _scheduleSync() {
    if (_disposed) return Future.value();
    final generation = _generation;
    final previous = _queue;
    _queue = () async {
      await previous;
      if (_disposed || generation != _generation) return;
      try {
        await _sync(generation);
      } catch (error) {
        onError?.call(error);
      }
    }();
    return _queue;
  }

  Future<void> _sync(int generation) async {
    _boundary?.cancel();
    final availability = await service.availability();
    if (_disposed || generation != _generation || !availability.supported) {
      return;
    }
    if (!_enabled) {
      await service.endAll();
      return;
    }
    if (!availability.enabled || !_foreground) return;
    final now = _clock();
    final visible = _occurrences
        .where((entry) => entry.isVisibleAt(now))
        .toList(growable: false);
    final ids = visible.map((entry) => entry.occurrenceId).toSet();
    for (final existing in await service.activeActivities()) {
      if (_disposed || generation != _generation) return;
      if (!ids.contains(existing.occurrenceId)) {
        await service.end(
          existing.occurrenceId,
          outcome: LiveRoutineOutcome.cancelled,
          revision: existing.revision,
        );
      }
    }
    for (final entry in visible) {
      if (_disposed || generation != _generation) return;
      try {
        await service.upsert(entry.at(now));
      } catch (error) {
        onError?.call(error);
      }
    }
    final boundaries =
        _occurrences
            .expand(
              (entry) => [
                entry.startsAt,
                entry.dueAt,
                entry.windowEndsAt,
                if (entry.snoozedUntil != null) entry.snoozedUntil!,
              ],
            )
            .where((date) => date.isAfter(now))
            .toList()
          ..sort();
    if (boundaries.isNotEmpty &&
        !_disposed &&
        generation == _generation &&
        _foreground) {
      _boundary = Timer(
        boundaries.first.difference(now),
        () => unawaited(_scheduleSync()),
      );
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _boundary?.cancel();
    if (_attached) WidgetsBinding.instance.removeObserver(this);
    await _subscription?.cancel();
    // Disposing a view does not cancel an active reminder. Call signOut() or
    // reconcile(enabled:false) when account/preferences actually change.
  }
}
