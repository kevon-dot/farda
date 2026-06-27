import 'package:farda/app_const/app_urls.dart';
import 'package:farda/env.dart';
import 'package:farda/utilities/api_service.dart';
import 'package:farda/utilities/logger_service.dart';
import 'package:http/http.dart' as http;

/// Device / event data, served DIRECTLY by the Vial API (issue #14/#30,
/// app-calls-both). The Main API's proxy for these paths was removed in PR #83,
/// so every call here targets [vialBaseUrl].
///
/// Auth: we pass `auth: true` (NOT a manual `Authorization` header) so
/// [ApiService] attaches the shared better-auth bearer token from secure
/// storage and the refresh-on-401 + token-rotation policy (PR #82/#19) is
/// reused. The Vial backend validates the same session against the shared DB
/// (see smart-vial-backend/middleware/verifyUserToken.js).
class DeviceRepo {
  /// Builds the claim-device request body. Extracted so the payload shape can be
  /// unit-tested without touching the network. The Vial `claimDevice`
  /// controller reads `device_id` from the body.
  static Map<String, String> buildClaimBody(String deviceId) {
    return {"device_id": deviceId};
  }

  /// Claims a provisioned vial for the current user on the Vial API.
  ///
  /// Issue #14/#30: the Main API no longer claims the device on prescription
  /// create (PR #83), so the app now claims it explicitly here. Returns the raw
  /// response so callers can branch on the status (200/201 success, 404 not
  /// provisioned, 409 already claimed).
  Future<http.Response?> claimDevice(String deviceId) async {
    try {
      return await ApiService.postResponse(
        baseUrl: vialBaseUrl,
        endpoint: VialUrls.claimDevice,
        body: buildClaimBody(deviceId),
        auth: true,
      );
    } catch (e) {
      Log.e("DeviceRepo.claimDevice error", error: e);
      return null;
    }
  }

  /// Unclaims (fully detaches) a device the current user owns. Real HTTP DELETE
  /// on the Vial backend.
  Future<http.Response?> unclaimDevice(String deviceId) async {
    try {
      return await ApiService.deleteResponse(
        baseUrl: vialBaseUrl,
        endpoint: VialUrls.unclaimDevice(deviceId),
        auth: true,
      );
    } catch (e) {
      Log.e("DeviceRepo.unclaimDevice error", error: e);
      return null;
    }
  }

  /// Lists all devices owned by the current user.
  Future<http.Response?> getUserDevices() async {
    try {
      return await ApiService.getList(
        baseUrl: vialBaseUrl,
        endpoint: VialUrls.userDevices,
        auth: true,
      );
    } catch (e) {
      Log.e("DeviceRepo.getUserDevices error", error: e);
      return null;
    }
  }

  /// Fetches the most recent events across all of the user's devices.
  Future<http.Response?> getAllDevicesEvents() async {
    try {
      return await ApiService.getList(
        baseUrl: vialBaseUrl,
        endpoint: VialUrls.allDevicesEvents,
        auth: true,
      );
    } catch (e) {
      Log.e("DeviceRepo.getAllDevicesEvents error", error: e);
      return null;
    }
  }

  /// Fetches the most recent events for a single device.
  Future<http.Response?> getDeviceEvents(String deviceId) async {
    try {
      return await ApiService.getList(
        baseUrl: vialBaseUrl,
        endpoint: VialUrls.deviceEvents(deviceId),
        auth: true,
      );
    } catch (e) {
      Log.e("DeviceRepo.getDeviceEvents error", error: e);
      return null;
    }
  }

  /// Searches a device's events within an inclusive time range.
  Future<http.Response?> searchDeviceEvents(
    String deviceId, {
    required String startTime,
    required String endTime,
  }) async {
    try {
      return await ApiService.getList(
        baseUrl: vialBaseUrl,
        endpoint: VialUrls.deviceEventsSearch(deviceId),
        auth: true,
        queryParams: {"start_time": startTime, "end_time": endTime},
      );
    } catch (e) {
      Log.e("DeviceRepo.searchDeviceEvents error", error: e);
      return null;
    }
  }

  /// Deletes all events for a device the current user owns.
  Future<http.Response?> deleteDeviceEvents(String deviceId) async {
    try {
      return await ApiService.deleteResponse(
        baseUrl: vialBaseUrl,
        endpoint: VialUrls.deleteDeviceEvents(deviceId),
        auth: true,
      );
    } catch (e) {
      Log.e("DeviceRepo.deleteDeviceEvents error", error: e);
      return null;
    }
  }
}
