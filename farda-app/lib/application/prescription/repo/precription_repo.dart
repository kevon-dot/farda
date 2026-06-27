import 'dart:io';

import 'package:farda/app_const/app_urls.dart';
import 'package:farda/application/prescription/model/prescription_model.dart';
import 'package:farda/utilities/api_service.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PrecriptionRepo {
  Future<PrescriptionModel?> getExtractPrescription(List<File> file) async {
    final preferences = await SharedPreferences.getInstance();
    final token = preferences.getString("access") ?? "";

    final response = await ApiService.postMultipart(
      files: file,
      endpoint: AppUrls.getExtractPrescriptionOcr,
      fileFieldName:
          "image", // This must match your backend's expected field name

      headers: {"Authorization": "Bearer $token"},
    );
    debugPrint(response.toString());
    if (response != null) {
      return PrescriptionModel.fromJson(response);
    } else {
      debugPrint("");
      return null;
    }
  }

  Future<int?> submitPrescription(PrescriptionModel prescription) async {
    final preferences = await SharedPreferences.getInstance();
    final token = preferences.getString("access") ?? "";
    final userId = preferences.getString("id") ?? "";

    print(prescription.toSubmit(userId));

    final response = await ApiService.postResponse(
      endpoint: AppUrls.submitPrescription,
      body: prescription.toSubmit(userId),
      headers: {"Authorization": "Bearer $token"},
    );

    debugPrint(response.toString());

    if (response != null) {
      return response.statusCode;
    } else {
      debugPrint(response.toString());
      return null;
    }
  }

  Future<dynamic> getPrescription() async {
    SharedPreferences preferences = await SharedPreferences.getInstance();

    try {
      final response = await ApiService.getList(
        headers: {
          "Authorization": "Bearer ${preferences.getString("access") ?? ""}",
        },
        endpoint: AppUrls.getPrescription,
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
}
