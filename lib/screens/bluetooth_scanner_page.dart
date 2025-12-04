import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:esp/screens/configuration_page.dart';

class BluetoothScannerPage extends StatefulWidget {
  const BluetoothScannerPage({super.key});

  @override
  State<BluetoothScannerPage> createState() => _BluetoothScannerPageState();
}

class _BluetoothScannerPageState extends State<BluetoothScannerPage> {
  bool _isScanning = false;
  List<BluetoothDiscoveryResult> _devices = [];
  StreamSubscription<BluetoothDiscoveryResult>? _streamSubscription;

  // NEW: connecting state
  bool _isConnecting = false;
  String? _connectingAddress; // which device is being connected

  @override
  void initState() {
    super.initState();
    _initialSetup();
  }

  Future<void> _initialSetup() async {
    await _checkAndRequestPermissions();
    await _checkAndEnableBluetooth();
  }

  /// Ask for Bluetooth + Location permissions (required for scanning).
  Future<void> _checkAndRequestPermissions() async {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    bool allGranted = true;
    for (final entry in statuses.entries) {
      if (entry.value.isDenied || entry.value.isPermanentlyDenied) {
        allGranted = false;
      }
    }

    if (!allGranted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Bluetooth & Location permissions are required for scanning.',
          ),
        ),
      );
    }
  }

  /// Ensure Bluetooth is ON.
  Future<void> _checkAndEnableBluetooth() async {
    bool? isEnabled = await FlutterBluetoothSerial.instance.isEnabled;

    if (isEnabled != true) {
      final result = await FlutterBluetoothSerial.instance.requestEnable();
      if (result == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Bluetooth enabled')),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❌ Bluetooth is required to proceed.')),
        );
      }
    }
  }

  /// Start scanning for nearby Bluetooth devices.
  void _startScan() async {
    // Re-check permissions in case user changed in settings
    final btScanStatus = await Permission.bluetoothScan.status;
    final btConnectStatus = await Permission.bluetoothConnect.status;
    final locStatus = await Permission.location.status;

    if (!btScanStatus.isGranted ||
        !btConnectStatus.isGranted ||
        !locStatus.isGranted) {
      await _checkAndRequestPermissions();
      return;
    }

    final isEnabled = await FlutterBluetoothSerial.instance.isEnabled;
    if (isEnabled != true) {
      await _checkAndEnableBluetooth();
      return;
    }

    // Cancel any existing discovery before starting a new one
    await _streamSubscription?.cancel();

    setState(() {
      _isScanning = true;
      _devices.clear();
    });

    try {
      _streamSubscription =
          FlutterBluetoothSerial.instance.startDiscovery().listen((result) {
        setState(() {
          final index =
              _devices.indexWhere((d) => d.device.address == result.device.address);
          if (index >= 0) {
            _devices[index] = result;
          } else {
            _devices.add(result);
          }
        });
      });

      _streamSubscription?.onDone(() {
        if (mounted) {
          setState(() => _isScanning = false);
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isScanning = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start scan: $e')),
        );
      }
    }
  }

  /// Connect to a selected device and open ConfigurationPage.
  Future<void> _connectToDevice(BluetoothDevice device) async {
    // UI: show "connecting" state for this device
    setState(() {
      _isConnecting = true;
      _connectingAddress = device.address;
    });

    // Optional: show toast that connection is starting
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Connecting to ${device.name ?? device.address}...'),
        duration: const Duration(seconds: 2),
      ),
    );

    try {
      // Discovery should be stopped before attempting connection
      await FlutterBluetoothSerial.instance.cancelDiscovery();
      await _streamSubscription?.cancel();
      setState(() => _isScanning = false);

      final connection = await BluetoothConnection.toAddress(device.address);

      if (!mounted) return;

      // Clear connecting state
      setState(() {
        _isConnecting = false;
        _connectingAddress = null;
      });

      if (connection.isConnected) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ConfigurationPage(
              connection: connection,
              device: device,
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to connect to ${device.name ?? device.address}',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isConnecting = false;
        _connectingAddress = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to connect to ${device.name ?? device.address}\n$e',
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _streamSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bluetooth Scanner'),
        backgroundColor: Colors.lightBlue,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Center(
              child: ElevatedButton.icon(
                onPressed: (_isScanning || _isConnecting) ? null : _startScan,
                icon: const Icon(Icons.search),
                label: Text(_isScanning ? 'Scanning...' : 'Scan'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.lightBlue,
                  minimumSize: const Size(180, 50),
                  textStyle: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 30),
            if (_devices.isNotEmpty)
              Expanded(
                child: ListView.builder(
                  itemCount: _devices.length,
                  itemBuilder: (context, index) {
                    final result = _devices[index];
                    final device = result.device;

                    final bool isThisConnecting =
                        _isConnecting && _connectingAddress == device.address;

                    return Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListTile(
                        leading: const Icon(
                          Icons.bluetooth,
                          color: Colors.lightBlue,
                        ),
                        title: Text(
                          device.name ?? 'Unknown Device',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(device.address),
                        trailing: isThisConnecting
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : ElevatedButton(
                                onPressed: _isConnecting
                                    ? null
                                    : () => _connectToDevice(device),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.lightBlue,
                                ),
                                child: const Text('Connect'),
                              ),
                      ),
                    );
                  },
                ),
              )
            else if (!_isScanning)
              const Expanded(
                child: Center(
                  child: Text(
                    'No devices found yet. Click Scan.',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              )
            else
              const Expanded(
                child: Center(
                  child: CircularProgressIndicator(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
