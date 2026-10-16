class CirclePermissions {
  const CirclePermissions({required this.doseStatus, required this.reminders});
  final bool doseStatus;
  final bool reminders;
  Map<String, Object?> toJson() => {
    'doseStatus': doseStatus,
    'reminders': reminders,
  };
  factory CirclePermissions.fromJson(Map<String, dynamic> json) =>
      CirclePermissions(
        doseStatus: json['doseStatus'] == true,
        reminders: json['reminders'] == true,
      );
}

class CirclePerson {
  const CirclePerson({required this.id, required this.displayName});
  final String id;
  final String displayName;
  factory CirclePerson.fromJson(Map<String, dynamic> json) => CirclePerson(
    id: json['id'] as String? ?? '',
    displayName: json['displayName'] as String? ?? 'Circle member',
  );
}

class CircleInvitation {
  const CircleInvitation({
    required this.id,
    required this.person,
    required this.permissions,
    required this.createdAt,
    required this.expiresAt,
    this.inviteCode,
  });
  final String id;
  final CirclePerson person;
  final CirclePermissions permissions;
  final DateTime createdAt;
  final DateTime expiresAt;
  final String? inviteCode;
  factory CircleInvitation.fromJson(Map<String, dynamic> json) =>
      CircleInvitation(
        id: json['id'] as String,
        person: CirclePerson.fromJson(
          Map<String, dynamic>.from(json['person'] as Map),
        ),
        permissions: CirclePermissions.fromJson(
          Map<String, dynamic>.from(json['permissions'] as Map),
        ),
        createdAt: DateTime.parse(json['createdAt'] as String),
        expiresAt: DateTime.parse(json['expiresAt'] as String),
        inviteCode: json['inviteCode'] as String?,
      );
}

class CircleMember {
  const CircleMember({
    required this.id,
    required this.person,
    required this.permissions,
    required this.acceptedAt,
    required this.updatedAt,
  });
  final String id;
  final CirclePerson person;
  final CirclePermissions permissions;
  final DateTime acceptedAt;
  final DateTime updatedAt;
  factory CircleMember.fromJson(Map<String, dynamic> json) => CircleMember(
    id: json['id'] as String,
    person: CirclePerson.fromJson(
      Map<String, dynamic>.from(json['person'] as Map),
    ),
    permissions: CirclePermissions.fromJson(
      Map<String, dynamic>.from(json['permissions'] as Map),
    ),
    acceptedAt: DateTime.parse(json['acceptedAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
  );
}

class CircleOverview {
  const CircleOverview({required this.pending, required this.members});
  final List<CircleInvitation> pending;
  final List<CircleMember> members;
  factory CircleOverview.fromJson(Map<String, dynamic> json) => CircleOverview(
    pending: (json['pending'] as List? ?? const [])
        .map(
          (v) => CircleInvitation.fromJson(Map<String, dynamic>.from(v as Map)),
        )
        .toList(),
    members: (json['members'] as List? ?? const [])
        .map((v) => CircleMember.fromJson(Map<String, dynamic>.from(v as Map)))
        .toList(),
  );
}

class SharedCircle {
  const SharedCircle({required this.access, required this.owner});
  final CircleMember access;
  final CirclePerson owner;
}

enum CircleRoutineState { taken, skipped, snoozed, notRecorded }

enum CircleEvidence { selfReport, deviceObservation, none }

class CircleRoutineItem {
  const CircleRoutineItem({
    required this.id,
    required this.label,
    this.scheduledFor,
    this.ownerTimeZone,
    this.state,
    this.evidence,
    this.recordedAt,
    this.snoozedUntil,
  });
  final String id;
  final String label;
  final DateTime? scheduledFor;
  final String? ownerTimeZone;
  final CircleRoutineState? state;
  final CircleEvidence? evidence;
  final DateTime? recordedAt;
  final DateTime? snoozedUntil;
  factory CircleRoutineItem.fromJson(Map<String, dynamic> json) =>
      CircleRoutineItem(
        id: json['id'] as String,
        label: json['label'] as String? ?? 'Routine item',
        scheduledFor: DateTime.tryParse(json['scheduledFor'] as String? ?? ''),
        ownerTimeZone: json['ownerTimeZone'] as String?,
        state: json['state'] == null
            ? null
            : CircleRoutineState.values.firstWhere(
                (v) =>
                    v.name ==
                    (json['state'] == 'not_recorded'
                        ? 'notRecorded'
                        : json['state']),
              ),
        evidence: json['evidence'] == null
            ? null
            : CircleEvidence.values.firstWhere(
                (v) =>
                    v.name ==
                    (json['evidence'] == 'self_report'
                        ? 'selfReport'
                        : json['evidence'] == 'device_observation'
                        ? 'deviceObservation'
                        : json['evidence']),
              ),
        recordedAt: DateTime.tryParse(json['recordedAt'] as String? ?? ''),
        snoozedUntil: DateTime.tryParse(json['snoozedUntil'] as String? ?? ''),
      );
}

class CircleRoutine {
  const CircleRoutine({
    required this.owner,
    required this.permissions,
    required this.items,
    required this.fetchedAt,
    required this.notice,
  });
  final CirclePerson owner;
  final CirclePermissions permissions;
  final List<CircleRoutineItem> items;
  final DateTime fetchedAt;
  final String notice;
  factory CircleRoutine.fromJson(Map<String, dynamic> json) => CircleRoutine(
    owner: CirclePerson.fromJson(
      Map<String, dynamic>.from(json['owner'] as Map),
    ),
    permissions: CirclePermissions.fromJson(
      Map<String, dynamic>.from(json['permissions'] as Map),
    ),
    items: (json['items'] as List? ?? const [])
        .map(
          (v) =>
              CircleRoutineItem.fromJson(Map<String, dynamic>.from(v as Map)),
        )
        .toList(),
    fetchedAt: DateTime.parse(json['fetchedAt'] as String),
    notice: json['notice'] as String? ?? 'Not recorded does not mean missed.',
  );
}
