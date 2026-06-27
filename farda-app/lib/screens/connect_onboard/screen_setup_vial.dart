import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:farda/components/_components.dart';
import 'package:farda/theme.dart';
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

  @override
  void dispose() {
    _vialIdController.dispose();
    super.dispose();
  }

  Future<void> _startBleScan() async {
    try {
      await FlutterBluePlus.startScan(
        withNames: ["Medical Vial App"],
        timeout: const Duration(seconds: 4),
      );
    } catch (e) {
      debugPrint("Scan error: \$e");
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

  Future<void> triggerLogSync(List<int> authKey32Bytes) async {
    if (writeChar == null || readChar == null) return;

    await readChar!.setNotifyValue(true);
    String incomingDataBuffer = "";

    readChar!.lastValueStream.listen((value) {
      String chunk = utf8.decode(value);
      incomingDataBuffer += chunk;

      if (incomingDataBuffer.startsWith("SYNC_DATA") &&
          incomingDataBuffer.endsWith("]")) {
        String jsonStr = incomingDataBuffer.replaceFirst("SYNC_DATA", "");
        try {
          List<dynamic> logs = jsonDecode(jsonStr);
          debugPrint("Parsed Logs: \$logs");
          sendAckCommand(authKey32Bytes);
        } catch (e) {
          debugPrint("JSON Parse Error: \$e");
        }
      }
    });

    List<int> syncPayload = [0x30]; // REQUEST_SYNC Opcode
    syncPayload.addAll(authKey32Bytes);
    await writeChar!.write(syncPayload, withoutResponse: false);
  }

  Future<void> sendAckCommand(List<int> authKey32Bytes) async {
    if (writeChar == null) return;
    List<int> ackPayload = [0x31]; // ACK_SYNC Opcode
    ackPayload.addAll(authKey32Bytes);
    await writeChar!.write(ackPayload, withoutResponse: false);
    debugPrint("ACK sent, log should be deleted on device.");
  }

  Future<void> _handlePairAndSetup() async {
    // If manual entry is shown and user entered an ID, simply return that ID.
    if (_showManualEntry && _vialIdController.text.trim().isNotEmpty) {
      Navigator.pop(context, _vialIdController.text.trim());
      return;
    }

    // Check if Bluetooth is supported
    if (await FlutterBluePlus.isSupported == false) {
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
    if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
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
