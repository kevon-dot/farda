part of '_utilities.dart';

void showErrorToast(String msg, [String? title, bool isLonger = false]) {
  toastification.show(
    type: ToastificationType.error,
    style: ToastificationStyle.fillColored,
    title: title != null ? Text(title) : null,
    description: Text(msg),
    alignment: Alignment.topCenter,
    autoCloseDuration:
        isLonger ? const Duration(seconds: 4) : const Duration(seconds: 2),
    icon: SvgPicture.asset(
      "assets/icons/warning.svg",
      height: 24.h,
      width: 24.h,
    ),
    // backgroundColor: AppColors.onAccent,
    // primaryColor: AppColors.accentRed,
    // foregroundColor: AppColors.onAccent,
  );
}

void showInfoToast(
  String msg, {
  String? title,
  bool isLonger = false,
  Alignment alignment = Alignment.topCenter,
}) {
  toastification.show(
    type: ToastificationType.info,
    style: ToastificationStyle.fillColored,
    title: title != null ? Text(title) : null,
    description: Text(msg),
    alignment: alignment,
    autoCloseDuration:
        isLonger ? const Duration(seconds: 4) : const Duration(seconds: 2),
    icon: SvgPicture.asset(
      "assets/icons/green_check.svg",
      height: 24.h,
      width: 24.h,
    ),
    // backgroundColor: AppColors.onAccent,
    // primaryColor: AppColors.mainText,
    // foregroundColor: AppColors.onAccent,
  );
}

// String formatTime(int milliseconds, {String timeFormat = "HH:mm"}) {
//   final DateTime dateTime = DateTime.fromMillisecondsSinceEpoch(milliseconds);
//   final DateFormat formatter = DateFormat(timeFormat);
//   return formatter.format(dateTime);
// }
