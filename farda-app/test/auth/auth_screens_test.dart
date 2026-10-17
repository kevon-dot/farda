import 'dart:async';
import 'dart:io';
import 'package:farda/components/_components.dart';
import 'package:farda/screens/login/login_provider.dart';
import 'package:farda/screens/login/screen_login.dart';
import 'package:farda/screens/otp_verify/screen_otp_verify.dart';
import 'package:farda/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

class FakeLogin extends LoginProvider {
  int sends = 0;
  final pins = <String>[];
  Completer<bool>? pendingSend;
  Completer<bool>? pendingVerify;
  @override
  Future<bool> sendOtpApi() async {
    sends++;
    isLoading = true;
    notifyListeners();
    final result = await (pendingSend?.future ?? Future.value(true));
    isLoading = false;
    notifyListeners();
    return result;
  }

  @override
  Future<bool> verifyOtpApi(String pin) async {
    pins.add(pin);
    return pendingVerify?.future ?? false;
  }
}

Future<void> mount(
  WidgetTester tester,
  FakeLogin login, {
  bool verify = false,
  double width = 390,
  double scale = 1,
  double keyboard = 0,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    initialLocation: verify ? '/verify' : '/login',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const Scaffold(body: Text('Welcome')),
      ),
      GoRoute(path: '/login', builder: (_, __) => const ScreenLogin()),
      GoRoute(path: '/verify', builder: (_, __) => const ScreenOtpVerify()),
      GoRoute(
        path: '/consumer/v2/today',
        builder: (_, __) => const Scaffold(body: Text('Your day')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider<LoginProvider>.value(
      value: login,
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder:
            (_, __) => MaterialApp.router(
              routerConfig: router,
              debugShowCheckedModeBanner: false,
              theme: AppTheme.theme,
              builder:
                  (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      padding: const EdgeInsets.only(top: 48, bottom: 20),
                      viewInsets: EdgeInsets.only(bottom: keyboard),
                      textScaler: TextScaler.linear(scale),
                    ),
                    child: child!,
                  ),
            ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'phone prefix matches the request and country selection persists into code review',
    (tester) async {
      final login = FakeLogin();
      await mount(tester, login);
      expect(find.text('+1'), findsOneWidget);
      expect(find.textContaining('Apple'), findsNothing);
      expect(find.textContaining('Google'), findsNothing);
      await tester.tap(find.text('🌐'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Albania'));
      await tester.pumpAndSettle();
      expect(login.countryCode, '+355');
      await tester.enterText(find.byType(TextField), '123456789');
      await tester.tap(find.text('Send code'));
      await tester.pumpAndSettle();
      expect(login.sends, 1);
      expect(find.textContaining('+355123456789'), findsOneWidget);
      expect(find.text('Call Instead'), findsNothing);
      await tester.tap(find.text('Use a different number'));
      await tester.pumpAndSettle();
      expect(find.text('123456789'), findsOneWidget);
      expect(find.text('+355'), findsOneWidget);
    },
  );

  testWidgets('sending locks repeated requests and unlocks after failure', (
    tester,
  ) async {
    final login = FakeLogin()..pendingSend = Completer<bool>();
    await mount(tester, login);
    await tester.enterText(find.byType(TextField), '5551234567');
    await tester.tap(find.text('Send code'));
    await tester.pump();
    expect(find.text('Sending code…'), findsOneWidget);
    await tester.tap(find.text('Sending code…'));
    expect(login.sends, 1);
    login.pendingSend!.complete(false);
    await tester.pumpAndSettle();
    expect(find.text('Send code'), findsOneWidget);
    expect(find.textContaining('Failed to send'), findsOneWidget);
  });

  testWidgets(
    'code accepts pasted digits, requires confirmation and prevents duplicate verification',
    (tester) async {
      final login =
          FakeLogin()
            ..phoneNumber = '5551234567'
            ..pendingVerify = Completer<bool>();
      await mount(tester, login, verify: true);
      final field = find.byKey(const Key('auth_code'));
      expect(
        tester.widget<TextField>(field).autofillHints,
        contains(AutofillHints.oneTimeCode),
      );
      await tester.enterText(field, '123');
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      expect(login.pins, isEmpty);
      await tester.enterText(field, '12x34567');
      await tester.pump();
      expect(tester.widget<TextField>(field).controller!.text, '123456');
      expect(login.pins, isEmpty);
      await tester.tap(find.text('Continue'));
      await tester.pump();
      expect(find.text('Checking code…'), findsOneWidget);
      expect(tester.widget<TextField>(field).enabled, isFalse);
      await tester.tap(find.text('Checking code…'));
      await tester.tap(find.text('Resend code'));
      expect(login.pins, ['123456']);
      expect(login.sends, 0);
      login.pendingVerify!.complete(false);
      await tester.pumpAndSettle();
      expect(find.textContaining('Invalid OTP'), findsOneWidget);
      expect(tester.widget<TextField>(field).enabled, isTrue);
      expect(tester.widget<TextField>(field).controller!.text, '123456');
    },
  );

  testWidgets(
    'keyboard submit reaches signed-in route and resend stays single-flight',
    (tester) async {
      final login =
          FakeLogin()
            ..pendingSend = Completer<bool>()
            ..pendingVerify = Completer<bool>();
      await mount(tester, login, verify: true);
      await tester.tap(find.text('Resend code'));
      await tester.pump();
      await tester.tap(find.text('Sending another code…'));
      expect(login.sends, 1);
      login.pendingSend!.complete(true);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('auth_code')), '123456');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(login.pins, ['123456']);
      login.pendingVerify!.complete(true);
      await tester.pumpAndSettle();
      expect(find.text('Your day'), findsOneWidget);
    },
  );

  for (final width in [390.0, 320.0]) {
    testWidgets(
      'auth remains scrollable at $width with large text and keyboard',
      (tester) async {
        final fonts = FontLoader('Outfit');
        for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
          fonts.addFont(rootBundle.load('assets/fonts/Outfit-$weight.ttf'));
        }
        await fonts.load();
        final root = Platform.environment['FLUTTER_ROOT'];
        if (root != null) {
          await (FontLoader('MaterialIcons')..addFont(
            Future.value(
              ByteData.sublistView(
                File(
                  '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
                ).readAsBytesSync(),
              ),
            ),
          )).load();
        }
        final login = FakeLogin()..phoneNumber = '5551234567';
        await mount(tester, login, width: width, scale: width == 320 ? 1.6 : 1);
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('UPDATE_VISUALS')) {
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('goldens/login-${width.toInt()}.png'),
          );
        }
        // Verify the phone form remains reachable above an open keyboard.
        await mount(
          tester,
          login,
          width: width,
          scale: width == 320 ? 1.6 : 1,
          keyboard: 300,
        );
        await tester.showKeyboard(find.byType(TextField));
        await tester.ensureVisible(find.text('Send code'));
        expect(tester.takeException(), isNull);
        await mount(
          tester,
          login,
          verify: true,
          width: width,
          scale: width == 320 ? 1.6 : 1,
          keyboard: 300,
        );
        await tester.enterText(find.byKey(const Key('auth_code')), '123456');
        await tester.ensureVisible(find.text('Continue'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('UPDATE_VISUALS')) {
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('goldens/verify-keyboard-${width.toInt()}.png'),
          );
        }
        await tester.ensureVisible(find.text('Use a different number'));
        await tester.tap(find.text('Use a different number'));
        await tester.pumpAndSettle();
        expect(find.byType(PhoneNumberInput), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
