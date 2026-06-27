import 'package:farda/app_const/app_urls.dart';
import 'package:farda/application/authentication/storage/auth_storage.dart';
import 'package:farda/application/refill/model/refill_model.dart';
import 'package:farda/utilities/api_service.dart';
import 'package:flutter/foundation.dart';

/// Backend client for the refill prediction + pharmacy-readiness feature
/// (GTM-541).
///
/// Talks to the Main API (`appBaseUrl`) refill routes through the shared
/// [ApiService] so the bearer token + refresh-on-401 behaviour is reused. The
/// pure parsing/payload logic lives in [RefillModel]/[RefillCalc] so it can be
/// unit-tested without a network call (see `test/refill_*`).
class RefillRepo {
  /// Fetches the user's per-prescription refill predictions. Returns null on
  /// failure so callers can keep their previous state.
  Future<List<RefillModel>?> fetchRefills() async {
    try {
      final response = await ApiService.get(
        endpoint: AppUrls.refills,
        auth: true,
      );
      if (response == null) return null;
      return parseRefills(response);
    } catch (e) {
      debugPrint('fetchRefills error: $e');
      return null;
    }
  }

  /// Parses the `/refills` response body. Pure + static so it is testable
  /// without HTTP.
  static List<RefillModel> parseRefills(Map<String, dynamic> json) {
    final rawList = (json['refills'] as List?) ?? const [];
    return rawList
        .whereType<Map<String, dynamic>>()
        .map(RefillModel.fromJson)
        .toList();
  }

  /// Fetches refill-adherence metrics. Returns null on failure.
  Future<RefillMetrics?> fetchMetrics() async {
    try {
      final response = await ApiService.get(
        endpoint: AppUrls.refillMetrics,
        auth: true,
      );
      if (response == null) return null;
      return RefillMetrics.fromJson(response);
    } catch (e) {
      debugPrint('fetchMetrics error: $e');
      return null;
    }
  }

  /// Logs a single refill-lifecycle event. Fire-and-forget friendly: returns
  /// true on success, false otherwise, and never throws.
  Future<bool> logEvent({
    required RefillEventType eventType,
    String? prescriptionId,
    String? outcome,
    DateTime? refillDueDate,
    DateTime? occurredAt,
    String channel = 'MANUAL',
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final body = RefillCalc.buildEventPayload(
        eventType: eventType,
        prescriptionId: prescriptionId,
        outcome: outcome,
        refillDueDate: refillDueDate,
        occurredAt: occurredAt,
        channel: channel,
        metadata: metadata,
      );
      final response = await ApiService.post(
        endpoint: AppUrls.refillEvents,
        body: body,
        auth: true,
      );
      return response != null;
    } catch (e) {
      debugPrint('logEvent (refill) error: $e');
      return false;
    }
  }

  /// The bearer token, exposed so callers can short-circuit when signed out.
  Future<String?> currentToken() => AuthStorage.getToken();
}
