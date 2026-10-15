import 'dart:io';

import 'package:farda/app_const/app_urls.dart';
import 'package:farda/application/authentication/storage/auth_storage.dart';
import 'package:farda/application/prescription/model/prescription_model.dart';
import 'package:farda/utilities/api_service.dart';

class PrecriptionRepo {
  Future<PrescriptionModel?> getExtractPrescription(List<File> files) async {
    final response = await ApiService.postMultipart(
      files: files,
      endpoint: AppUrls.getExtractPrescriptionOcr,
      fileFieldName: 'image',
      auth: true,
    );
    return response == null ? null : PrescriptionModel.fromJson(response);
  }

  Future<int?> submitPrescription(PrescriptionModel prescription) async {
    final session = await AuthStorage.readSession();
    if (session == null) return null;
    final response = await ApiService.postResponse(
      endpoint: AppUrls.submitPrescription,
      body: prescription.toSubmit(session.userId),
      auth: true,
    );
    return response?.statusCode;
  }

  Future<dynamic> getPrescription() =>
      ApiService.getList(endpoint: AppUrls.getPrescription, auth: true);
}
