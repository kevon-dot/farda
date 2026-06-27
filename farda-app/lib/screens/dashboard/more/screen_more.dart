import 'package:farda/components/_components.dart';
import 'package:farda/screens/login/login_provider.dart';
import 'package:farda/screens/prescription_info/prescription_provider.dart';
import 'package:farda/theme.dart';
import 'package:farda/routes/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/svg.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

class ScreenMore extends StatelessWidget {
  const ScreenMore({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FardaColors>()!;
    final spacing = theme.extension<Spacing>()!;
    final prescriptionProvider = context.watch<PrescriptionProvider>();
    final loginProvider = context.watch<LoginProvider>();
    final patientName =
        loginProvider.name.isNotEmpty ? loginProvider.name : "Patient";
    return Scaffold(
      // appBar: CustomAppBar(titleType: AppBarTitleType.text, titleText: ""),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: spacing.horizontalDefault,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              20.verticalSpace,
              Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [_profileCard()],
              ),
              20.verticalSpace,
              Text(
                patientName,
                style: theme.textTheme.titleLarge?.merge(
                  TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
              4.verticalSpace,
              TextMedium(text: "Palo Alto, CA"),
              Divider(color: colors.slate.shade100, height: 40.h),
              Text(
                "Mood Calendar",
                style: theme.textTheme.titleMedium?.merge(
                  TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
              TextMedium(
                text: "Collected from app openings and mood check-in’s",
                style: TextStyle(color: colors.slate.shade600),
              ),
              24.verticalSpace,
              WeekCalendar(
                onDateSelected: (date) {
                  // context.router.push(RouteEmoji());
                },
              ),
              Divider(color: colors.slate.shade100, height: 40.h),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Prescription",
                    style: theme.textTheme.titleMedium?.merge(
                      TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      context.push(CustomRoutePaths.prescription);
                    },
                    icon: Icon(
                      prescriptionProvider.prescriptionModelList.isEmpty
                          ? Icons.add
                          : Icons.edit,
                      color: theme.primaryColor,
                    ),
                    label: Text(
                      prescriptionProvider.prescriptionModelList.isEmpty
                          ? "Add"
                          : "Update",
                      style: TextStyle(color: theme.primaryColor),
                    ),
                  ),
                ],
              ),
              12.verticalSpace,
              // prescription view
              prescriptionProvider.prescriptionModelList.isEmpty
                  ? PrescriptionView(
                    onSetupVial: () async {
                      // Link the paired vial ID returned by the pairing screen
                      // to the prescription model. A null/empty result (user
                      // backed out) leaves the existing deviceId untouched.
                      // Capture the provider before the await so we don't use
                      // BuildContext across an async gap.
                      final provider = context.read<PrescriptionProvider>();
                      final pairedId = await context.push<String>(
                        CustomRoutePaths.screenConnectOnBoard,
                      );
                      provider.applyPairedDeviceId(pairedId);
                    },
                    drName: "Doctor Name",
                    address: "Address not found",
                    patientName: patientName,
                    rxNumber: "N/A",
                    storeNumber: "N/A",
                    title: "Medicine Name",

                    description: "No Instructions",

                    quantity: "0",

                    notification: "No Info",
                    sideEffects: "None",
                  )
                  : PrescriptionView(
                    onSetupVial: () async {
                      // Link the paired vial ID returned by the pairing screen
                      // to the prescription model. A null/empty result (user
                      // backed out) leaves the existing deviceId untouched.
                      // Capture the provider before the await so we don't use
                      // BuildContext across an async gap.
                      final provider = context.read<PrescriptionProvider>();
                      final pairedId = await context.push<String>(
                        CustomRoutePaths.screenConnectOnBoard,
                      );
                      provider.applyPairedDeviceId(pairedId);
                    },
                    drName:
                        prescriptionProvider
                            .prescriptionModelList
                            .first
                            .pharmacyOrDoctorName ??
                        "Doctor Name",
                    address:
                        prescriptionProvider
                            .prescriptionModelList
                            .first
                            .address ??
                        "Address not found",
                    patientName: patientName,
                    rxNumber:
                        prescriptionProvider
                            .prescriptionModelList
                            .first
                            .rxNumber ??
                        "N/A",
                    storeNumber:
                        prescriptionProvider
                            .prescriptionModelList
                            .first
                            .storeNumber ??
                        "N/A",
                    title:
                        prescriptionProvider
                                    .prescriptionModelList
                                    .first
                                    .medicines
                                    ?.isNotEmpty ==
                                true
                            ? prescriptionProvider
                                    .prescriptionModelList
                                    .first
                                    .medicines!
                                    .first
                                    .medicineName ??
                                "Medicine Name"
                            : "No Medicine",
                    description:
                        prescriptionProvider
                                    .prescriptionModelList
                                    .first
                                    .medicines
                                    ?.isNotEmpty ==
                                true
                            ? prescriptionProvider
                                    .prescriptionModelList
                                    .first
                                    .medicines!
                                    .first
                                    .instructions ??
                                "No Instructions"
                            : "No Instructions",
                    quantity:
                        prescriptionProvider
                                    .prescriptionModelList
                                    .first
                                    .medicines
                                    ?.isNotEmpty ==
                                true
                            ? prescriptionProvider
                                    .prescriptionModelList
                                    .first
                                    .medicines!
                                    .first
                                    .qty ??
                                "0"
                            : "0",
                    notification:
                        prescriptionProvider
                                    .prescriptionModelList
                                    .first
                                    .medicines
                                    ?.isNotEmpty ==
                                true
                            ? prescriptionProvider
                                    .prescriptionModelList
                                    .first
                                    .medicines!
                                    .first
                                    .refillsInfo ??
                                "No Info"
                            : "No Info",
                    sideEffects:
                        prescriptionProvider
                                    .prescriptionModelList
                                    .first
                                    .medicines
                                    ?.isNotEmpty ==
                                true
                            ? prescriptionProvider
                                    .prescriptionModelList
                                    .first
                                    .medicines!
                                    .first
                                    .sideEffects ??
                                "None"
                            : "None",
                  ),
              Divider(color: colors.slate.shade100, height: 40.h),
              Text(
                "Device",
                style: theme.textTheme.titleMedium?.merge(
                  TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
              4.verticalSpace,
              TextMedium(
                text: "Calibrate your Farda device",
                style: TextStyle(color: colors.slate.shade600),
              ),
              12.verticalSpace,
              // Entry point for the device calibration screen (GTM-538 builds
              // the full flow; this just makes the screen reachable).
              InkWell(
                onTap: () => context.push(CustomRoutePaths.calibration),
                borderRadius: BorderRadius.circular(16.r),
                child: Container(
                  padding: spacing.allM,
                  decoration: BoxDecoration(
                    color: colors.baseWhite,
                    borderRadius: BorderRadius.circular(16.r),
                    boxShadow: [
                      BoxShadow(
                        color: colors.baseBlack.withValues(alpha: 0.06),
                        offset: const Offset(0, 2),
                        blurRadius: 16,
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        height: 48.h,
                        width: 48.w,
                        decoration: BoxDecoration(
                          color: colors.slate.shade100,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.tune,
                          color: theme.primaryColor,
                          size: 24.h,
                        ),
                      ),
                      16.horizontalSpace,
                      Expanded(
                        child: TextMedium(
                          text: "Calibrate Device",
                          style: TextStyle(
                            color: colors.baseBlack,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        color: colors.slate.shade400,
                      ),
                    ],
                  ),
                ),
              ),
              Divider(color: colors.slate.shade100, height: 40.h),
              Text(
                "Care",
                style: theme.textTheme.titleMedium?.merge(
                  TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
              4.verticalSpace,
              TextMedium(
                text: "Manage caregivers and the patients you look after",
                style: TextStyle(color: colors.slate.shade600),
              ),
              12.verticalSpace,
              // GTM-517 — entry point for the caregiver/patient hub.
              InkWell(
                onTap: () => context.push(CustomRoutePaths.caregiver),
                borderRadius: BorderRadius.circular(16.r),
                child: Container(
                  padding: spacing.allM,
                  decoration: BoxDecoration(
                    color: colors.baseWhite,
                    borderRadius: BorderRadius.circular(16.r),
                    boxShadow: [
                      BoxShadow(
                        color: colors.baseBlack.withValues(alpha: 0.06),
                        offset: const Offset(0, 2),
                        blurRadius: 16,
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        height: 48.h,
                        width: 48.w,
                        decoration: BoxDecoration(
                          color: colors.slate.shade100,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.people_alt_outlined,
                          color: theme.primaryColor,
                          size: 24.h,
                        ),
                      ),
                      16.horizontalSpace,
                      Expanded(
                        child: TextMedium(
                          text: "Caregivers & patients",
                          style: TextStyle(
                            color: colors.baseBlack,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        color: colors.slate.shade400,
                      ),
                    ],
                  ),
                ),
              ),
              20.verticalSpace,
            ],
          ),
        ),
      ),
    );
  }

  Widget _profileCard() {
    return SizedBox(
      width: 80.r,
      height: 80.r,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipOval(
            child: Image.asset("assets/images/profile.png", fit: BoxFit.cover),
          ),
          Align(
            alignment: Alignment.bottomRight,
            child: InkWell(
              onTap: () {},
              child: SvgPicture.asset(
                "assets/icons/add_image.svg",
                width: 22.r,
                height: 22.r,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
