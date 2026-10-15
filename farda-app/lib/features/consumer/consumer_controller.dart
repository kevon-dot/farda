import 'package:flutter/foundation.dart';

import 'data/consumer_models.dart';
import 'data/consumer_repository.dart';

class ConsumerController extends ChangeNotifier {
  ConsumerController(this.repository, {DateTime Function()? now})
    : clock = now ?? DateTime.now {
    selectedDate = day(clock());
    visibleMonth = DateTime(selectedDate.year, selectedDate.month);
  }
  final ConsumerRepository repository;
  final DateTime Function() clock;
  ConsumerSnapshot? snapshot;
  bool loading = false;
  bool saving = false;
  bool showCompanion = true;
  String? error;
  bool sessionExpired = false;
  late DateTime selectedDate;
  late DateTime visibleMonth;
  int tab = 0;
  String calendarFilter = 'all';
  int _request = 0;
  bool _disposed = false;

  static DateTime day(DateTime value) =>
      DateTime(value.year, value.month, value.day);
  List<ConsumerOccurrence> occurrencesFor(DateTime value) =>
      (snapshot?.occurrences ?? [])
          .where((o) => day(o.scheduledFor.toLocal()) == day(value))
          .toList()
        ..sort((a, b) => a.scheduledFor.compareTo(b.scheduledFor));
  List<ConsumerOccurrence> get today => occurrencesFor(clock());
  ConsumerOccurrence? get nextOccurrence {
    final pending =
        today.where((o) => o.status == OccurrenceStatus.unconfirmed).toList();
    return pending.isEmpty ? null : pending.first;
  }

  void selectTab(int value) {
    tab = value;
    notifyListeners();
  }

  void selectDay(DateTime value) {
    selectedDate = day(value);
    notifyListeners();
  }

  void setFilter(String value) {
    calendarFilter = value;
    notifyListeners();
  }

  void setCompanion(bool value) {
    showCompanion = value;
    notifyListeners();
  }

  Future<void> moveMonth(int delta) async {
    visibleMonth = DateTime(visibleMonth.year, visibleMonth.month + delta);
    selectedDate = visibleMonth;
    await load();
  }

  Future<void> jumpToday() async {
    selectedDate = day(clock());
    visibleMonth = DateTime(selectedDate.year, selectedDate.month);
    await load();
  }

  Future<void> load() async {
    final request = ++_request;
    loading = true;
    error = null;
    notifyListeners();
    final monthStart = DateTime(visibleMonth.year, visibleMonth.month);
    final monthEnd = DateTime(visibleMonth.year, visibleMonth.month + 1);
    // Include the complete Monday–Sunday weeks at both month edges so the
    // week selector can show real markers for its adjacent-month dates.
    // Construct local dates rather than subtracting 24 hours across DST.
    final start = DateTime(
      monthStart.year,
      monthStart.month,
      2 - monthStart.weekday,
    );
    final end = DateTime(
      monthEnd.year,
      monthEnd.month,
      1 + (8 - monthEnd.weekday) % 7,
    );
    final current = day(clock());
    try {
      // Fetch the visible month and, when necessary, a separate current window.
      // Distant history must not produce an ever-growing API date range.
      final windowStart = DateTime(
        current.year,
        current.month,
        current.day - 1,
      );
      final windowEnd = DateTime(current.year, current.month, current.day + 2);
      final needsCurrentWindow =
          start.isAfter(windowStart) || end.isBefore(windowEnd);
      final results = await Future.wait([
        repository.loadSnapshot(from: start, to: end),
        if (needsCurrentWindow)
          repository.loadSnapshot(from: windowStart, to: windowEnd),
      ]);
      final base = results.last;
      final occurrences = <String, ConsumerOccurrence>{
        for (final result in results)
          for (final occurrence in result.occurrences)
            occurrence.id: occurrence,
      };
      final result = ConsumerSnapshot(
        prescriptions: base.prescriptions,
        occurrences: occurrences.values.toList(),
        inventory: base.inventory,
        preferences: base.preferences,
        capabilities: base.capabilities,
        warnings: base.warnings,
        callConsentText: base.callConsentText,
        fetchedAt: base.fetchedAt,
      );
      if (_disposed || request != _request) return;
      snapshot = result;
      sessionExpired = false;
    } on ConsumerRepositoryException catch (e) {
      if (_disposed || request != _request) return;
      error = e.message;
      sessionExpired = e.sessionExpired;
      // Never retain another session's records after authentication expires.
      if (e.sessionExpired) snapshot = null;
    } catch (_) {
      if (_disposed || request != _request) return;
      error = 'We could not refresh your routine. Please try again.';
    } finally {
      if (!_disposed && request == _request) {
        loading = false;
        notifyListeners();
      }
    }
  }

  /// Only server-confirmed writes change the visible record. Failed forms stay open.
  Future<String?> mutate(Future<void> Function() action) async {
    if (saving) return 'Another update is still saving. Please wait.';
    saving = true;
    notifyListeners();
    try {
      await action();
      if (_disposed) return null;
      await load();
      return null;
    } on ConsumerRepositoryException catch (e) {
      if (e.sessionExpired && !_disposed) {
        snapshot = null;
        sessionExpired = true;
        error = e.message;
      }
      return e.message;
    } catch (_) {
      return 'This update was not confirmed. Check your connection and try again.';
    } finally {
      if (!_disposed) {
        saving = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_request;
    repository.dispose();
    super.dispose();
  }
}
