import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:farda/application/device/sync/dose_log_parser.dart';
import 'package:farda/application/device/sync/vial_sync_service.dart';
import 'package:farda/components/_components.dart';
import 'package:farda/theme.dart';
import 'package:farda/utilities/ble_permissions.dart';
import 'package:farda/utilities/logger_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class ScreenConnectOnboard extends StatefulWidget {
  const ScreenConnectOnboard({super.key});

  @override
  State<ScreenConnectOnboard> createState() => _ScreenConnectOnboardState();
}

class _ScreenConnectOnboardState extends State<ScreenConnectOnboard> {
  final TextEditingController _vialIdController = TextEditingController();

  BluetoothCharacteristic? writeChar;
  BluetoothCharacteristic? readChar;
  BluetoothDevice? connectedDevice;
  bool _showManualEntry = false;

  /// App-side dose-log sync → parse → upload → buffer/retry pipeline (GTM-514).
  final VialSyncService _syncService = VialSyncService();

  /// Accumulates BLE notify chunks until a full `SYNC_DATA[...]` frame arrives.
  String _incomingDataBuffer = "";
  StreamSubscription<List<int>>? _syncSub;

  @override
  void dispose() {
    _syncSub?.cancel();
    _vialIdController.dispose();
    super.dispose();
  }

  Future<void> _startBleScan() async {
    try {
      // On Android 12+ / iOS, flutter_blue_plus prompts the user for the
      // BLUETOOTH_SCAN / BLUETOOTH_CONNECT (and pre-Android-12 location)
      // runtime permissions here, the first time a scan is started. The
      // matching declarations live in AndroidManifest.xml and Info.plist.
      await FlutterBluePlus.startScan(
        withNames: ["Medical Vial App"],
        timeout: const Duration(seconds: 4),
      );
    } catch (e) {
      debugPrint("Scan error: $e");
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await device.connect();

      if (Platform.isAndroid) {
        await device.requestMtu(512);
      }

      connectedDevice = device;
      await _discoverPillBottleServices(device);

      // GTM-514: kick off the dose-log sync now that we're connected and the
      // read/write characteristics are discovered. Fire-and-forget so it never
      // blocks the connect UX; results (parse → upload) are buffered/retried by
      // [VialSyncService]. authKey is the device session key the firmware
      // expects on the REQUEST_SYNC opcode — HARDWARE-dependent; see
      // [_authKeyForDevice]. Failures here are non-fatal to pairing.
      unawaited(_runLogSync(device));

      setState(() {
        _vialIdController.text = device.remoteId.str;
      });

      if (mounted) {
        Navigator.pop(context); // Hide loading dialog
        
        // Return the connected device ID to the previous screen (e.g. prescription add screen)
        Navigator.pop(context, device.remoteId.str); 
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Hide loading
        setState(() {
          _showManualEntry = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text("Failed to connect: \$e. You can enter the ID manually.")),
        );
      }
    }
  }

  Future<void> _discoverPillBottleServices(BluetoothDevice device) async {
    List<BluetoothService> services = await device.discoverServices();
    for (BluetoothService service in services) {
      if (service.uuid.toString().toUpperCase().contains("00FF") ||
          service.uuid.toString().toUpperCase().contains("00EE")) {
        for (BluetoothCharacteristic c in service.characteristics) {
          if (c.properties.write || c.properties.writeWithoutResponse) {
            writeChar = c;
          }
          if (c.properties.notify || c.properties.read) {
            readChar = c;
          }
        }
      }
    }
  }

  /// Drives the on-connect dose-log sync for [device] (GTM-514).
  ///
  /// HARDWARE FLAG: every BLE byte here (REQUEST_SYNC write, the `SYNC_DATA`
  /// notify stream, the ACK write) needs a real vial + firmware (GTM-513) to
  /// validate end-to-end. The parse → upload → buffer/retry it feeds is pure
  /// app-side plumbing and is unit-tested.
  Future<void> _runLogSync(BluetoothDevice device) async {
    try {
      await triggerLogSync(_authKeyForDevice(device));
    } catch (e) {
      Log.e("VialSync: log sync failed for ${device.remoteId.str}", error: e);
    }
  }

  /// The 32-byte device session/auth key the firmware expects appended to the
  /// REQUEST_SYNC / ACK opcodes.
  ///
  /// HARDWARE/SECURITY FLAG: the real key is provisioned with the device (A3,
  /// docs/DEVICE_AUTH.md) and is NOT yet wired into the app's secure storage —
  /// that handshake is part of the on-device BLE task (GTM-513). Until then we
  /// pass a deterministic placeholder so the plumbing compiles and can be
  /// exercised; a real handshake must replace this before shipping.
  List<int> _authKeyForDevice(BluetoothDevice device) {
    final seed = utf8.encode(device.remoteId.str);
    return List<int>.generate(32, (i) => seed.isEmpty ? 0 : seed[i % seed.length]);
  }

  Future<void> triggerLogSync(List<int> authKey32Bytes) async {
    if (writeChar == null || readChar == null) return;

    final String deviceId = connectedDevice?.remoteId.str ?? "";

    await readChar!.setNotifyValue(true);
    _incomingDataBuffer = "";

    await _syncSub?.cancel();
    _syncSub = readChar!.lastValueStream.listen((value) {
      // Firmware streams the framed `SYNC_DATA[...]` payload in MTU-sized
      // chunks; accumulate until the frame is complete (parse logic is pure +
      // unit-tested in [DoseLogParser]).
      _incomingDataBuffer += utf8.decode(value);

      if (DoseLogParser.isComplete(_incomingDataBuffer)) {
        final buffer = _incomingDataBuffer;
        _incomingDataBuffer = "";
        unawaited(_onSyncFrameComplete(buffer, deviceId, authKey32Bytes));
      }
    });

    List<int> syncPayload = [0x30]; // REQUEST_SYNC Opcode
    syncPayload.addAll(authKey32Bytes);
    await writeChar!.write(syncPayload, withoutResponse: false);
  }

  /// Parse → upload → buffer/retry the completed sync frame, and only ACK
  /// (clear the on-device log) when every event is durably relayed.
  Future<void> _onSyncFrameComplete(
    String buffer,
    String deviceId,
    List<int> authKey32Bytes,
  ) async {
    try {
      final result = await _syncService.handleSyncBuffer(buffer, deviceId);
      if (result.fullyFlushed) {
        // Safe to delete the device-side log: nothing is left pending upload.
        await sendAckCommand(authKey32Bytes);
      } else {
        // Some events are still buffered (offline / 5xx). Keep the device log
        // intact and let the next sync retry the queue before ACKing.
        Log.w(
          "VialSync: ${result.retryable} event(s) still pending; "
          "skipping ACK so device log is preserved.",
        );
      }
    } catch (e) {
      Log.e("VialSync: handling sync frame failed", error: e);
    }
  }

  Future<void> sendAckCommand(List<int> authKey32Bytes) async {
    if (writeChar == null) return;
    List<int> ackPayload = [0x31]; // ACK_SYNC Opcode
    ackPayload.addAll(authKey32Bytes);
    await writeChar!.write(ackPayload, withoutResponse: false);
    Log.i("VialSync: ACK sent, device log cleared.");
  }

  Future<void> _handlePairAndSetup() async {
    // If manual entry is shown and user entered an ID, simply return that ID.
    if (_showManualEntry && _vialIdController.text.trim().isNotEmpty) {
      Navigator.pop(context, _vialIdController.text.trim());
      return;
    }

    // Check if Bluetooth is supported
    final readiness = await BlePermissions.check();
    if (readiness == BleReadiness.unsupported) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Bluetooth is not supported on this device.")),
        );
        setState(() {
          _showManualEntry = true;
        });
      }
      return;
    }

    // Check if Bluetooth is turned on
    if (readiness == BleReadiness.bluetoothOff) {
      try {
        if (Platform.isAndroid) {
          await FlutterBluePlus.turnOn();
          // Wait briefly for adapter to turn on
          await Future.delayed(const Duration(milliseconds: 500));
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Please turn on Bluetooth in settings.")),
            );
          }
          return;
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Could not turn on Bluetooth.")),
          );
          setState(() {
            _showManualEntry = true;
          });
        }
        return;
      }
    }

    // Double check that it is actually on now before proceeding
    if (FlutterBluePlus.adapterStateNow == BluetoothAdapterState.on) {
      _showScanModal();
    } else {
       if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Bluetooth is still off.")),
        );
      }
    }
  }

  void _showScanModal() {
    _startBleScan();

    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.all(16.r),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Scanning for Bluetooth Devices...",
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              16.verticalSpace,
              StreamBuilder<bool>(
                stream: FlutterBluePlus.isScanning,
                initialData: false,
                builder: (context, snapshot) {
                  if (snapshot.data == true) {
                    return const CircularProgressIndicator();
                  }
                  return const SizedBox.shrink();
                },
              ),
              16.verticalSpace,
              SizedBox(
                height: 300.h,
                child: StreamBuilder<List<ScanResult>>(
                  stream: FlutterBluePlus.scanResults,
                  initialData: const [],
                  builder: (context, snapshot) {
                    final results = snapshot.data ?? [];
                    if (results.isEmpty) {
                      return const Center(child: Text("No devices found yet."));
                    }
                    return ListView.separated(
                      itemCount: results.length,
                      separatorBuilder: (context, index) => const Divider(),
                      itemBuilder: (context, index) {
                        final device = results[index].device;
                        final deviceId = device.remoteId.str;
                        final deviceName = device.platformName.isNotEmpty
                            ? device.platformName
                            : "Unknown Device";
                        return ListTile(
                          leading: Icon(
                            Icons.bluetooth,
                            color: Theme.of(context).primaryColor,
                          ),
                          title: Text(deviceName),
                          subtitle: Text(deviceId),
                          onTap: () async {
                            FlutterBluePlus.stopScan();
                            Navigator.pop(context); // Close bottom sheet
                            await _connectToDevice(device);
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    ).whenComplete(() {
      FlutterBluePlus.stopScan();
      if (connectedDevice == null) {
        setState(() {
          _showManualEntry = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FardaColors>()!;
    final spacing = theme.extension<Spacing>()!;
    return ExtendedScaffold(
      appBar: CustomAppBar(
        titleType: AppBarTitleType.text,
        titleText: "Connect Your farda.",
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: spacing.horizontalDefault,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              16.verticalSpace,
              TextMedium(
                text:
                    "Connect your farda. Medicine Vial. Connect your vial to the charger. Please make sure that Bluetooth is enabled on your device.",
              ),
              SizedBox(
                height: 0.4.sh,
                child: Center(
                  child: Image.asset("assets/images/vial_bottle.png"),
                ),
              ),
              16.verticalSpace,

              if (_showManualEntry) ...[
                // Vial ID Field
                Text(
                  "Enter Vial ID",
                  style: theme.textTheme.titleMedium?.merge(
                    TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                8.verticalSpace,
                TextField(
                  controller: _vialIdController,
                  decoration: InputDecoration(
                    hintText: "e.g. VIAL-12345",
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12.r),
                      borderSide: BorderSide(color: colors.slate.shade300),
                    ),
                    prefixIcon: const Icon(Icons.qr_code_scanner),
                  ),
                ),
                24.verticalSpace,
              ],

              ButtonPrimary(
                text: "Pair & Setup Vial",
                onClick: _handlePairAndSetup,
              ),
              12.verticalSpace,
              TextButton(
                onPressed: () {
                  Navigator.pop(context); // Optional: you can pass null or empty string to indicate skip
                },
                child: Text(
                  "Skip",
                  style: TextStyle(
                    color: colors.slate.shade600,
                    fontWeight: FontWeight.w600,
                    fontSize: 16.sp,
                  ),
                ),
              ),
              16.verticalSpace,
            ],
          ),
        ),
      ),
    );
  }
}
