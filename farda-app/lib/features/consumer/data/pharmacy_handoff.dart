/// Official pharmacy destinations are supplied by the authenticated directory.
/// A handoff is navigation only, never an order or a pharmacy status.
abstract interface class PharmacyHandoffRepository {
  Future<List<PharmacyDestination>> loadPharmacyDirectory();
  Future<PharmacyHandoff> preparePharmacyHandoff(
    String prescriptionId, {
    required String pharmacyId,
    required String purpose,
  });
  Future<Future<bool> Function()> capturePharmacySession();
}

class PharmacyDestination {
  const PharmacyDestination({
    required this.id,
    required this.name,
    this.aliases = const [],
    required this.actions,
  });
  final String id;
  final String name;
  final List<String> aliases;
  final Map<String, Uri> actions;
  factory PharmacyDestination.fromJson(Map<String, dynamic> json) =>
      PharmacyDestination(
        id: json['id'] as String,
        name: json['name'] as String,
        aliases: (json['aliases'] as List? ?? []).cast<String>(),
        actions: {
          for (final entry in (json['actions'] as Map? ?? {}).entries)
            if (entry.value is Map && entry.value['url'] is String)
              entry.key as String: Uri.parse(entry.value['url'] as String),
        },
      );
  bool matches(String? saved) {
    String normalize(String text) =>
        text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final value = normalize(saved ?? '');
    return value.isNotEmpty &&
        [name, ...aliases].any((name) => normalize(name) == value);
  }
}

class PharmacyHandoff {
  const PharmacyHandoff({
    required this.pharmacyId,
    required this.pharmacyName,
    required this.purpose,
    required this.mode,
    required this.notice,
    this.url,
  });
  final String pharmacyId;
  final String pharmacyName;
  final String purpose;
  final String mode;
  final String notice;
  final Uri? url;
  factory PharmacyHandoff.fromJson(Map<String, dynamic> json) {
    final pharmacy = json['pharmacy'] as Map;
    final action = json['action'] as Map;
    return PharmacyHandoff(
      pharmacyId: pharmacy['id'] as String,
      pharmacyName: pharmacy['name'] as String,
      purpose: json['purpose'] as String,
      mode: action['mode'] as String,
      notice: json['notice'] as String,
      url:
          action['url'] is String
              ? Uri.tryParse(action['url'] as String)
              : null,
    );
  }
  bool hasSafeDestination(PharmacyDestination pharmacy) {
    final target = url;
    return pharmacy.id == pharmacyId &&
        mode == 'external_site' &&
        target != null &&
        target.scheme == 'https' &&
        target.host.isNotEmpty &&
        target.userInfo.isEmpty &&
        !target.hasQuery &&
        !target.hasFragment &&
        pharmacy.actions[purpose] == target;
  }
}
