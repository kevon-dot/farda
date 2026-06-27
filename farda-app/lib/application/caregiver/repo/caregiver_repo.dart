import 'package:farda/app_const/app_urls.dart';
import 'package:farda/env.dart';
import 'package:farda/utilities/api_service.dart';
import 'package:farda/utilities/logger_service.dart';
import 'package:http/http.dart' as http;

/// Caregiver data, served DIRECTLY by the Vial API (issue #14/#30,
/// app-calls-both). The Main API's caregiver proxy was removed in PR #83, so
/// every call targets [vialBaseUrl] with the shared better-auth bearer
/// (`auth: true`), exactly like [DeviceRepo].
///
/// Authorization on the backend is SERVER-AUTHORITATIVE: a caregiver may only
/// read a device the owner explicitly granted (see
/// smart-vial-backend/controllers/caregiver.controller.js). The app just passes
/// the bearer; the asserted role is never trusted server-side.
class CaregiverRepo {
  /// Builds the owner→caregiver assignment body. Extracted for unit testing; the
  /// Vial `claimDeviceForCaregiver` controller requires both `device_id` and
  /// `caregiver_id` as strings.
  static Map<String, String> buildAssignCaregiverBody(
    String deviceId,
    String caregiverId,
  ) {
    return {"device_id": deviceId, "caregiver_id": caregiverId};
  }

  /// Owner assigns [caregiverId] as caregiver of [deviceId].
  Future<http.Response?> assignCaregiver(
    String deviceId,
    String caregiverId,
  ) async {
    try {
      return await ApiService.postResponse(
        baseUrl: vialBaseUrl,
        endpoint: VialUrls.caregiverClaimDevice,
        body: buildAssignCaregiverBody(deviceId, caregiverId),
        auth: true,
      );
    } catch (e) {
      Log.e("CaregiverRepo.assignCaregiver error", error: e);
      return null;
    }
  }

  /// Removes the current caregiver's access to [deviceId] (owner only). Real
  /// HTTP DELETE on the Vial backend.
  Future<http.Response?> revokeCaregiverAccess(String deviceId) async {
    try {
      return await ApiService.deleteResponse(
        baseUrl: vialBaseUrl,
        endpoint: VialUrls.deleteCaregiverAccess(deviceId),
        auth: true,
      );
    } catch (e) {
      Log.e("CaregiverRepo.revokeCaregiverAccess error", error: e);
      return null;
    }
  }

  /// Lists the current user's caregiver grants (GTM-517), server-authoritative
  /// + PHI-free. The response has `as_caregiver` (my invites inbox / patients I
  /// look after) and `as_owner` (relationships I created). Optional [status]
  /// (`pending`|`accepted`|`revoked`) and [role] (`caregiver`|`owner`) filters
  /// map straight to the `?status=&role=` query params.
  Future<http.Response?> getGrants({String? status, String? role}) async {
    try {
      final query = <String, String>{};
      if (status != null && status.isNotEmpty) query['status'] = status;
      if (role != null && role.isNotEmpty) query['role'] = role;
      return await ApiService.getList(
        baseUrl: vialBaseUrl,
        endpoint: VialUrls.caregiverGrants,
        auth: true,
        queryParams: query.isEmpty ? null : query,
      );
    } catch (e) {
      Log.e("CaregiverRepo.getGrants error", error: e);
      return null;
    }
  }

  /// Invited caregiver ACCEPTS a pending grant (`pending → accepted`). Only then
  /// does the backend grant read access.
  Future<http.Response?> acceptGrant(String grantId) async {
    try {
      return await ApiService.postResponse(
        baseUrl: vialBaseUrl,
        endpoint: VialUrls.caregiverAcceptGrant(grantId),
        body: const {},
        auth: true,
      );
    } catch (e) {
      Log.e("CaregiverRepo.acceptGrant error", error: e);
      return null;
    }
  }

  /// REVOKES a grant by id (`* → revoked`). Used both by the caregiver to
  /// DECLINE a pending invite and by the owner to cut an accepted caregiver's
  /// access. Authorization (owner or caregiver only) is enforced server-side.
  Future<http.Response?> revokeGrant(String grantId) async {
    try {
      return await ApiService.postResponse(
        baseUrl: vialBaseUrl,
        endpoint: VialUrls.caregiverRevokeGrant(grantId),
        body: const {},
        auth: true,
      );
    } catch (e) {
      Log.e("CaregiverRepo.revokeGrant error", error: e);
      return null;
    }
  }

  /// Lists all devices assigned to the current caregiver.
  Future<http.Response?> getCaregiverDevices() async {
    try {
      return await ApiService.getList(
        baseUrl: vialBaseUrl,
        endpoint: VialUrls.caregiverDevices,
        auth: true,
      );
    } catch (e) {
      Log.e("CaregiverRepo.getCaregiverDevices error", error: e);
      return null;
    }
  }

  /// Summary of a single device the caregiver has access to.
  Future<http.Response?> getDeviceSummary(String deviceId) async {
    try {
      return await ApiService.getList(
        baseUrl: vialBaseUrl,
        endpoint: VialUrls.caregiverDeviceSummary(deviceId),
        auth: true,
      );
    } catch (e) {
      Log.e("CaregiverRepo.getDeviceSummary error", error: e);
      return null;
    }
  }

  /// Looks up a device by id within caregiver scope.
  Future<http.Response?> searchDevice(String deviceId) async {
    try {
      return await ApiService.getList(
        baseUrl: vialBaseUrl,
        endpoint: VialUrls.caregiverSearchDevice,
        auth: true,
        queryParams: {"device_id": deviceId},
      );
    } catch (e) {
      Log.e("CaregiverRepo.searchDevice error", error: e);
      return null;
    }
  }

  /// Filters a device's events by date range (caregiver scope).
  Future<http.Response?> filterEventsByDate(
    String deviceId, {
    required String startTime,
    required String endTime,
  }) async {
    try {
      return await ApiService.getList(
        baseUrl: vialBaseUrl,
        endpoint: VialUrls.caregiverEventsByDate,
        auth: true,
        queryParams: {
          "device_id": deviceId,
          "start_time": startTime,
          "end_time": endTime,
        },
      );
    } catch (e) {
      Log.e("CaregiverRepo.filterEventsByDate error", error: e);
      return null;
    }
  }
}
