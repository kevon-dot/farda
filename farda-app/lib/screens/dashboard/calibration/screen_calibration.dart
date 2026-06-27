import 'package:easy_stepper/easy_stepper.dart';
import 'package:farda/components/_components.dart';
import 'package:farda/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/svg.dart';

class ScreenCalibration extends StatelessWidget {
  const ScreenCalibration({super.key});

  void showCalibrationDialog(BuildContext context) {
    final colors = Theme.of(context).extension<FardaColors>()!;
    final txtStyle = TextStyle(
      fontSize: 18.sp,
      color: Colors.black,
      fontWeight: FontWeight.bold,
    );
    showDialog(
      context: context,
      builder: (context) {
        return Align(
          alignment: Alignment.center,
          child: Dialog(
            insetPadding: EdgeInsets.only(
              left: 16.w,
              top: 16.w,
              right: 16.w,
              bottom: kToolbarHeight * 1.5,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24.r),
            ),
            alignment: Alignment.bottomCenter,
            clipBehavior: Clip.hardEdge,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                12.verticalSpace,
                Padding(
                  padding: EdgeInsets.all(16.w),
                  child: Column(
                    children: [
                      12.verticalSpace,
                      SvgPicture.asset(
                        "assets/icons/calibration_pill_icon.svg",
                      ),
                      12.verticalSpace,
                      TextMedium(
                        text: "CALIBRATION STARTED",
                        style: TextStyle(
                          color: colors.baseBlack,
                          fontSize: 16.sp,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      16.verticalSpace,
                      TextMedium(
                        text:
                            "Over the next four days, Farda will be accumulating baseline data to assess your medication data and your upcoming refill date.",
                        style: TextStyle(color: colors.slate.shade500),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                16.verticalSpace,
                Container(
                  decoration: BoxDecoration(
                    color: colors.baseWhite,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        offset: Offset(0, -10),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: EdgeInsets.only(top: 24.h),
                    child: Column(
                      children: [
                        TextMedium(
                          text: "4 days until initial calibration",
                          style: TextStyle(color: colors.slate.shade500),
                          textAlign: TextAlign.center,
                        ),
                        EasyStepper(
                          padding: EdgeInsets.zero,
                          showTitle: false,
                          activeStep: 1,
                          stepRadius: 16.r,
                          showStepBorder: true,
                          enableStepTapping: false,
                          showLoadingAnimation: false,
                          internalPadding: 2,
                          borderThickness: 2,

                          defaultStepBorderType: BorderType.normal,
                          activeStepBorderType: BorderType.normal,

                          unreachedStepBorderColor: colors.slate.shade300,
                          unreachedStepBackgroundColor: Colors.transparent,

                          activeStepBackgroundColor: Colors.transparent,
                          activeStepBorderColor: colors.success[500],

                          finishedStepBackgroundColor: colors.success[500],
                          finishedStepBorderType: BorderType.normal,
                          finishedStepBorderColor: colors.success[500],

                          titlesAreLargerThanSteps: false,
                          steps: [
                            // Step 1: Green circle with check
                            EasyStep(
                              customStep: CircleAvatar(
                                radius: 22.h,
                                backgroundColor: Colors.transparent,
                                child: Icon(
                                  Icons.check,
                                  color: colors.baseWhite,
                                  size: 20.h,
                                ),
                              ),
                            ),
                            // Step 2: Number in outlined circle
                            EasyStep(
                              customStep: CircleAvatar(
                                radius: 22,
                                backgroundColor: Colors.transparent,
                                foregroundColor: Colors.black,
                                child: Text('2', style: txtStyle),
                              ),
                            ),
                            // Step 3: Number in outlined circle
                            EasyStep(
                              customStep: CircleAvatar(
                                radius: 22,
                                backgroundColor: Colors.transparent,
                                foregroundColor: Colors.black,
                                child: Text('3', style: txtStyle),
                              ),
                            ),
                            // Step 4: Number in outlined circle
                            EasyStep(
                              customStep: CircleAvatar(
                                radius: 22,
                                backgroundColor: Colors.transparent,
                                foregroundColor: Colors.black,
                                child: Text('4', style: txtStyle),
                              ),
                            ),
                          ],
                          // Optional: Tap to change active step
                          onStepReached: (index) {},
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<FardaColors>()!;
    return Scaffold(
      backgroundColor: colors.baseWhite,
      appBar: CustomAppBar(
        isChild: false,
        titleType: AppBarTitleType.logo,
        logo: Image.asset(
          "assets/images/farda_large_grey.png",
          height: 0.03.sh,
        ),
      ),
      body: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            12.verticalSpace,
            Container(
              width: 0.6.sw,
              height: 0.6.sw,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [Color(0xFFD1FAE5), Color(0xFF10B981)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    offset: Offset(0, 10),
                    blurRadius: 24,
                  ),
                ],
                border: Border.all(
                  color: colors.baseWhite,
                  width: 10.r,
                  strokeAlign: 1,
                ),
              ),
              child: Center(
                child: SvgPicture.asset(
                  "assets/icons/calibration_capsule.svg",
                  width: 0.25.sw,
                  height: 0.25.sw,
                ),
              ),
            ),
            48.verticalSpace,
            GestureDetector(
              onTap: () => showCalibrationDialog(context),
              child: Container(
                padding: EdgeInsets.all(16.h),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.horizontal(
                    right: Radius.circular(100),
                    left: Radius.circular(100),
                  ),
                  color: colors.baseWhite,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      offset: Offset(0, 2),
                      blurRadius: 30,
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      height: 60.h,
                      width: 60.h,
                      decoration: BoxDecoration(
                        color: colors.slate.shade100,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Image.asset(
                          "assets/images/dna.png",
                          height: 50.h,
                          width: 50.h,
                        ),
                      ),
                    ),
                    12.horizontalSpace,
                    Expanded(
                      child: TextMedium(
                        text:
                            "We will now be calibrating your device. To get started, place one single pill on the platform.",
                        style: TextStyle(),
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
