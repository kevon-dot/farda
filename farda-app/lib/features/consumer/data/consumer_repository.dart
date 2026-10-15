import 'consumer_models.dart';

abstract interface class ConsumerRepository {
  bool get isDemo;
  Future<ConsumerSnapshot> loadSnapshot({
    required DateTime from,
    required DateTime to,
  });
  Future<void> savePrescription(ConsumerPrescriptionDraft draft);
  Future<void> updateSchedule(
    String prescriptionId,
    ConsumerPrescriptionDraft draft,
  );
  Future<void> recordOccurrence(ConsumerOccurrenceUpdate update);
  Future<void> snoozeOccurrence(String id, Duration duration);
  Future<void> saveReminderPreferences(
    ConsumerReminderPreferences preferences, {
    bool callConsent = false,
  });
  Future<void> updateInventory(String prescriptionId, int quantity);
  Future<void> updateRefill(
    String prescriptionId,
    RefillStage stage, {
    bool startNew = false,
  });
  Future<void> reconcileReceipt(
    String prescriptionId, {
    required int quantity,
    required bool alreadyIncluded,
  });
  Future<bool> signOut(String token);
  void dispose();
}
