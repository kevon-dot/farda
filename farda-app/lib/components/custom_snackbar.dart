import 'package:farda/theme.dart';
import 'package:flutter/material.dart';

class CustomSnackbar {
  static void show(
    BuildContext context, {
    required String message,
    Color? backgroundColor,
    Color? textColor,
    Duration duration = const Duration(seconds: 3),
    IconData? icon,
  }) {
    final colors = Theme.of(context).extension<FardaColors>()!;
    // Matches Material's Colors.black87 (alpha 0xDD).
    backgroundColor ??= colors.baseBlack.withValues(alpha: 0xDD / 0xFF);
    textColor ??= colors.baseWhite;
    final snackBar = SnackBar(
      duration: duration,
      behavior: SnackBarBehavior.floating,
      backgroundColor: backgroundColor,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      content: Row(
        children: [
          if (icon != null)
            Padding(
              padding: const EdgeInsets.only(right: 12.0),
              child: Icon(icon, color: textColor),
            ),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: textColor, fontSize: 15),
            ),
          ),
        ],
      ),
    );

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }
}
