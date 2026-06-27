// Pure-Dart unit tests for the router auth guard. These import only the pure
// helper (no widgets, plugins, or platform channels) so they run fast and
// reliably under `flutter test` in CI.

import 'package:flutter_test/flutter_test.dart';

import 'package:farda/utilities/auth_state.dart';

void main() {
  group('redirectTarget', () {
    group('when unauthenticated', () {
      test('redirects protected routes to /login', () {
        for (final location in const [
          '/dashboard',
          '/prescription',
          '/subscription',
          '/calibration',
          '/mood',
          '/emoji',
          '/screen-connect-onboard',
        ]) {
          expect(
            redirectTarget(isAuthed: false, location: location),
            '/login',
            reason: '$location should bounce to /login when signed out',
          );
        }
      });

      test('allows the unauthenticated entry / auth screens through', () {
        for (final location in const ['/', '/onboard', '/login', '/otp-verify']) {
          expect(
            redirectTarget(isAuthed: false, location: location),
            isNull,
            reason: '$location should be reachable while signed out',
          );
        }
      });
    });

    group('when authenticated', () {
      test('redirects /login and /otp-verify to /dashboard', () {
        expect(redirectTarget(isAuthed: true, location: '/login'), '/dashboard');
        expect(
          redirectTarget(isAuthed: true, location: '/otp-verify'),
          '/dashboard',
        );
      });

      test('leaves protected routes untouched', () {
        for (final location in const [
          '/dashboard',
          '/prescription',
          '/emoji',
          '/onboard',
          '/',
        ]) {
          expect(
            redirectTarget(isAuthed: true, location: location),
            isNull,
            reason: '$location should not redirect when signed in',
          );
        }
      });
    });
  });

  group('AuthState', () {
    test('defaults to unauthenticated', () {
      expect(AuthState().isAuthed, isFalse);
    });

    test('setAuthed notifies listeners only on change', () {
      final state = AuthState();
      var notifications = 0;
      state.addListener(() => notifications++);

      state.setAuthed(true);
      expect(state.isAuthed, isTrue);
      expect(notifications, 1);

      // Same value -> no extra notification.
      state.setAuthed(true);
      expect(notifications, 1);

      state.setAuthed(false);
      expect(state.isAuthed, isFalse);
      expect(notifications, 2);
    });
  });
}
