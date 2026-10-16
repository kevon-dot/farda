import 'consumer_models.dart';
import 'consumer_repository.dart';
import 'circle_models.dart';

/// Explicitly selected, in-memory sample data. Never used as a production fallback.
class ConsumerDemoRepository implements ConsumerRepository {
  ConsumerDemoRepository({DateTime Function()? now})
    : clock = now ?? DateTime.now {
    final current = clock();
    _prescriptions.add(
      const ConsumerPrescription(
        id: 'demo-medication',
        name: 'Sample daily medication',
        directions: 'Follow the directions on your prescription label.',
        pharmacy: 'Your sample pharmacy',
        rxNumber: 'DEMO-4821',
        times: ['09:00'],
        labelReviewed: true,
      ),
    );
    for (var offset = -12; offset <= 30; offset++) {
      final date = DateTime(
        current.year,
        current.month,
        current.day + offset,
        9,
      );
      _occurrences.add(
        ConsumerOccurrence(
          id: 'demo-${date.toIso8601String()}',
          prescriptionId: 'demo-medication',
          scheduledFor: date,
          status: offset < 0 && offset % 3 != 0
              ? OccurrenceStatus.taken
              : OccurrenceStatus.unconfirmed,
          recordedAt: offset < 0 && offset % 3 != 0
              ? date.add(const Duration(minutes: 4))
              : null,
          source: 'Sample record',
        ),
      );
    }
    _inventory['demo-medication'] = ConsumerInventory(
      prescriptionId: 'demo-medication',
      quantity: 6,
      dailyUnits: 1,
      countedAt: current,
      revision: 1,
    );
  }
  final DateTime Function() clock;
  final List<ConsumerPrescription> _prescriptions = [];
  final List<ConsumerOccurrence> _occurrences = [];
  final Map<String, ConsumerInventory> _inventory = {};
  ConsumerReminderPreferences _preferences =
      const ConsumerReminderPreferences();
  int _counter = 0;
  @override
  bool get isDemo => true;
  @override
  Future<CircleOverview> loadCircle() async =>
      const CircleOverview(pending: [], members: []);
  @override
  Future<List<CircleInvitation>> loadCircleInvitations() async => const [];
  @override
  Future<CircleInvitation> inviteToCircle(
    String phone,
    CirclePermissions permissions,
  ) async => throw const ConsumerRepositoryException(
    'Circle invitations require a signed-in account.',
  );

  @override
  Future<void> acceptCircleInvitation(String id, String inviteCode) async {}
  @override
  Future<void> updateCircleMember(
    String id,
    CirclePermissions permissions,
  ) async {}
  @override
  Future<void> removeCircleMember(String id) async {}
  @override
  Future<void> cancelCircleInvitation(String id) async {}
  @override
  Future<void> declineCircleInvitation(String id) async {}
  @override
  Future<List<SharedCircle>> loadSharedCircles() async => const [];
  @override
  Future<void> leaveSharedCircle(String grantId) async {}
  @override
  Future<CircleRoutine> loadSharedCircleRoutine(
    String grantId, {
    required DateTime from,
    required DateTime to,
  }) async => CircleRoutine(
    owner: const CirclePerson(id: 'demo', displayName: 'Sample account'),
    permissions: const CirclePermissions(doseStatus: true, reminders: true),
    items: const [],
    fetchedAt: clock(),
    notice: 'Sample only. Not recorded does not mean missed.',
  );
  @override
  Future<ConsumerSnapshot> loadSnapshot({
    required DateTime from,
    required DateTime to,
  }) async => ConsumerSnapshot(
    prescriptions: List.unmodifiable(_prescriptions),
    occurrences: _occurrences
        .where(
          (o) => !o.scheduledFor.isBefore(from) && o.scheduledFor.isBefore(to),
        )
        .toList(),
    inventory: _inventory.values.toList(),
    preferences: _preferences,
    capabilities: const ConsumerCapabilities(
      voiceEnabled: true,
      liveActivityDeliveryEnabled: true,
      inventoryEnabled: true,
      refillsEnabled: true,
    ),
    fetchedAt: clock(),
  );
  @override
  Future<void> savePrescription(ConsumerPrescriptionDraft draft) async {
    if (draft.validationError != null) {
      throw ConsumerRepositoryException(draft.validationError!);
    }
    final id = 'demo-new-${++_counter}';
    _prescriptions.add(
      ConsumerPrescription(
        id: id,
        name: draft.name.trim(),
        directions: draft.directions,
        pharmacy: draft.pharmacy,
        rxNumber: draft.rxNumber,
        labelReviewed: draft.labelReviewed,
        times: draft.remindersEnabled ? List.of(draft.times) : const [],
        timeZone: draft.timeZone,
      ),
    );
    // Demo-only dates use the device clock; production occurrences come from the server.
    for (
      var day = 0;
      draft.remindersEnabled && day < draft.durationDays;
      day++
    ) {
      for (final time in draft.times) {
        final pieces = time.split(':');
        final date = DateTime(
          draft.startDate.year,
          draft.startDate.month,
          draft.startDate.day + day,
          int.parse(pieces[0]),
          int.parse(pieces[1]),
        );
        _occurrences.add(
          ConsumerOccurrence(
            id: '$id-${date.toIso8601String()}',
            prescriptionId: id,
            scheduledFor: date,
            source: 'Sample record',
          ),
        );
      }
    }
  }

  @override
  Future<void> recordOccurrence(ConsumerOccurrenceUpdate update) async {
    final index = _occurrences.indexWhere((o) => o.id == update.id);
    if (index < 0) {
      throw const ConsumerRepositoryException(
        'This sample entry no longer exists.',
      );
    }
    _occurrences[index] = _occurrences[index].copyWith(
      status: update.status,
      recordedAt: update.takenAt,
      note: update.note,
      clearSnooze: update.status != null,
    );
  }

  @override
  Future<void> updateSchedule(
    String prescriptionId,
    ConsumerPrescriptionDraft draft,
  ) async {
    if (draft.validationError != null) {
      throw ConsumerRepositoryException(draft.validationError!);
    }
    final index = _prescriptions.indexWhere((p) => p.id == prescriptionId);
    if (index < 0) {
      throw const ConsumerRepositoryException('This routine no longer exists.');
    }
    final old = _prescriptions[index];
    _prescriptions[index] = ConsumerPrescription(
      id: old.id,
      name: old.name,
      directions: old.directions,
      pharmacy: old.pharmacy,
      rxNumber: old.rxNumber,
      labelReviewed: old.labelReviewed,
      times: List.of(draft.times),
      timeZone: draft.timeZone,
    );
    final effective = clock();
    for (var i = 0; i < _occurrences.length; i++) {
      final occurrence = _occurrences[i];
      if (occurrence.prescriptionId == prescriptionId &&
          occurrence.scheduledFor.isAfter(effective) &&
          occurrence.status == OccurrenceStatus.unconfirmed) {
        _occurrences[i] = occurrence.copyWith(
          status: OccurrenceStatus.cancelled,
          clearSnooze: true,
        );
      }
    }
    for (var offset = 0; offset < draft.durationDays; offset++) {
      for (final time in draft.times) {
        final parts = time.split(':');
        final due = DateTime(
          draft.startDate.year,
          draft.startDate.month,
          draft.startDate.day + offset,
          int.parse(parts[0]),
          int.parse(parts[1]),
        );
        if (!due.isAfter(effective)) continue;
        _occurrences.add(
          ConsumerOccurrence(
            id: 'demo-edit-${++_counter}',
            prescriptionId: prescriptionId,
            scheduledFor: due,
            source: 'Sample record',
          ),
        );
      }
    }
  }

  @override
  Future<void> snoozeOccurrence(String id, Duration duration) async {
    final index = _occurrences.indexWhere((o) => o.id == id);
    if (index < 0 ||
        _occurrences[index].status != OccurrenceStatus.unconfirmed) {
      throw const ConsumerRepositoryException(
        'Only an unconfirmed routine can be snoozed.',
      );
    }
    _occurrences[index] = _occurrences[index].copyWith(
      snoozedUntil: clock().add(duration),
    );
  }

  @override
  Future<void> saveReminderPreferences(
    ConsumerReminderPreferences preferences, {
    bool callConsent = false,
  }) async {
    if (preferences.callsEnabled &&
        !_preferences.callsEnabled &&
        !callConsent) {
      throw const ConsumerRepositoryException(
        'Choose call reminders before enabling them.',
      );
    }
    _preferences = preferences;
  }

  @override
  Future<void> updateInventory(String prescriptionId, int quantity) async {
    if (quantity < 0 || quantity > 100000) {
      throw const ConsumerRepositoryException('Enter a valid count.');
    }
    final old = _inventory[prescriptionId];
    _inventory[prescriptionId] = ConsumerInventory(
      prescriptionId: prescriptionId,
      quantity: quantity,
      countedAt: clock(),
      dailyUnits: old?.dailyUnits,
      stage: old?.stage ?? RefillStage.planning,
      refillId: old?.refillId,
      plannedFor: old?.plannedFor,
      revision: (old?.revision ?? 0) + 1,
      receiptReconciled: old?.receiptReconciled ?? false,
    );
  }

  @override
  Future<void> updateRefill(
    String prescriptionId,
    RefillStage stage, {
    bool startNew = false,
  }) async {
    final old = _inventory[prescriptionId];
    _inventory[prescriptionId] = ConsumerInventory(
      prescriptionId: prescriptionId,
      quantity: old?.quantity,
      countedAt: old?.countedAt,
      dailyUnits: old?.dailyUnits,
      stage: stage,
      refillId: startNew
          ? 'demo-refill-${++_counter}'
          : old?.refillId ?? 'demo-refill-$prescriptionId',
      plannedFor: startNew ? clock() : old?.plannedFor ?? clock(),
      revision: old?.revision ?? 0,
      receiptReconciled: startNew ? false : old?.receiptReconciled ?? false,
    );
  }

  @override
  Future<void> reconcileReceipt(
    String prescriptionId, {
    required int quantity,
    required bool alreadyIncluded,
  }) async {
    final old = _inventory[prescriptionId];
    if (old?.quantity == null ||
        old!.stage != RefillStage.received ||
        quantity < 1) {
      throw const ConsumerRepositoryException(
        'Record receipt and a current count before reconciling this refill.',
      );
    }
    if (old.receiptReconciled) return;
    _inventory[prescriptionId] = ConsumerInventory(
      prescriptionId: prescriptionId,
      quantity: alreadyIncluded ? old.quantity : old.quantity! + quantity,
      countedAt: clock(),
      dailyUnits: old.dailyUnits,
      stage: old.stage,
      refillId: old.refillId,
      plannedFor: old.plannedFor,
      revision: old.revision + 1,
      receiptReconciled: true,
    );
  }

  @override
  Future<bool> signOut(String token) async => true;

  @override
  void dispose() {}
}
