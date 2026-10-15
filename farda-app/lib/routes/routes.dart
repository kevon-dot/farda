import 'package:farda/consumer_v2/consumer_v2_entry.dart';
import 'package:farda/features/consumer/consumer_entry.dart';
import 'package:farda/screens/connect_onboard/screen_setup_vial.dart';
import 'package:farda/screens/dashboard/calibration/screen_calibration.dart';
import 'package:farda/screens/dashboard/mood_check/screen_mood_checkin.dart';
import 'package:farda/screens/emoji/screen_emoji.dart';
import 'package:farda/screens/login/screen_login.dart';
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
    initialLocation: const bool.fromEnvironment('FARDA_DEMO')
        ? '/consumer/demo'
        : CustomRoutePaths.onboard,
    routes: [
      GoRoute(
        path: CustomRoutePaths.root,
        redirect: (context, state) => CustomRoutePaths.onboard,
      ),
      GoRoute(
        path: CustomRoutePaths.dashboard,
        builder: (context, state) => ConsumerEntry(
          initialTab: state.uri.queryParameters['tab'] == 'refills' ? 2 : 0,
        ),
      ),
      GoRoute(
        path: CustomRoutePaths.consumer,
        builder: (context, state) => const ConsumerEntry(),
      ),
      GoRoute(
        path: CustomRoutePaths.consumerDemo,
        builder: (context, state) => const ConsumerEntry(demo: true),
      ),
      GoRoute(
        path: CustomRoutePaths.consumerV2,
        redirect: (context, state) => CustomRoutePaths.consumerV2Today,
      ),
      GoRoute(
        path: '${CustomRoutePaths.consumerV2}/:tab',
        redirect: (context, state) {
          final tab = state.pathParameters['tab'];
          return CustomRoutePaths.consumerV2Tabs.contains(tab)
              ? null
              : CustomRoutePaths.consumerV2Today;
        },
        builder: (context, state) {
          final index = CustomRoutePaths.consumerV2Tabs.indexOf(
            state.pathParameters['tab']!,
          );
          return ConsumerV2Entry(
            initialIndex: index,
            onTabSelected: (selected) =>
                context.go(CustomRoutePaths.consumerV2TabPath(selected)),
            onOpenAccount: () => context.go(CustomRoutePaths.dashboard),
            onOpenRefillTools: () => context.go('${CustomRoutePaths.dashboard}?tab=refills'),
          );
        },
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
        builder: (context, state) => const ConsumerWelcome(),
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
      GoRoute(
        path: CustomRoutePaths.mood,
        builder: (context, state) => const ScreenMoodCheckIn(),
      ),
      GoRoute(
        path: CustomRoutePaths.calibration,
        builder: (context, state) => const ScreenCalibration(),
      ),
      GoRoute(
        path: CustomRoutePaths.emoji,
        builder: (context, state) => const ScreenEmoji(),
      ),
      GoRoute(
        path: CustomRoutePaths.home,
        redirect: (context, state) => CustomRoutePaths.consumerV2Today,
      ),
      GoRoute(
        path: CustomRoutePaths.plan,
        redirect: (context, state) => CustomRoutePaths.consumerV2Refills,
      ),
      GoRoute(
        path: CustomRoutePaths.calendar,
        redirect: (context, state) => CustomRoutePaths.consumerV2Calendar,
      ),
      GoRoute(
        path: CustomRoutePaths.more,
        redirect: (context, state) => CustomRoutePaths.consumerV2You,
      ),
    ],
  );
}

class CustomRoutePaths {
  static const String root = '/';
  static const String screenConnectOnBoard = '/screen-connect-onboard';
  static const String onboard = '/onboard';
  static const String dashboard = '/dashboard';
  static const String consumer = '/consumer';
  static const String consumerDemo = '/consumer/demo';
  static const String consumerV2 = '/consumer/v2';
  static const String login = '/login';
  static const String otpVerify = '/otp-verify';
  static const String subscription = '/subscription';
  static const String prescription = '/prescription';
  static const String emoji = '/calendar/emoji';
  static const String mood = '/mood';
  static const String calibration = '/calibration';

  static const String consumerV2Today = '/consumer/v2/today';
  static const String consumerV2Calendar = '/consumer/v2/calendar';
  static const String consumerV2Refills = '/consumer/v2/refills';
  static const String consumerV2You = '/consumer/v2/you';
  static const List<String> consumerV2Tabs = [
    'today',
    'calendar',
    'refills',
    'you',
  ];

  static String consumerV2TabPath(int index) {
    final safeIndex = index.clamp(0, consumerV2Tabs.length - 1).toInt();
    return '$consumerV2/${consumerV2Tabs[safeIndex]}';
  }

  static const String home = '/home';
  static const String plan = '/plan';
  static const String calendar = '/calendar';
  static const String more = '/more';
  static const String dashboardto = consumerV2Calendar;
}
