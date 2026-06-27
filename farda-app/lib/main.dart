import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:farda/application/reminders/service/notification_service.dart';
import 'package:farda/routes/routes.dart';
import 'package:farda/screens/caregiver/caregiver_provider.dart';
import 'package:farda/screens/dashboard/calendar/calender_provider.dart';
import 'package:farda/screens/dashboard/home/home_provider.dart';
import 'package:farda/screens/emoji/emoji_provider.dart';
import 'package:farda/screens/prescription_info/prescription_provider.dart';
import 'package:farda/screens/refill/refill_provider.dart';
import 'package:farda/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:toastification/toastification.dart';
import 'package:provider/provider.dart';
import 'screens/login/login_provider.dart';

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
 
  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(393, 852),
      minTextAdapt: true,
      splitScreenMode: true,
      ensureScreenSize: true,
      builder: (_, child) {
        return ToastificationWrapper(
          child: MultiProvider(
            providers: [
              ChangeNotifierProvider(create: (_) => LoginProvider()..loadFromPrefs()),
              ChangeNotifierProvider(create: (_) => EmojiProvider()),
              // Calendar / Prescription providers intentionally do NOT fetch on
              // construction: their endpoints are authenticated and the bearer
              // token is empty before login. Their fetches are triggered after
              // authentication, gated by AuthGate (see ScreenDashboardShell).
              ChangeNotifierProvider(create: (_) => CalenderProvider()),
              ChangeNotifierProvider(
                create: (_) => PrescriptionProvider(),
              ),
              // Add your providers here
              ChangeNotifierProvider(create: (_) => HomeProvider()),
              // GTM-517 — caregiver/patient experience. Like the calendar /
              // prescription providers it does NOT fetch on construction: its
              // Vial endpoints are authenticated, so the screen triggers
              // loadGrants()/loadAuthorizedSummaries() post-auth in initState.
              ChangeNotifierProvider(create: (_) => CaregiverProvider()),
              // GTM-541 — refill prediction + pharmacy-readiness. Like the
              // calendar / prescription / caregiver providers it does NOT fetch
              // on construction (its `/refills` endpoint is authenticated); the
              // refill screen triggers load() post-auth in initState.
              ChangeNotifierProvider(create: (_) => RefillProvider()),
            ],
            child: MaterialApp.router(
              theme: AppTheme.theme,
              routerConfig: AppRouter.router,
            ),
          ),
        );
      },
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      systemStatusBarContrastEnforced: false,
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  const String environment = String.fromEnvironment('ENV', defaultValue: 'development');
  await dotenv.load(fileName: ".env.$environment");

  // Seed the router's cached auth flag from secure storage before the first
  // frame so the redirect guard makes the right call on deep links / cold start.
  await AppRouter.authState.hydrate();

  // Initialise the local-notification engine (timezone db + plugin + tap
  // handler) so dose reminders can be scheduled. Scheduling itself is triggered
  // post-auth (#43) in the dashboard shell; init here is safe + cheap and does
  // not require a session. Tolerant of failure so a notification-init hiccup
  // never blocks app start.
  try {
    await NotificationService.instance.init();
  } catch (e) {
    debugPrint('NotificationService init failed: $e');
  }

  // await injectDependencies();

  runApp(const MyApp());
}
