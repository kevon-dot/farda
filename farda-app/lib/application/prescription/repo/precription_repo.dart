import 'dart:io';

import 'package:farda/app_const/app_urls.dart';
import 'package:farda/application/authentication/storage/auth_storage.dart';
import 'package:farda/application/prescription/model/prescription_model.dart';
import 'package:farda/utilities/api_service.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PrecriptionRepo {
  Future<PrescriptionModel?> getExtractPrescription(List<File> file) async {
    final token = await AuthStorage.getToken() ?? "";

    final response = await ApiService.postMultipart(
      files: file,
      endpoint: AppUrls.getExtractPrescriptionOcr,
      fileFieldName:
          "image", // This must match your backend's expected field name

      headers: {"Authorization": "Bearer $token"},
    );
    if (response != null) {
      return PrescriptionModel.fromJson(response);
    } else {
      return null;
    }
  }

  Future<int?> submitPrescription(PrescriptionModel prescription) async {
    final preferences = await SharedPreferences.getInstance();
    final token = await AuthStorage.getToken() ?? "";
    final userId = preferences.getString("id") ?? "";

    final response = await ApiService.postResponse(
      endpoint: AppUrls.submitPrescription,
      body: prescription.toSubmit(userId),
      headers: {"Authorization": "Bearer $token"},
    );

    if (response != null) {
      return response.statusCode;
    } else {
      return null;
    }
  }

  Future<dynamic> getPrescription() async {
    try {
      final token = await AuthStorage.getToken() ?? "";
      final response = await ApiService.getList(
        headers: {
          "Authorization": "Bearer $token",
        },
        endpoint: AppUrls.getPrescription,
      );

      if (response != null) {
        return response;
      } else {
        debugPrint("Failed to fetch prescription.");
        return null;
      }
    } catch (e) {
      debugPrint("getPrescription error: $e");
      return null;
    }
  }
}
