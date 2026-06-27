/// Capability flag for push notifications (FCM/APNs) — GTM-537 SCAFFOLD.
///
/// Push is GATED OFF by default so the app builds and runs WITHOUT a Firebase
/// project, `google-services.json`, an APNs cert, or the `firebase_messaging`
/// dependency. Local notifications (flutter_local_notifications) are the live
/// delivery path today and need none of that.
///
/// Enabling push (follow-up for the maintainer):
///   1. Create the Firebase project; add `google-services.json` (android/app/)
///      and `GoogleService-Info.plist` (ios/Runner/), plus the APNs key/cert.
///   2. Add `firebase_core` + `firebase_messaging` to pubspec.yaml and run the
///      platform setup (FlutterFire), then `firebase_messaging`'s token APIs.
///   3. Implement [PushService.retrieveToken] against `FirebaseMessaging` and
///      flip [enabled] (e.g. via `--dart-define=ENABLE_PUSH=true`).
/// Until then the registration path below is a NO-OP and never references
/// Firebase, so the build is unaffected.
class PushCapability {
  /// Whether push is enabled for this build. Driven by a dart-define so push can
  /// be turned on only in builds that actually ship Firebase config. Defaults to
  /// false everywhere else.
  static const bool enabled =
      bool.fromEnvironment('ENABLE_PUSH', defaultValue: false);
}
