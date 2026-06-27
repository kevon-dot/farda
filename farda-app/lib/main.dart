import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:farda/routes/routes.dart';
import 'package:farda/screens/dashboard/calendar/calender_provider.dart';
import 'package:farda/screens/dashboard/home/home_provider.dart';
import 'package:farda/screens/emoji/emoji_provider.dart';
import 'package:farda/screens/prescription_info/prescription_provider.dart';
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

  // await injectDependencies();

  runApp(const MyApp());
}
