import 'dart:convert';
import 'dart:io';

import 'package:farda/application/prescription/model/prescription_list_model.dart';
import 'package:farda/application/prescription/model/prescription_model.dart';
import 'package:farda/application/prescription/repo/precription_repo.dart';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class PrescriptionProvider extends ChangeNotifier {
  PrescriptionModel prescriptionModel = PrescriptionModel();
  List<PrescriptionModelList> prescriptionModelList = [];
  bool isLoading = false;
  bool isSaving = false;

  TextEditingController prescriptionNumberController = TextEditingController();
  TextEditingController storeNumberController = TextEditingController();
  TextEditingController pillQtyController = TextEditingController();

  List<File> images = [];

  final ImagePicker _picker = ImagePicker();

  /// Pick image from gallery or camera
 Future<void> pickImages() async {
    try {
      final pickedFiles = await _picker.pickMultiImage(); // No source parameter needed here
      if (pickedFiles.isNotEmpty) {
        // Convert picked files to File objects and add to the images list
        images = pickedFiles.map((pickedFile) => File(pickedFile.path)).toList();
        notifyListeners(); // Update UI with selected images
      }
    } catch (e) {
      debugPrint("Image pick error: $e");
    }
  }

  /// Pick single image from camera
  Future<void> pickImageFromCamera() async {
    try {
      final pickedFile = await _picker.pickImage(source: ImageSource.camera);
      if (pickedFile != null) {
        images = [File(pickedFile.path)];
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Camera pick error: $e");
    }
  }

  /// API call to extract prescription from image
Future<void> getExtractPrescriptionApi(List<File> files) async {
  if (files.isEmpty) return;

  try {
    isLoading = true;
    notifyListeners();

    // Make the API call
    final data = await PrecriptionRepo().getExtractPrescription(files);
    if (data != null) {
      prescriptionModel = data;
      
      // Safely assign text fields, avoiding errors if fields are null or "none"
      prescriptionNumberController.text =
          (prescriptionModel.pharmacyOrDoctorName != null && prescriptionModel.pharmacyOrDoctorName != 'none')
              ?  prescriptionModel.rxNumber ?? ''
              : ''; // using rxNumber for prescription Number ideally instead of pharmacyOrDoctorName, but keeping safe logic
              
      storeNumberController.text = 
          (prescriptionModel.storeNumber != null && prescriptionModel.storeNumber != 'none') 
              ? prescriptionModel.storeNumber.toString() 
              : '';

      if (prescriptionModel.medicinesNames != null && prescriptionModel.medicinesNames!.isNotEmpty) {
        pillQtyController.text = 
            prescriptionModel.medicinesNames!.first.qty?.toString() ?? '';
      } else {
        pillQtyController.text = '';
      }
      
      notifyListeners();
    } else {
      // Clear images to revert to the scan UI if API fails completely
      images.clear();
      notifyListeners();
    }
  } catch (e,stack) {
    debugPrint("getExtractPrescription error: $stack");
    // Clear images to revert to the scan UI if an exception occurs
    images.clear();
  } finally {
    isLoading = false;
    notifyListeners();
  }
}

  //
  Future<bool> submitPrescriptionApi() async {
  try {
    isSaving = true;
    notifyListeners();
    final int? response = await PrecriptionRepo().submitPrescription(prescriptionModel);
    if (response == 201 || response == 200) {
      return true;
    }else{
      return false;
    }

  } catch (e) {
    debugPrint("submitPrescriptionApi error: $e");
    return false;
  } finally {
    isSaving = false;
    notifyListeners();
  }
}


  //get prescription data 
Future<void> getMyPrescriptionApi() async {
  try {
    // Fetch prescription data from the repository
    final data = await PrecriptionRepo().getPrescription();
    
    // Check if the response is valid and has status code 200
    if (data != null && data.statusCode == 200) {
      final List<dynamic> dataList = jsonDecode(data.body);

      // Only process data if it's not empty
      if (dataList.isNotEmpty) {
        // Map the data to PrescriptionModel objects
        prescriptionModelList = dataList
            .map((item) => PrescriptionModelList.fromJson(item))
            .toList();
        notifyListeners(); // Notify listeners if the list has changed
        debugPrint(prescriptionModelList.first.medicines?.first.qty.toString());  // Log the list for debugging
      }
    } else {
      // Handle non-200 status codes (if necessary)
      debugPrint("Failed to fetch data: ${data?.statusCode}");
    }
    
  } catch (e) {
    // Handle any error that occurs during the API call or data processing
    debugPrint("Error fetching prescription data: $e");
  }
}
}
