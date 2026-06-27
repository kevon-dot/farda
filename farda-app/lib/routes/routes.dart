import 'package:farda/screens/_screens.dart';
import 'package:farda/screens/connect_onboard/screen_setup_vial.dart';
import 'package:farda/screens/dashboard/calendar/screen_calendar.dart';
import 'package:farda/screens/dashboard/calibration/screen_calibration.dart';
import 'package:farda/screens/dashboard/dashboard_shell.dart';
import 'package:farda/screens/dashboard/home/screen_home.dart';
import 'package:farda/screens/dashboard/mood_check/screen_mood_checkin.dart';
import 'package:farda/screens/dashboard/more/screen_more.dart';
import 'package:farda/screens/dashboard/plan/screen_plan.dart';
import 'package:farda/screens/emoji/screen_emoji.dart';
import 'package:farda/screens/login/screen_login.dart';
import 'package:farda/screens/onboard/screen_onboard.dart';
import 'package:farda/screens/otp_verify/screen_otp_verify.dart';
import 'package:farda/screens/prescription_info/screen_prescription.dart';
import 'package:farda/screens/subscription/screen_subscription.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();

class AppRouter {
 

  static final GoRouter router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    debugLogDiagnostics: true,
    initialLocation: CustomRoutePaths.onboard,
    routes: [
      GoRoute(
        path: CustomRoutePaths.dashboard,
        builder: (context, state) => ScreenDashboardShell(),
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
        builder: (context, state) => ScreenConnectOnboard(),
      ),
      GoRoute(
        path: CustomRoutePaths.subscription,
        builder: (context, state) => const ScreenSubscription(),
      ),
      GoRoute(
        path: CustomRoutePaths.prescription,
        builder: (context, state) => const ScreenPrescription(),
      ),
      // GoRoute(
      //   path: CustomRoutePaths.emoji,
      //   builder: (context, state) => const ScreenEmoji(),
      // ),
      GoRoute(
        path: CustomRoutePaths.mood,
        builder: (context, state) => const ScreenMoodCheckIn(),
      ),
      GoRoute(
        path: CustomRoutePaths.calibration,
        builder: (context, state) => const ScreenCalibration(),
      ),
      // Dashboard Shell Route
      ShellRoute(
        builder: (context, state, child) {
          return ScreenDashboardShell(
            child: state.fullPath == CustomRoutePaths.dashboard ? null : child,
          );
        },
        routes: [
          GoRoute(
            path: CustomRoutePaths.home,
            builder: (context, state) => const ScreenHome(),
          ),
          GoRoute(
            path: CustomRoutePaths.plan,
            builder: (context, state) => const ScreenPlanHope(),
          ),
          GoRoute(
            path: '/calendar',
            builder: (context, state) => const ScreenCalendar(),
            routes: [
              GoRoute(
                path: 'emoji',
                builder: (context, state) => const ScreenEmoji(),
              ),
            ],
          ),
          GoRoute(
            path: CustomRoutePaths.more,
            builder: (context, state) => const ScreenMore(),
          ),
        ],
      ),
    ],
    // redirect: (context, state) async {
    //   final initialRoute = await _getInitialRoute();

    //   // Redirect logic for other routes
    //   if (initialRoute == CustomRoutePaths.login) {
    //     return CustomRoutePaths
    //         .onboard; // Force redirect to login if accessing restricted routes
    //   } else if ((state.path == CustomRoutePaths.dashboard)) {
    //     return CustomRoutePaths.dashboard;
    //   }

    //   // Prevent redirecting to login if already on the login screen
    //   if (state.path == CustomRoutePaths.login &&
    //       initialRoute == CustomRoutePaths.login) {
    //     return null; // No redirect needed if already on the login screen
    //   }

    //   return initialRoute; // Default redirection (either dashboard or login)
    // },
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
  static const String emoji =
      '/calendar/emoji'; // Remove the '/' for relative path
  static const String mood = '/mood';
  static const String calibration = '/calibration';
  static const String dashboardto = '/dashboard/calendar';

  // Tabs under dashboard
  static const String home = 'home';
  static const String plan = 'plan';
  static const String calendar = 'calendar';
  static const String more = 'more';
}
