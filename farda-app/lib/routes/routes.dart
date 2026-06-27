import 'package:farda/screens/connect_onboard/screen_setup_vial.dart';
import 'package:farda/screens/dashboard/calibration/screen_calibration.dart';
import 'package:farda/screens/dashboard/dashboard_shell.dart';
import 'package:farda/screens/dashboard/mood_check/screen_mood_checkin.dart';
import 'package:farda/screens/emoji/screen_emoji.dart';
import 'package:farda/screens/login/screen_login.dart';
import 'package:farda/screens/onboard/screen_onboard.dart';
import 'package:farda/screens/otp_verify/screen_otp_verify.dart';
import 'package:farda/screens/prescription_info/screen_prescription.dart';
import 'package:farda/screens/subscription/screen_subscription.dart';
import 'package:farda/utilities/auth_state.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();

class AppRouter {
  /// Cached auth flag the redirect reads synchronously. Hydrated once at
  /// startup (see `main.dart`) and updated on login / logout. The router
  /// re-evaluates redirects whenever this notifies (via [refreshListenable]).
  static final AuthState authState = AuthState();

  static final GoRouter router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    debugLogDiagnostics: true,
    initialLocation: CustomRoutePaths.onboard,
    refreshListenable: authState,
    routes: [
      GoRoute(
        path: CustomRoutePaths.dashboard,
        builder: (context, state) => const ScreenDashboardShell(),
      ),
      GoRoute(
        path: CustomRoutePaths.login,
        builder: (context, state) => const ScreenLogin(),
      ),
      GoRoute(
        path: CustomRoutePaths.otpVerify,
        builder: (context, state) => const ScreenOtpVerify(),
      ),
      GoRoute(
        path: CustomRoutePaths.onboard,
        builder: (context, state) => const ScreenOnboard(),
      ),
      GoRoute(
        path: CustomRoutePaths.screenConnectOnBoard,
        builder: (context, state) => const ScreenConnectOnboard(),
      ),
      GoRoute(
        path: CustomRoutePaths.subscription,
        builder: (context, state) => const ScreenSubscription(),
      ),
      GoRoute(
        path: CustomRoutePaths.prescription,
        builder: (context, state) => const ScreenPrescription(),
      ),
      GoRoute(
        path: CustomRoutePaths.emoji,
        builder: (context, state) => const ScreenEmoji(),
      ),
      GoRoute(
        path: CustomRoutePaths.mood,
        builder: (context, state) => const ScreenMoodCheckIn(),
      ),
      GoRoute(
        path: CustomRoutePaths.calibration,
        builder: (context, state) => const ScreenCalibration(),
      ),
    ],
    // Auth guard. Deep links to protected routes require a valid session
    // (a non-empty bearer token in secure storage, cached in [authState]).
    // Unauthenticated -> /login; authenticated hitting /login or the OTP step
    // -> /dashboard. Kept synchronous by reading the cached flag rather than
    // touching secure storage on every navigation.
    redirect: (context, state) {
      return redirectTarget(
        isAuthed: authState.isAuthed,
        location: state.matchedLocation,
      );
    },
  );
}

class CustomRoutePaths {
  static const String root = '/';
  static const String screenConnectOnBoard = "/screen-connect-onboard";
  static const String onboard = "/onboard";
  static const String dashboard = '/dashboard';
  static const String login = '/login';
  static const String otpVerify = '/otp-verify';
  static const String subscription = '/subscription';
  static const String prescription = '/prescription';
  // Emoji is a standalone (pushed) route so it can be popped back to the
  // calendar it was opened from.
  static const String emoji = '/emoji';
  static const String mood = '/mood';
  static const String calibration = '/calibration';
}
