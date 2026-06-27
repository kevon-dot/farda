import 'package:farda/app_const/app_urls.dart';
import 'package:farda/application/authentication/storage/auth_storage.dart';
import 'package:farda/utilities/api_service.dart';
import 'package:flutter/material.dart';

class CalenderRepo {
  Future<dynamic> getDoseTime() async {
    try {
      final token = await AuthStorage.getToken() ?? "";
      final response = await ApiService.getList(
        headers: {
          "Authorization": "Bearer $token",
        },
        endpoint: AppUrls.getDoseTime,
      );

      if (response != null) {
        return response;
      } else {
        debugPrint("Failed to fetch dose time.");
        return null;
      }
    } catch (e) {
      debugPrint("getDoseTime error: $e");
      return null;
    }
  }

  Future<dynamic> getMood() async {
    try {
      final token = await AuthStorage.getToken() ?? "";
      final response = await ApiService.getList(
        headers: {
          "Authorization": "Bearer $token",
        },
        endpoint: AppUrls.getMode,
      );

      if (response != null) {
        return response;
      } else {
        debugPrint("Failed to fetch mood.");
        return null;
      }
    } catch (e) {
      debugPrint("getMood error: $e");
      return null;
    }
  }

  Future<dynamic> setMood(String date, String emoji) async {
    final token = await AuthStorage.getToken() ?? "";
    try {
      final data = await ApiService.post(
        endpoint: AppUrls.setMood,
        headers: {"Authorization": "Bearer $token"},
        body: {"date": date, "emoji": emoji},
      );
      if (data != null) {
        return data;
      }
    } catch (e) {
      debugPrint("setMood error: $e");
    }
  }

  /// Builds the request body for submitting a note. Extracted so the payload
  /// shape can be unit-tested without touching platform channels.
  static Map<String, String> buildNotePayload(String id, String note) {
    return {"dose_time_id": id, "note": note};
  }

  Future<int> submitNote(String id, String note) async {
    final token = await AuthStorage.getToken() ?? "";
    try {
      final data = await ApiService.postResponse(
        endpoint: AppUrls.setNotes,
        headers: {"Authorization": "Bearer $token"},
        body: buildNotePayload(id, note),
      );
      if (data != null) {
      return data.statusCode;
    } else {
      return data!.statusCode;
    }
    } catch (e) {
      debugPrint("submitNote error: $e");
      return 100;

    }
  }
}
