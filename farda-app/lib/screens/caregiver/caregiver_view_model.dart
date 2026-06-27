import 'package:farda/application/caregiver/model/caregiver_device_summary_model.dart';
import 'package:farda/application/caregiver/model/caregiver_grant_model.dart';

/// Dose-adherence status surfaced to a caregiver for one patient's device.
///
/// This is an IN-APP status only. Real push delivery of a missed/late-dose
/// alert is GTM-537's flagged Firebase work (see [DoseAlertStatus] TODO in the
/// authorized-patients screen). For now we derive the status client-side from
/// the device's most-recent OPEN (vial-opened ≈ dose-taken) event.
enum DoseAlertStatus {
  /// A vial-open was seen within the recent window — looks on track.
  onTrack,

  /// No open seen within the recent window — a dose may have been missed/late.
  missedOrLate,

  /// Not enough data yet (no events / device never opened).
  unknown,
}

/// Pure (widget-free, plugin-free) helpers for the caregiver/patient screens.
///
/// Everything here is deterministic and side-effect-free so it can be unit
/// tested under `flutter test` without a live backend or platform channels. The
/// provider ([CaregiverProvider]) delegates partitioning + request-body
/// building to these statics.
///
/// SERVER-AUTHORITATIVE INVARIANT: these helpers only ever *partition* the
/// grants the server already chose to return. A `pending` grant authorizes
/// nothing — [authorizedPatients] never includes a pending grant, so the UI
/// cannot accidentally surface a device the caregiver may not read.
class CaregiverViewModel {
  /// Invites awaiting MY acceptance — the caregiver's inbox. Only `pending`
  /// grants where I am the caregiver.
  static List<CaregiverGrantModel> pendingInvitesForMe(CaregiverGrants grants) {
    return grants.asCaregiver.where((g) => g.isPending).toList();
  }

  /// Patients/devices I am authorized to view as a caregiver — ONLY `accepted`
  /// grants. This is the gate the UI uses to decide what to show; a pending or
  /// revoked grant is intentionally excluded (no access).
  static List<CaregiverGrantModel> authorizedPatients(CaregiverGrants grants) {
    return grants.asCaregiver.where((g) => g.isAccepted).toList();
  }

  /// Outstanding invites I (as owner/patient) have extended that haven't been
  /// accepted yet — `pending` grants where I am the owner.
  static List<CaregiverGrantModel> outstandingInvitesFromMe(
    CaregiverGrants grants,
  ) {
    return grants.asOwner.where((g) => g.isPending).toList();
  }

  /// Caregivers who currently have access to my device(s) — `accepted` grants
  /// where I am the owner. These are the relationships I can revoke.
  static List<CaregiverGrantModel> myAcceptedCaregivers(
    CaregiverGrants grants,
  ) {
    return grants.asOwner.where((g) => g.isAccepted).toList();
  }

  /// Body for the owner→caregiver invite (POST /claim-device). Mirrors
  /// [CaregiverRepo.buildAssignCaregiverBody]; both ids are required strings.
  static Map<String, String> buildInviteBody(
    String deviceId,
    String caregiverId,
  ) {
    return {"device_id": deviceId.trim(), "caregiver_id": caregiverId.trim()};
  }

  /// Most recent OPEN (vial-opened) event timestamp from a device summary, or
  /// null if the device has never been opened. Reads `device_timestamp` first
  /// (when the vial reported it) and falls back to `server_timestamp`.
  static DateTime? lastOpenAt(CaregiverDeviceSummary summary) {
    for (final e in summary.recentEvents) {
      final type = e['event_type']?.toString().toUpperCase();
      if (type != 'OPEN') continue;
      final raw = e['device_timestamp'] ?? e['server_timestamp'];
      final ts = raw == null ? null : DateTime.tryParse(raw.toString());
      if (ts != null) return ts;
    }
    return null;
  }

  /// Derives a [DoseAlertStatus] for a device: if the last vial-open is older
  /// than [window] (relative to [now], default 24h) we flag a possible
  /// missed/late dose. No events at all -> [DoseAlertStatus.unknown].
  ///
  /// This is a deliberately simple, server-data-driven heuristic — it never
  /// fabricates access (it only interprets summaries the server returned for an
  /// accepted grant). A schedule-aware version is a follow-up.
  static DoseAlertStatus doseStatus(
    CaregiverDeviceSummary summary, {
    DateTime? now,
    Duration window = const Duration(hours: 24),
  }) {
    final last = lastOpenAt(summary);
    if (last == null) return DoseAlertStatus.unknown;
    final reference = now ?? DateTime.now();
    final elapsed = reference.difference(last);
    return elapsed > window
        ? DoseAlertStatus.missedOrLate
        : DoseAlertStatus.onTrack;
  }

  /// Whether an invite form is ready to submit: both ids non-blank and the
  /// owner is not inviting themselves (the backend rejects that with a 400, but
  /// we catch it client-side for a better UX).
  static bool canSubmitInvite({
    required String deviceId,
    required String caregiverId,
    String? ownerUserId,
  }) {
    final d = deviceId.trim();
    final c = caregiverId.trim();
    if (d.isEmpty || c.isEmpty) return false;
    if (ownerUserId != null && c == ownerUserId.trim()) return false;
    return true;
  }
}
