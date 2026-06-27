import 'package:farda/components/custom_snackbar.dart';
import 'package:farda/routes/routes.dart';
import 'package:farda/screens/login/login_provider.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

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
      context.push(CustomRoutePaths.otpVerify);
    } else {
      CustomSnackbar.show(
        context,
        message: "Failed to send OTP. Please check your number.",
      );
    }
  }
}
