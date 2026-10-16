import 'consumer_models.dart';
import 'circle_models.dart';

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
  Future<CircleOverview> loadCircle();
  Future<List<CircleInvitation>> loadCircleInvitations();
  Future<CircleInvitation> inviteToCircle(
    String phone,
    CirclePermissions permissions,
  );
  Future<void> acceptCircleInvitation(String id, String inviteCode);
  Future<void> updateCircleMember(String id, CirclePermissions permissions);
  Future<void> removeCircleMember(String id);
  Future<void> cancelCircleInvitation(String id);
  Future<void> declineCircleInvitation(String id);
  Future<List<SharedCircle>> loadSharedCircles();
  Future<void> leaveSharedCircle(String grantId);
  Future<CircleRoutine> loadSharedCircleRoutine(
    String grantId, {
    required DateTime from,
    required DateTime to,
  });
  void dispose();
}
