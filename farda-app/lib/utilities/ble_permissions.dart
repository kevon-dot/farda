import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Outcome of preparing the device for a BLE scan.
enum BleReadiness {
  /// Everything is in place; a scan may start.
  ready,

  /// The device has no Bluetooth hardware / BLE support.
  unsupported,

  /// Bluetooth is supported but the adapter is currently off.
  bluetoothOff,
}

/// Small helper that gates a BLE scan behind the checks/permissions that
/// `flutter_blue_plus` needs.
///
/// On Android 12+ and iOS, `flutter_blue_plus` surfaces the OS runtime
/// permission dialogs (BLUETOOTH_SCAN / BLUETOOTH_CONNECT, and location on
/// Android 11 and below) automatically the first time [FlutterBluePlus.startScan]
/// is called, *provided* the matching permissions are declared in
/// AndroidManifest.xml and Info.plist. This helper makes sure we only reach that
/// call once Bluetooth is actually supported and powered on, and centralises the
/// decision logic so it can be unit-tested without platform channels.
class BlePermissions {
  const BlePermissions._();

  /// Maps the raw Bluetooth support flag and adapter state into a single,
  /// testable readiness outcome. Pure function — no platform channels.
  static BleReadiness evaluate({
    required bool isSupported,
    required BluetoothAdapterState adapterState,
  }) {
    if (!isSupported) {
      return BleReadiness.unsupported;
    }
    if (adapterState != BluetoothAdapterState.on) {
      return BleReadiness.bluetoothOff;
    }
    return BleReadiness.ready;
  }

  /// True only when a scan can be started right now.
  static bool canScan({
    required bool isSupported,
    required BluetoothAdapterState adapterState,
  }) =>
      evaluate(isSupported: isSupported, adapterState: adapterState) ==
      BleReadiness.ready;

  /// Queries the live adapter state and returns the current readiness.
  ///
  /// This talks to platform channels, so it is exercised on a real device
  /// rather than in unit tests; the pure [evaluate] logic is what tests cover.
  static Future<BleReadiness> check() async {
    final supported = await FlutterBluePlus.isSupported;
    return evaluate(
      isSupported: supported,
      adapterState: FlutterBluePlus.adapterStateNow,
    );
  }
}
