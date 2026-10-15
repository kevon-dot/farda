/// Domain values used by the consumer experience. Unknown is never zero.
enum OccurrenceStatus { unconfirmed, taken, skipped, cancelled }

enum RefillStage { planning, contacted, ready, received }

class ConsumerPrescription {
  const ConsumerPrescription({
    required this.id,
    required this.name,
    this.directions,
    this.pharmacy,
    this.rxNumber,
    this.times = const [],
    this.timeZone = 'America/Los_Angeles',
    this.labelReviewed = false,
  });
  final String id;
  final String name;
  final String? directions;
  final String? pharmacy;
  final String? rxNumber;
  final List<String> times;
  final String timeZone;
  final bool labelReviewed;
}

class ConsumerOccurrence {
  const ConsumerOccurrence({
    required this.id,
    required this.prescriptionId,
    required this.scheduledFor,
    this.status = OccurrenceStatus.unconfirmed,
    this.recordedAt,
    this.note,
    this.snoozedUntil,
    this.source = 'Your record',
    this.revision = 0,
    this.updatedAt,
  });
  final String id;
  final String prescriptionId;
  final DateTime scheduledFor;
  final OccurrenceStatus status;
  final DateTime? recordedAt;
  final String? note;
  final DateTime? snoozedUntil;
  final String source;
  final int revision;
  final DateTime? updatedAt;

  ConsumerOccurrence copyWith({
    OccurrenceStatus? status,
    DateTime? recordedAt,
    String? note,
    DateTime? snoozedUntil,
    bool clearSnooze = false,
  }) => ConsumerOccurrence(
    id: id,
    prescriptionId: prescriptionId,
    scheduledFor: scheduledFor,
    status: status ?? this.status,
    recordedAt: recordedAt ?? this.recordedAt,
    note: note ?? this.note,
    snoozedUntil: clearSnooze ? null : snoozedUntil ?? this.snoozedUntil,
    source: source,
    revision: revision + 1,
    updatedAt: updatedAt,
  );
}

class ConsumerInventory {
  const ConsumerInventory({
    required this.prescriptionId,
    this.quantity,
    this.countedAt,
    this.dailyUnits,
    this.stage = RefillStage.planning,
    this.refillId,
    this.plannedFor,
    this.revision = 0,
    this.receiptReconciled = false,
    this.stale = false,
  });
  final String prescriptionId;
  final int? quantity;
  final DateTime? countedAt;

  /// Only an explicitly supplied, supported fixed daily quantity supports this.
  final double? dailyUnits;
  final RefillStage stage;
  final String? refillId;
  final DateTime? plannedFor;
  final int revision;
  final bool receiptReconciled;
  final bool stale;
  int? get estimatedDays =>
      quantity != null && dailyUnits != null && dailyUnits! > 0
          ? (quantity! / dailyUnits!).floor()
          : null;
}

class ConsumerReminderPreferences {
  const ConsumerReminderPreferences({
    this.callsEnabled = false,
    this.liveActivitiesEnabled = false,
    this.timeZone = 'America/Los_Angeles',
    this.quietHoursStart = '21:00',
    this.quietHoursEnd = '08:00',
  });
  final bool callsEnabled;
  final bool liveActivitiesEnabled;
  final String timeZone;
  final String quietHoursStart;
  final String quietHoursEnd;
  ConsumerReminderPreferences copyWith({
    bool? callsEnabled,
    bool? liveActivitiesEnabled,
    String? timeZone,
    String? quietHoursStart,
    String? quietHoursEnd,
  }) => ConsumerReminderPreferences(
    callsEnabled: callsEnabled ?? this.callsEnabled,
    liveActivitiesEnabled: liveActivitiesEnabled ?? this.liveActivitiesEnabled,
    timeZone: timeZone ?? this.timeZone,
    quietHoursStart: quietHoursStart ?? this.quietHoursStart,
    quietHoursEnd: quietHoursEnd ?? this.quietHoursEnd,
  );
  Map<String, Object> toJson({bool callConsent = false}) => {
    'callsEnabled': callsEnabled,
    'liveActivitiesEnabled': liveActivitiesEnabled,
    'timeZone': timeZone,
    'quietHoursStart': quietHoursStart,
    'quietHoursEnd': quietHoursEnd,
    if (callConsent) 'callConsent': true,
  };
}

class ConsumerCapabilities {
  const ConsumerCapabilities({
    this.voiceEnabled = false,
    this.liveActivityDeliveryEnabled = false,
    this.inventoryEnabled = false,
    this.refillsEnabled = false,
    this.phoneVerified = false,
  });
  final bool voiceEnabled;
  final bool liveActivityDeliveryEnabled;
  final bool inventoryEnabled;
  final bool refillsEnabled;
  final bool phoneVerified;
}

class ConsumerSnapshot {
  const ConsumerSnapshot({
    this.prescriptions = const [],
    this.occurrences = const [],
    this.inventory = const [],
    this.preferences = const ConsumerReminderPreferences(),
    this.capabilities = const ConsumerCapabilities(),
    this.warnings = const [],
    this.callConsentText,
    required this.fetchedAt,
  });
  final List<ConsumerPrescription> prescriptions;
  final List<ConsumerOccurrence> occurrences;
  final List<ConsumerInventory> inventory;
  final ConsumerReminderPreferences preferences;
  final ConsumerCapabilities capabilities;
  final List<String> warnings;
  final String? callConsentText;
  final DateTime fetchedAt;
  ConsumerPrescription? prescription(String id) {
    for (final p in prescriptions) {
      if (p.id == id) return p;
    }
    return null;
  }

  ConsumerInventory? supply(String id) {
    for (final i in inventory) {
      if (i.prescriptionId == id) return i;
    }
    return null;
  }
}

class ConsumerPrescriptionDraft {
  const ConsumerPrescriptionDraft({
    required this.name,
    required this.directions,
    required this.labelReviewed,
    required this.timeZone,
    required this.times,
    required this.startDate,
    this.durationDays = 30,
    this.remindersEnabled = true,
    this.pharmacy,
    this.rxNumber,
    this.clientRequestId = '',
  });
  final String name;
  final String directions;
  final String? pharmacy;
  final String? rxNumber;
  final bool labelReviewed;
  final String timeZone;
  final List<String> times;
  final DateTime startDate;
  final int durationDays;
  final bool remindersEnabled;
  final String clientRequestId;
  String? get validationError {
    if (clientRequestId.length < 8 || clientRequestId.length > 100) {
      return 'This draft needs a new save identifier. Reopen the form and try again.';
    }
    if (name.trim().isEmpty) {
      return 'Enter the medication name from your label.';
    }
    if (directions.trim().isEmpty) {
      return 'Check the label or pharmacy for the directions.';
    }
    if (name.trim().length > 200) {
      return 'Medication name must be 200 characters or fewer.';
    }
    if (directions.trim().length > 2000) {
      return 'Directions exceed the 2,000-character limit. Your full text is preserved; review before saving.';
    }
    if ((pharmacy?.trim().length ?? 0) > 200) {
      return 'Pharmacy name must be 200 characters or fewer.';
    }
    if ((rxNumber?.trim().length ?? 0) > 100) {
      return 'Prescription number must be 100 characters or fewer.';
    }
    if (!labelReviewed) return 'Review the label before saving a routine.';
    if (!remindersEnabled) return null;
    if (times.isEmpty ||
        times.length > 4 ||
        times.any((t) => !RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(t))) {
      return 'Choose one to four daily reminder times.';
    }
    if (times.toSet().length != times.length) {
      return 'Each reminder time must be different.';
    }
    if (durationDays < 1 || durationDays > 365) {
      return 'Use a reminder period from 1 to 365 days.';
    }
    if (timeZone.trim().isEmpty) return 'Choose the timezone for this routine.';
    return null;
  }

  Map<String, Object?> toJson() => {
    'medicationName': name.trim(),
    'clientRequestId': clientRequestId,
    'dosageInstructions': directions.trim(),
    'labelReviewed': labelReviewed,
    'pharmacyOrDoctorName': pharmacy?.trim(),
    'rxNumber': rxNumber?.trim(),
    if (remindersEnabled)
      'schedule': {
        'recurrence': 'daily',
        'times': times,
        'timezone': timeZone,
        'startDate':
            '${startDate.year.toString().padLeft(4, '0')}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}',
        'durationDays': durationDays,
      },
  };
}

class ConsumerOccurrenceUpdate {
  const ConsumerOccurrenceUpdate({
    required this.id,
    this.status,
    this.takenAt,
    this.note,
    this.reason,
    this.expectedRevision,
  });
  final String id;
  final OccurrenceStatus? status;
  final DateTime? takenAt;
  final String? note;
  final String? reason;
  final int? expectedRevision;
  Map<String, Object?> toJson() => {
    if (status != null) 'status': status!.name,
    if (takenAt != null) 'takenAt': takenAt!.toUtc().toIso8601String(),
    if (note != null) 'note': note,
    if (reason != null) 'reason': reason,
    if (expectedRevision != null) 'expectedRevision': expectedRevision,
  };
}

class ConsumerRepositoryException implements Exception {
  const ConsumerRepositoryException(
    this.message, {
    this.sessionExpired = false,
    this.sessionChanged = false,
  });
  final String message;
  final bool sessionExpired;
  final bool sessionChanged;
  @override
  String toString() => message;
}
