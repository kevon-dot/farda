import 'package:farda/screens/connect_onboard/screen_setup_vial.dart';
import 'package:farda/screens/dashboard/calibration/screen_calibration.dart';
import 'package:farda/screens/dashboard/dashboard_shell.dart';
import 'package:farda/screens/dashboard/mood_check/screen_mood_checkin.dart';
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
        redirect: (context, state) => CustomRoutePaths.today,
      ),
      GoRoute(
        path: '${CustomRoutePaths.dashboard}/:tab',
        redirect: (context, state) {
          final tab = state.pathParameters['tab'];
          return CustomRoutePaths.consumerTabs.contains(tab)
              ? null
              : CustomRoutePaths.today;
        },
        builder: (context, state) => ScreenDashboardShell(
          initialIndex: CustomRoutePaths.consumerTabs.indexOf(
            state.pathParameters['tab']!,
          ),
          onTabSelected: (index) {
            context.go(CustomRoutePaths.consumerTabPath(index));
          },
        ),
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
      GoRoute(
        path: CustomRoutePaths.legacyHome,
        redirect: (context, state) => CustomRoutePaths.today,
      ),
      GoRoute(
        path: CustomRoutePaths.legacyPlan,
        redirect: (context, state) => CustomRoutePaths.refills,
      ),
      GoRoute(
        path: CustomRoutePaths.legacyCalendar,
        redirect: (context, state) => CustomRoutePaths.calendar,
      ),
      GoRoute(
        path: CustomRoutePaths.legacyMore,
        redirect: (context, state) => CustomRoutePaths.you,
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
  static const String screenConnectOnBoard = '/screen-connect-onboard';
  static const String onboard = '/onboard';
  static const String dashboard = '/dashboard';
  static const String login = '/login';
  static const String otpVerify = '/otp-verify';
  static const String subscription = '/subscription';
  static const String prescription = '/prescription';
  static const String emoji =
      '/calendar/emoji'; // Remove the '/' for relative path
  static const String mood = '/mood';
  static const String calibration = '/calibration';
  // Consumer-v2 tabs under dashboard.
  static const String today = '/dashboard/today';
  static const String calendar = '/dashboard/calendar';
  static const String refills = '/dashboard/refills';
  static const String you = '/dashboard/you';
  static const String dashboardto = calendar;
  static const List<String> consumerTabs = [
    'today',
    'calendar',
    'refills',
    'you',
  ];

  static String consumerTabPath(int index) {
    final safeIndex = index.clamp(0, consumerTabs.length - 1).toInt();
    return '$dashboard/${consumerTabs[safeIndex]}';
  }

  // Legacy aliases retained while older callers are migrated.
  static const String home = today;
  static const String plan = refills;
  static const String more = you;
  static const String legacyHome = '/home';
  static const String legacyPlan = '/plan';
  static const String legacyCalendar = '/calendar';
  static const String legacyMore = '/more';
}
