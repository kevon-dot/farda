import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ble_sync_service.dart';

/// Call only with the exact UUID/role mapping agreed with the firmware vendor.
/// The current handoff does not identify roles reliably, so the app does not
/// instantiate this adapter from a substring or arbitrary characteristic.
class GattBleTransport implements BleSyncTransport {
  GattBleTransport._(this._write, this._notify);
  final BluetoothCharacteristic _write;
  final BluetoothCharacteristic _notify;

  factory GattBleTransport.fromDiscovered({
    required List<BluetoothService> services,
    required String serviceUuid,
    required String writeUuid,
    required String notifyUuid,
  }) {
    final uuid = RegExp(
      r'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$',
    );
    if (![serviceUuid, writeUuid, notifyUuid].every(uuid.hasMatch)) {
      throw ArgumentError('Exact canonical 128-bit UUIDs are required');
    }
    final service =
        services.where((value) => value.uuid == Guid(serviceUuid)).single;
    final write =
        service.characteristics
            .where((value) => value.uuid == Guid(writeUuid))
            .single;
    final notify =
        service.characteristics
            .where((value) => value.uuid == Guid(notifyUuid))
            .single;
    if (!write.properties.write || !notify.properties.notify) {
      throw StateError('Firmware characteristics do not match the contract');
    }
    return GattBleTransport._(write, notify);
  }

  @override
  Stream<List<int>> get notifications => _notify.onValueReceived;
  @override
  Future<void> setNotifications(bool enabled) async {
    await _notify.setNotifyValue(enabled);
  }

  @override
  Future<void> write(List<int> value) =>
      _write.write(value, withoutResponse: false);
}
