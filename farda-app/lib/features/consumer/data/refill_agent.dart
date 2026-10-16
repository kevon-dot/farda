/// Provider-backed requests are separate from the user's refill plan and count.
abstract interface class RefillAgentRepository {
  Future<RefillAgentState> loadRefillAgent(String prescriptionId);
  Future<RefillAgentState> submitRefillAgent(
    String prescriptionId, {
    required String reviewToken,
    required String idempotencyKey,
  });
  Future<RefillAgentState> refreshRefillAgent(String prescriptionId);
}

class RefillAgentState {
  const RefillAgentState({
    required this.prescriptionId,
    required this.configured,
    required this.canSubmit,
    this.provider = 'Photon',
    this.environment,
    this.blockedReason,
    this.review,
    this.latestRequest,
  });
  final String prescriptionId;
  final bool configured;
  final bool canSubmit;
  final String provider;
  final String? environment;
  final String? blockedReason;
  final RefillAgentReview? review;
  final RefillProviderRequest? latestRequest;

  factory RefillAgentState.fromJson(Map<String, dynamic> json) {
    final provider = json['provider'] as Map? ?? const {};
    return RefillAgentState(
      prescriptionId: json['prescriptionId'] as String,
      configured: provider['configured'] == true,
      provider: provider['name'] as String? ?? 'Photon',
      environment: provider['environment'] as String?,
      canSubmit: json['canSubmit'] == true,
      blockedReason: json['blockedReason'] as String?,
      review:
          json['review'] is Map
              ? RefillAgentReview.fromJson(
                Map<String, dynamic>.from(json['review'] as Map),
              )
              : null,
      latestRequest:
          json['latestRequest'] is Map
              ? RefillProviderRequest.fromJson(
                Map<String, dynamic>.from(json['latestRequest'] as Map),
              )
              : null,
    );
  }
}

class RefillAgentReview {
  const RefillAgentReview({
    required this.token,
    required this.expiresAt,
    required this.medicationName,
    required this.pharmacyName,
    required this.address,
    required this.consentText,
    this.instructions,
    this.fillsRemaining,
  });
  final String token;
  final DateTime expiresAt;
  final String medicationName;
  final String? instructions;
  final String pharmacyName;
  final String address;
  final String consentText;
  final int? fillsRemaining;

  factory RefillAgentReview.fromJson(Map<String, dynamic> json) {
    final address = json['deliveryAddress'] as Map? ?? const {};
    return RefillAgentReview(
      token: json['token'] as String,
      expiresAt: DateTime.parse(json['expiresAt'] as String),
      medicationName: json['medicationName'] as String,
      pharmacyName: json['pharmacyName'] as String,
      instructions: json['instructions'] as String?,
      address: ['street1', 'street2', 'city', 'state', 'postalCode', 'country']
          .map((key) => address[key] as String? ?? '')
          .where((part) => part.isNotEmpty)
          .join(', '),
      consentText: json['consentText'] as String,
      fillsRemaining: (json['fillsRemaining'] as num?)?.toInt(),
    );
  }
}

class RefillProviderRequest {
  const RefillProviderRequest({
    required this.id,
    required this.status,
    required this.statusLabel,
    required this.providerConfirmed,
    required this.canRefresh,
    required this.updatedAt,
    this.lastCheckedAt,
  });
  final String id;
  final String status;
  final String statusLabel;
  final bool providerConfirmed;
  final bool canRefresh;
  final DateTime updatedAt;
  final DateTime? lastCheckedAt;
  bool get uncertain => status == 'unknown' || status == 'submitting';
  factory RefillProviderRequest.fromJson(Map<String, dynamic> json) =>
      RefillProviderRequest(
        id: json['id'] as String,
        status: json['status'] as String,
        statusLabel: json['statusLabel'] as String,
        providerConfirmed: json['providerConfirmed'] == true,
        canRefresh: json['canRefresh'] == true,
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        lastCheckedAt: DateTime.tryParse('${json['lastCheckedAt'] ?? ''}'),
      );
}

/// Opt-in helper: classifies a question; it cannot send or change treatment.
abstract interface class RefillQuestionRepository {
  Future<RefillAgentAnswer> askRefillQuestion(
    String prescriptionId,
    String question,
  );
}

class RefillAgentAnswer {
  const RefillAgentAnswer({
    required this.title,
    required this.message,
    required this.action,
    required this.source,
  });
  final String title;
  final String message;
  final String action;
  final String source;
  factory RefillAgentAnswer.fromJson(Map<String, dynamic> json) =>
      RefillAgentAnswer(
        title: json['title'] as String,
        message: json['message'] as String,
        action: json['action'] as String,
        source: json['source'] as String,
      );
}
