import 'package:farda/app_const/app_text.dart';
import 'package:farda/components/custom_snackbar.dart';
import 'package:farda/screens/dashboard/dashboard_shell.dart';
import 'package:farda/screens/prescription_info/prescription_provider.dart';
import 'package:farda/theme.dart';
import 'package:flutter/material.dart';

class PrescriptionController {
  final PrescriptionProvider provider;

  const PrescriptionController(this.provider);

  Future<void> handleGallerySelection(BuildContext bottomSheetContext) async {
    Navigator.pop(bottomSheetContext);
    await provider.pickImages();
    if (provider.images.isNotEmpty) {
      await provider.getExtractPrescriptionApi(provider.images);
    }
  }

  Future<void> handleCameraSelection(BuildContext bottomSheetContext) async {
    Navigator.pop(bottomSheetContext);
    await provider.pickImageFromCamera();
    if (provider.images.isNotEmpty) {
      await provider.getExtractPrescriptionApi(provider.images);
    }
  }

  void showImagePickerOptions(BuildContext context, ThemeData theme, FardaColors colors) {
    showModalBottomSheet(
      backgroundColor: colors.baseBlack,
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.white),
              title: const Text(
                'Gallery',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () => handleGallerySelection(ctx),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.white),
              title: const Text(
                'Camera',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () => handleCameraSelection(ctx),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> handleSave(BuildContext context) async {
    final data = await provider.submitPrescriptionApi();
    debugPrint(data.toString());
    
    if (context.mounted) {
      if (data == true) {
        CustomSnackbar.show(
          context,
          message: submitPrescription,
        );
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const ScreenDashboardShell(),
          ),
        );
      } else {
        CustomSnackbar.show(
          context,
          message: failedPrescriptionSubmit,
        );
      }
    }
  }
}
