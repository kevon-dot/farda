import 'package:farda/components/custom_snackbar.dart';
import 'package:farda/screens/login/login_provider.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../routes/routes.dart';

class OtpVerifyController {
  
  static Future<void> onResendCode(BuildContext context) async {
    final loginProvider = context.read<LoginProvider>();
    bool response = await loginProvider.sendOtpApi();
    
    if (!context.mounted) return;
    
    if (response) {
      CustomSnackbar.show(
        context,
        message: "Your OTP has been resent to your phone.",
      );
    } else {
      CustomSnackbar.show(
        context,
        message: "Failed to resend OTP. Please try again.",
      );
    }
  }

  static Future<void> onSubmitPin(BuildContext context, String pin) async {
    if (pin.length != 6) return; // Basic validation
    
    final loginProvider = context.read<LoginProvider>();
    bool response = await loginProvider.verifyOtpApi(pin);
    
    if (!context.mounted) return;

    if (response) {
      CustomSnackbar.show(
        context, 
        message: "OTP verified successfully."
      );
      context.go(CustomRoutePaths.dashboard);
    } else {
      CustomSnackbar.show(
        context, 
        message: "Invalid OTP. Please try again."
      );
    }
  }
}
