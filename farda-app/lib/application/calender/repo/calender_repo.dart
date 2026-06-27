import 'package:farda/app_const/app_urls.dart';
import 'package:farda/utilities/api_service.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CalenderRepo {
  Future<dynamic> getDoseTime() async {
    SharedPreferences preferences = await SharedPreferences.getInstance();
    try {
      final response = await ApiService.getList(
        headers: {
          "Authorization": "Bearer ${preferences.getString("access") ?? ""}",
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
    SharedPreferences preferences = await SharedPreferences.getInstance();

    try {
      final response = await ApiService.getList(
        headers: {
          "Authorization": "Bearer ${preferences.getString("access") ?? ""}",
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
      debugPrint("getDoseTime error: $e");
      return null;
    }
  }

  Future<dynamic> setMood(String date, String emoji) async {
    SharedPreferences preferences = await SharedPreferences.getInstance();
    final token = preferences.getString("access") ?? "";
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
      print(e);
    }
  }

  Future<int> submitNote(String id, String note) async {
    SharedPreferences preferences = await SharedPreferences.getInstance();
    final token = preferences.getString("access") ?? "";
    try {
      final data = await ApiService.postResponse(
        endpoint: AppUrls.setNotes,
        headers: {"Authorization": "Bearer $token"},
        body: {"dose_time_id": id, "note": "dsfasd"},
      );
      if (data != null) {
      return data.statusCode;
    } else {
      debugPrint(data.toString());
      return data!.statusCode;
    }
    } catch (e) {
      print(e);
      return 100;
      
    }
  }
}
