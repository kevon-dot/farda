import 'package:farda/components/custom_snackbar.dart';
import 'package:farda/screens/login/login_provider.dart';
import 'package:farda/screens/otp_verify/screen_otp_verify.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class LoginController {
  // Validate and Send OTP Controller logic
  static Future<void> onContinueClicked(BuildContext context) async {
    FocusScope.of(context).unfocus();

    final loginProvider = context.read<LoginProvider>();

    // Validate input length before hitting provider fully
    final RegExp phoneRegex = RegExp(r'^[0-9]{7,15}$');
    if (!phoneRegex.hasMatch(loginProvider.phoneNumber)) {
      CustomSnackbar.show(
        context,
        message: "Please enter a valid mobile number (7-15 digits).",
      );
      return;
    }

    bool response = await loginProvider.sendOtpApi();
    if (!context.mounted) return;

    if (response == true) {
      CustomSnackbar.show(
        context,
        message: "Your OTP has been sent to your phone.",
      );
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ScreenOtpVerify()),
      );
    } else {
      CustomSnackbar.show(
        context,
        message: "Failed to send OTP. Please check your number.",
      );
    }
  }
}
