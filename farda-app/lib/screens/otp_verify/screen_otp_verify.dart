import 'package:clipboard/clipboard.dart';
import 'package:farda/components/_components.dart';
import 'package:farda/components/custom_snackbar.dart';
import 'package:farda/routes/routes.dart';
import 'package:farda/screens/connect_onboard/screen_setup_vial.dart';
import 'package:farda/screens/login/login_provider.dart';

import 'package:farda/screens/otp_verify/otp_verify_controller.dart';
import 'package:farda/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:otp_text_field/otp_field.dart';
import 'package:otp_text_field/otp_field_style.dart';
import 'package:otp_text_field/style.dart';
import 'package:provider/provider.dart';

class ScreenOtpVerify extends StatefulWidget {
  const ScreenOtpVerify({super.key});

  @override
  State<ScreenOtpVerify> createState() => _ScreenOtpVerifyState();
}

class _ScreenOtpVerifyState extends State<ScreenOtpVerify> {
  String _otp = "";
  OtpFieldController otpController = OtpFieldController();

  void _pasteFromClipboard() async {
    final text = await FlutterClipboard.paste();
    if (text.length == 6 && RegExp(r'^\d+$').hasMatch(text)) {
      otpController.set(['', '', '', '', '', '']);
      otpController.set(text.split(''));
      setState(() {
        _otp = text;
      });
      debugPrint("OTP Pasted: $text");
    } else {
      debugPrint("Clipboard content is not a valid 6-digit OTP");
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FardaColors>()!;
    final spacing = theme.extension<Spacing>()!;
    final loginProvider = context.watch<LoginProvider>();


    return ExtendedScaffold(
      resize: true,
      appBar: CustomAppBar(
        titleType: AppBarTitleType.text,
        titleText: "Confirm it's you",
        // onBack: ()=> context.go(CustomRoutePaths.login),
        onBack: () => Navigator.pop(context),
      ),
      body: SafeArea(
        child: Padding(
          padding: spacing.horizontalDefault,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              20.verticalSpace,
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'Enter 6-digit OTP sent on ',
                      style: TextStyle(
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w400,
                        fontFamily: "Outfit",
                      ),
                    ),
                    TextSpan(
                      text: '${loginProvider.countryCode}${loginProvider.phoneNumber}',
                      style: TextStyle(
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w600,
                        fontFamily: "Outfit",
                      ),
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
              20.verticalSpace,
              Container(
                padding: EdgeInsets.all(16.r),
                decoration: BoxDecoration(
                  border: Border.all(color: colors.slate.shade200),
                  borderRadius: BorderRadius.circular(16.r),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OTPTextField(
                      length: 6,
                      width: MediaQuery.of(context).size.width,
                      fieldWidth: 45,
                      style: TextStyle(fontSize: 20),
                      textFieldAlignment: MainAxisAlignment.spaceAround,
                      fieldStyle: FieldStyle.box,
                      controller: otpController,
                      onChanged: (pin) => _otp = pin,
                      onCompleted: (pin) => OtpVerifyController.onSubmitPin(context, pin),
                      otpFieldStyle: OtpFieldStyle(
                        focusBorderColor: colors.baseBlack,
                        enabledBorderColor: colors.slate.shade200,
                      ),
                    ),
                    SizedBox(height: 20),
                    GestureDetector(
                      onTap: _pasteFromClipboard,
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: colors.slate.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              "Paste from clipboard",
                              style: TextStyle(
                                fontSize: 16.sp,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            8.horizontalSpace,
                            Icon(Icons.paste, size: 16.h),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Spacer(),
              Row(
                children: [
                  Expanded(
                    child: ButtonPrimary(
                      text: "Resend Code",
                      onClick: () => OtpVerifyController.onResendCode(context),
                    ),
                  ),
                  12.horizontalSpace,
                  Expanded(
                    child: ButtonTertiary(text: "Call Instead", onClick: () {}),
                  ),
                ],
              ),
              16.verticalSpace,
            ],
          ),
        ),
      ),
    );
  }
}
