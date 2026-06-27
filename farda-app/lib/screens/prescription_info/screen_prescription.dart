import 'package:farda/components/_components.dart';
import 'package:farda/routes/routes.dart';
import 'package:farda/screens/prescription_info/prescription_provider.dart';
import 'package:farda/screens/prescription_info/prescription_controller.dart';
import 'package:farda/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

class ScreenPrescription extends StatelessWidget {
  const ScreenPrescription({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = PrescriptionController(
      context.read<PrescriptionProvider>(),
    );
    final theme = Theme.of(context);
    final colors = theme.extension<FardaColors>()!;
    final spacing = theme.extension<Spacing>()!;
    final prescriptionProvider = context.watch<PrescriptionProvider>();
    return ExtendedScaffold(
      appBar: CustomAppBar(
        titleType: AppBarTitleType.text,
        titleText: "Prescription Info",
        isEndIcon: false,
      ),
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: spacing.horizontalDefault,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  28.verticalSpace,
                  TextMedium(
                    text:
                        "Enter the prescription number and store number from your label.",
                  ),
                  22.verticalSpace,
                  TextField(
                    controller:
                        prescriptionProvider.prescriptionNumberController,
                    decoration: InputDecoration(
                      hintText: "7-digit prescription number",
                    ),
                  ),
                  12.verticalSpace,
                  TextField(
                    controller: prescriptionProvider.storeNumberController,
                    decoration: InputDecoration(
                      hintText: "4-digit store number",
                    ),
                  ),
                  12.verticalSpace,
                  TextField(
                    controller: prescriptionProvider.pillQtyController,
                    decoration: InputDecoration(
                      hintText: "Pill count quantity",
                    ),
                  ),
                  12.verticalSpace,
                  TextField(
                    decoration: InputDecoration(
                      hintText: "Date of Birth",
                      suffixIcon: Icon(
                        Icons.calendar_month,
                        color: colors.slate[500],
                      ),
                    ),
                  ),
                  24.verticalSpace,
                  if (prescriptionProvider.images.isEmpty &&
                      prescriptionProvider
                              .prescriptionModel
                              .pharmacyOrDoctorName ==
                          null) ...[
                    Text(
                      "Scan Prescription",
                      style: theme.textTheme.titleLarge?.merge(
                        TextStyle(fontWeight: FontWeight.w600, fontSize: 16.sp),
                      ),
                    ),
                    12.verticalSpace,
                    Container(
                      padding: EdgeInsets.all(16.r),
                      decoration: BoxDecoration(
                        border: Border.all(color: colors.slate.shade200),
                        borderRadius: BorderRadius.circular(10.r),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            padding: EdgeInsets.all(16.r),
                            decoration: BoxDecoration(
                              color: theme.primaryColor.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons
                                  .document_scanner_outlined, // thinner outline version
                              size: 40.r,
                              color: theme.primaryColor,
                            ),
                          ),
                          16.verticalSpace,
                          Text(
                            "No prescription scanned yet",
                            style: theme.textTheme.titleMedium,
                          ),
                          8.verticalSpace,
                          Text(
                            "Scan your prescription label to auto-fill the details.",
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.slate.shade600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          16.verticalSpace,
                          ButtonSecondary(
                            prefixIcon: Icon(
                              Icons.camera_alt_outlined,
                              color: theme.primaryColor,
                            ),
                            text: "Scan Prescription",
                            onClick:
                                () => controller.showImagePickerOptions(
                                  context,
                                  theme,
                                  colors,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    PrescriptionView(
                      drName: (prescriptionProvider.prescriptionModel.pharmacyOrDoctorName == null || prescriptionProvider.prescriptionModel.pharmacyOrDoctorName == 'none') 
                          ? "Doctor Name" 
                          : prescriptionProvider.prescriptionModel.pharmacyOrDoctorName!,
                      address: (prescriptionProvider.prescriptionModel.address == null || prescriptionProvider.prescriptionModel.address == 'none') 
                          ? "Address not found" 
                          : prescriptionProvider.prescriptionModel.address!,
                      patientName: "Tom Cruse",
                      rxNumber: (prescriptionProvider.prescriptionModel.rxNumber == null || prescriptionProvider.prescriptionModel.rxNumber == 'none') 
                          ? "N/A" 
                          : prescriptionProvider.prescriptionModel.rxNumber!,
                      storeNumber: (prescriptionProvider.prescriptionModel.storeNumber == null || prescriptionProvider.prescriptionModel.storeNumber == 'none') 
                          ? "N/A" 
                          : prescriptionProvider.prescriptionModel.storeNumber!,
                      title: (prescriptionProvider.prescriptionModel.medicinesNames?.isNotEmpty == true)
                          ? (prescriptionProvider.prescriptionModel.medicinesNames!.first.medicineName == 'none' 
                              ? "Medicine Name" 
                              : prescriptionProvider.prescriptionModel.medicinesNames!.first.medicineName ?? "Medicine Name")
                          : "No Medicine",
                      description: (prescriptionProvider.prescriptionModel.medicinesNames?.isNotEmpty == true)
                          ? (prescriptionProvider.prescriptionModel.medicinesNames!.first.instructions == 'none' 
                              ? "No Instructions" 
                              : prescriptionProvider.prescriptionModel.medicinesNames!.first.instructions ?? "No Instructions")
                          : "No Instructions",
                      quantity: (prescriptionProvider.prescriptionModel.medicinesNames?.isNotEmpty == true)
                          ? (prescriptionProvider.prescriptionModel.medicinesNames!.first.qty?.toString() == 'none' 
                              ? "0" 
                              : prescriptionProvider.prescriptionModel.medicinesNames!.first.qty?.toString() ?? "0")
                          : "0",
                      notification: (prescriptionProvider.prescriptionModel.medicinesNames?.isNotEmpty == true)
                          ? (prescriptionProvider.prescriptionModel.medicinesNames!.first.refillsInfo == 'none' 
                              ? "No Info" 
                              : prescriptionProvider.prescriptionModel.medicinesNames!.first.refillsInfo ?? "No Info")
                          : "No Info",
                      sideEffects: (prescriptionProvider.prescriptionModel.medicinesNames?.isNotEmpty == true)
                          ? (prescriptionProvider.prescriptionModel.medicinesNames!.first.sideEffects == 'none' 
                              ? "None" 
                              : prescriptionProvider.prescriptionModel.medicinesNames!.first.sideEffects ?? "None")
                          : "None",
                    ),
                  ],
                  24.verticalSpace,
                  Text(
                    "Connected Vial",
                    style: theme.textTheme.titleLarge?.merge(
                      TextStyle(fontWeight: FontWeight.w600, fontSize: 16.sp),
                    ),
                  ),
                  12.verticalSpace,
                  Container(
                    padding: EdgeInsets.all(16.r),
                    decoration: BoxDecoration(
                      border: Border.all(color: colors.slate.shade200),
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Image.asset(
                          "assets/images/vial_bottle.png",
                          height: 60.h,
                        ),
                        16.verticalSpace,
                        Text(
                          "No vial connected yet",
                          style: theme.textTheme.titleMedium,
                        ),
                        8.verticalSpace,
                        Text(
                          "Pair a smart vial to track your medication.",
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.slate.shade600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        16.verticalSpace,
                        ButtonSecondary(
                          prefixIcon: Icon(
                            Icons.bluetooth_connected,
                            color: theme.primaryColor,
                          ),
                          text: "Setup Vial",
                          onClick: () {
                            context.push(CustomRoutePaths.screenConnectOnBoard);
                          },
                        ),
                      ],
                    ),
                  ),
                  36.verticalSpace,
                  ButtonPrimary(
                    text: "Save",
                    onClick: prescriptionProvider.isSaving ? () {} : () => controller.handleSave(context),
                  ),
                  12.verticalSpace,
                ],
              ),
            ),
            // Submitting Overlay
            if (prescriptionProvider.isSaving)
              Container(
                color: Colors.white.withOpacity(0.5),
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              ),
            // Loading Overlay (Scanning)
            if (prescriptionProvider.isLoading)
              Container(
                color: Colors.white.withOpacity(0.9),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: EdgeInsets.all(24.r),
                        decoration: BoxDecoration(
                          color: theme.primaryColor.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              width: 80.r,
                              height: 80.r,
                              child: CircularProgressIndicator(
                                color: theme.primaryColor,
                                strokeWidth: 3,
                              ),
                            ),
                            Icon(
                              Icons.document_scanner,
                              color: theme.primaryColor,
                              size: 40.r,
                            ),
                          ],
                        ),
                      ),
                      24.verticalSpace,
                      Text(
                        "Scanning Prescription",
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      8.verticalSpace,
                      Text(
                        "Extracting details from the label...",
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.slate.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
