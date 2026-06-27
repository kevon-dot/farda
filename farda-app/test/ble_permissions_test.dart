// Pure-Dart unit tests for the BlePermissions decision logic. These only
// touch the `evaluate`/`canScan` pure functions and the BluetoothAdapterState
// enum from flutter_blue_plus (no platform channels), so they run under
// `flutter test` in CI without a device.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'package:farda/utilities/ble_permissions.dart';

void main() {
  group('BlePermissions.evaluate', () {
    test('returns unsupported when BLE is not supported', () {
      expect(
        BlePermissions.evaluate(
          isSupported: false,
          adapterState: BluetoothAdapterState.on,
        ),
        BleReadiness.unsupported,
      );
    });

    test('unsupported takes precedence even when the adapter is off', () {
      expect(
        BlePermissions.evaluate(
          isSupported: false,
          adapterState: BluetoothAdapterState.off,
        ),
        BleReadiness.unsupported,
      );
    });

    test('returns bluetoothOff when supported but adapter is not on', () {
      expect(
        BlePermissions.evaluate(
          isSupported: true,
          adapterState: BluetoothAdapterState.off,
        ),
        BleReadiness.bluetoothOff,
      );
    });

    test('treats unknown/turning-on adapter states as not ready', () {
      expect(
        BlePermissions.evaluate(
          isSupported: true,
          adapterState: BluetoothAdapterState.turningOn,
        ),
        BleReadiness.bluetoothOff,
      );
      expect(
        BlePermissions.evaluate(
          isSupported: true,
          adapterState: BluetoothAdapterState.unknown,
        ),
        BleReadiness.bluetoothOff,
      );
    });

    test('returns ready when supported and adapter is on', () {
      expect(
        BlePermissions.evaluate(
          isSupported: true,
          adapterState: BluetoothAdapterState.on,
        ),
        BleReadiness.ready,
      );
    });
  });

  group('BlePermissions.canScan', () {
    test('is true only when supported and on', () {
      expect(
        BlePermissions.canScan(
          isSupported: true,
          adapterState: BluetoothAdapterState.on,
        ),
        isTrue,
      );
    });

    test('is false when unsupported', () {
      expect(
        BlePermissions.canScan(
          isSupported: false,
          adapterState: BluetoothAdapterState.on,
        ),
        isFalse,
      );
    });

    test('is false when the adapter is off', () {
      expect(
        BlePermissions.canScan(
          isSupported: true,
          adapterState: BluetoothAdapterState.off,
        ),
        isFalse,
      );
    });
  });
}
