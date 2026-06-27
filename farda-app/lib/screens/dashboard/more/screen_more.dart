import 'package:farda/components/_components.dart';
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
                "Terry Roberts",
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
                    onSetupVial:
                        () =>
                            context.push(CustomRoutePaths.screenConnectOnBoard),
                    drName: "Doctor Name",
                    address: "Address not found",
                    patientName: "Tom Cruse",
                    rxNumber: "N/A",
                    storeNumber: "N/A",
                    title: "Medicine Name",

                    description: "No Instructions",

                    quantity: "0",

                    notification: "No Info",
                    sideEffects: "None",
                  )
                  : PrescriptionView(
                    onSetupVial:
                        () =>
                            context.push(CustomRoutePaths.screenConnectOnBoard),
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
                    patientName: "Tom Cruse",
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
