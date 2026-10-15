import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let liveActivityBridge = LiveActivityBridge()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      liveActivityBridge.register(with: controller.binaryMessenger)
    }
    if let url = launchOptions?[.url] as? URL { liveActivityBridge.open(url) }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(_ app: UIApplication, open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
    if liveActivityBridge.open(url) { return true }
    return super.application(app, open: url, options: options)
  }
}
