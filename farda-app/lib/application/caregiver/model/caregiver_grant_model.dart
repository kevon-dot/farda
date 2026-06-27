/// GTM-517 — client model of a caregiver↔patient grant.
///
/// This mirrors the PHI-FREE serialization the Vial backend returns from
/// `GET /api/caregiver/grants` (and the accept/revoke/invite responses): opaque
/// ids, the consent `status`, and consent timestamps. It deliberately carries
/// NO device telemetry or patient PHI — authorization stays server-side, so the
/// app never infers access from this record. To read a device the caregiver
/// must still call the authorized device endpoints, which the backend only
/// serves for an ACCEPTED grant.
class CaregiverGrantModel {
  final String? id;
  final String? deviceId;
  final String? patientUserId;
  final String? caregiverUserId;

  /// One of `pending` | `accepted` | `revoked` (see [CaregiverGrantStatus]).
  final String? status;

  final String? invitedAt;
  final String? invitedBy;
  final String? acceptedAt;
  final String? acceptedBy;
  final String? revokedAt;
  final String? revokedBy;

  const CaregiverGrantModel({
    this.id,
    this.deviceId,
    this.patientUserId,
    this.caregiverUserId,
    this.status,
    this.invitedAt,
    this.invitedBy,
    this.acceptedAt,
    this.acceptedBy,
    this.revokedAt,
    this.revokedBy,
  });

  factory CaregiverGrantModel.fromJson(Map<String, dynamic> json) {
    String? str(dynamic v) => v == null ? null : v.toString();
    return CaregiverGrantModel(
      id: str(json['id']),
      deviceId: str(json['device_id']),
      patientUserId: str(json['patient_user_id']),
      caregiverUserId: str(json['caregiver_user_id']),
      status: str(json['status']),
      invitedAt: str(json['invited_at']),
      invitedBy: str(json['invited_by']),
      acceptedAt: str(json['accepted_at']),
      acceptedBy: str(json['accepted_by']),
      revokedAt: str(json['revoked_at']),
      revokedBy: str(json['revoked_by']),
    );
  }

  bool get isPending => status == CaregiverGrantStatus.pending;
  bool get isAccepted => status == CaregiverGrantStatus.accepted;
  bool get isRevoked => status == CaregiverGrantStatus.revoked;
}

/// Lifecycle states, mirroring the backend `GRANT_STATUS` enum exactly so the
/// app and server agree on the strings.
class CaregiverGrantStatus {
  static const String pending = 'pending';
  static const String accepted = 'accepted';
  static const String revoked = 'revoked';
}

/// The two buckets returned by `GET /api/caregiver/grants`: relationships where
/// the session user is the caregiver, and those where they are the owner/patient.
class CaregiverGrants {
  /// Grants where I am the caregiver (invites inbox + patients I look after).
  final List<CaregiverGrantModel> asCaregiver;

  /// Grants where I am the owner/patient (caregivers I invited; revocable).
  final List<CaregiverGrantModel> asOwner;

  const CaregiverGrants({
    this.asCaregiver = const [],
    this.asOwner = const [],
  });

  factory CaregiverGrants.fromJson(Map<String, dynamic> json) {
    List<CaregiverGrantModel> parse(dynamic raw) {
      if (raw is! List) return const [];
      return raw
          .whereType<Map<String, dynamic>>()
          .map(CaregiverGrantModel.fromJson)
          .toList();
    }

    return CaregiverGrants(
      asCaregiver: parse(json['as_caregiver']),
      asOwner: parse(json['as_owner']),
    );
  }

  bool get isEmpty => asCaregiver.isEmpty && asOwner.isEmpty;
}
