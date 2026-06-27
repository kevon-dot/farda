import 'dart:convert';

import 'package:farda/application/caregiver/model/caregiver_device_summary_model.dart';
import 'package:farda/application/caregiver/model/caregiver_grant_model.dart';
import 'package:farda/application/caregiver/repo/caregiver_repo.dart';
import 'package:farda/screens/caregiver/caregiver_view_model.dart';
import 'package:farda/utilities/logger_service.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// State for the caregiver/patient experience (GTM-517).
///
/// Holds the session user's grants (both sides) plus the device summaries the
/// caregiver is authorized to read. ALL reads go through [CaregiverRepo] →
/// the Vial backend's server-authoritative endpoints; the provider NEVER
/// assumes access from local state. A `pending` grant shows nothing readable:
/// authorized device summaries are only fetched for ACCEPTED caregiver grants.
class CaregiverProvider extends ChangeNotifier {
  CaregiverProvider({CaregiverRepo? repo}) : _repo = repo ?? CaregiverRepo();

  final CaregiverRepo _repo;

  CaregiverGrants _grants = const CaregiverGrants();
  CaregiverGrants get grants => _grants;

  bool _loading = false;
  bool get isLoading => _loading;

  String? _error;
  String? get error => _error;

  /// Device summaries keyed by device id — populated only for ACCEPTED
  /// caregiver grants (see [loadAuthorizedSummaries]).
  final Map<String, CaregiverDeviceSummary> _summaries = {};
  Map<String, CaregiverDeviceSummary> get summaries =>
      Map.unmodifiable(_summaries);

  // --- Partitioned views (delegated to the pure view-model) -----------------

  List<CaregiverGrantModel> get pendingInvites =>
      CaregiverViewModel.pendingInvitesForMe(_grants);

  List<CaregiverGrantModel> get authorizedPatients =>
      CaregiverViewModel.authorizedPatients(_grants);

  List<CaregiverGrantModel> get outstandingInvites =>
      CaregiverViewModel.outstandingInvitesFromMe(_grants);

  List<CaregiverGrantModel> get myCaregivers =>
      CaregiverViewModel.myAcceptedCaregivers(_grants);

  /// In-app missed/late-dose status for a device the caregiver is authorized
  /// for. TODO(GTM-537): also deliver this as a push alert via Firebase once the
  /// caregiver push channel ships — for now it is surfaced in-app only.
  DoseAlertStatus doseStatusFor(String deviceId) {
    final summary = _summaries[deviceId];
    if (summary == null) return DoseAlertStatus.unknown;
    return CaregiverViewModel.doseStatus(summary);
  }

  // --- Network actions ------------------------------------------------------

  /// Loads both grant buckets for the session user. Safe to call post-auth.
  Future<void> loadGrants() async {
    _setLoading(true);
    _error = null;
    try {
      final res = await _repo.getGrants();
      final parsed = _parseGrants(res);
      if (parsed != null) {
        _grants = parsed;
      } else {
        _error = 'Could not load caregiver relationships';
      }
    } catch (e) {
      Log.e('CaregiverProvider.loadGrants error', error: e);
      _error = 'Could not load caregiver relationships';
    } finally {
      _setLoading(false);
    }
  }

  /// Fetches device summaries for every ACCEPTED caregiver grant. Pending grants
  /// are deliberately skipped — they authorize nothing, and the backend would
  /// 403 the read anyway. Failures per-device are tolerated (the patient still
  /// shows, just without a summary).
  Future<void> loadAuthorizedSummaries() async {
    final authorized = authorizedPatients;
    for (final grant in authorized) {
      final deviceId = grant.deviceId;
      if (deviceId == null || deviceId.isEmpty) continue;
      try {
        final res = await _repo.getDeviceSummary(deviceId);
        final summary = _parseSummary(res);
        if (summary != null) {
          _summaries[deviceId] = summary;
        }
      } catch (e) {
        Log.e('CaregiverProvider.loadAuthorizedSummaries error', error: e);
      }
    }
    notifyListeners();
  }

  /// Accepts a pending invite (caregiver side), then refreshes grants +
  /// summaries so the newly authorized patient appears. Returns true on success.
  Future<bool> acceptInvite(String grantId) async {
    final res = await _repo.acceptGrant(grantId);
    final ok = _isOk(res);
    if (ok) {
      await loadGrants();
      await loadAuthorizedSummaries();
    }
    return ok;
  }

  /// Declines a pending invite (caregiver side) — a revoke from `pending`.
  Future<bool> declineInvite(String grantId) => _revokeAndRefresh(grantId);

  /// Revokes an accepted/pending grant (owner side) to cut/withdraw access.
  Future<bool> revokeGrant(String grantId) => _revokeAndRefresh(grantId);

  /// Owner invites [caregiverId] to [deviceId] (creates a pending grant). The
  /// caregiver still has no access until they accept.
  Future<bool> inviteCaregiver(String deviceId, String caregiverId) async {
    final res = await _repo.assignCaregiver(deviceId, caregiverId);
    final ok = _isOk(res);
    if (ok) {
      await loadGrants();
    }
    return ok;
  }

  Future<bool> _revokeAndRefresh(String grantId) async {
    final res = await _repo.revokeGrant(grantId);
    final ok = _isOk(res);
    if (ok) {
      await loadGrants();
      await loadAuthorizedSummaries();
    }
    return ok;
  }

  // --- Parsing helpers (extracted so they're easy to reason about) ----------

  /// Parses a grants response, or null on a non-2xx / unparseable body.
  static CaregiverGrants? _parseGrants(http.Response? res) {
    if (!_isOk(res)) return null;
    try {
      final decoded = jsonDecode(res!.body);
      if (decoded is Map<String, dynamic>) {
        return CaregiverGrants.fromJson(decoded);
      }
    } catch (_) {}
    return null;
  }

  static CaregiverDeviceSummary? _parseSummary(http.Response? res) {
    if (!_isOk(res)) return null;
    try {
      final decoded = jsonDecode(res!.body);
      if (decoded is Map<String, dynamic>) {
        return CaregiverDeviceSummary.fromJson(decoded);
      }
    } catch (_) {}
    return null;
  }

  static bool _isOk(http.Response? res) =>
      res != null && res.statusCode >= 200 && res.statusCode < 300;

  void _setLoading(bool value) {
    _loading = value;
    notifyListeners();
  }
}
