import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:esp/screens/configuration_page.dart';

class BluetoothScannerPage extends StatefulWidget {
  const BluetoothScannerPage({super.key});

  @override
  State<BluetoothScannerPage> createState() => _BluetoothScannerPageState();
}

class _BluetoothScannerPageState extends State<BluetoothScannerPage> {
  bool _isScanning = false;
  final List<BluetoothDiscoveryResult> _devices = [];
  StreamSubscription<BluetoothDiscoveryResult>? _streamSubscription;

  @override
  void initState() {
    super.initState();
    _checkAndEnableBluetooth();
  }

  Future<void> _checkAndEnableBluetooth() async {
    final isEnabled = await FlutterBluetoothSerial.instance.isEnabled;
    if (!isEnabled!) {
      final result = await FlutterBluetoothSerial.instance.requestEnable();
      if (result ?? false) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ Bluetooth enabled")),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("❌ Bluetooth is required to proceed.")),
        );
      }
    }
  }

  void _startScan() async {
    final isEnabled = await FlutterBluetoothSerial.instance.isEnabled;
    if (!isEnabled!) {
      await _checkAndEnableBluetooth();
      return;
    }

    setState(() {
      _isScanning = true;
      _devices.clear();
    });

    _streamSubscription =
        FlutterBluetoothSerial.instance.startDiscovery().listen((result) {
      setState(() {
        final index = _devices.indexWhere((d) => d.device.address == result.device.address);
        if (index >= 0) {
          _devices[index] = result;
        } else {
          _devices.add(result);
        }
      });
    });

    _streamSubscription?.onDone(() {
      setState(() => _isScanning = false);
    });
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    try {
      final connection = await BluetoothConnection.toAddress(device.address);
      if (connection.isConnected && mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ConfigurationPage(
              connection: connection,
              device: device,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to connect to ${device.name ?? device.address}")),
        );
      }
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
        title: const Text("Bluetooth Scanner"),
        backgroundColor: Colors.lightBlue,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Center(
              child: ElevatedButton.icon(
                onPressed: _isScanning ? null : _startScan,
                icon: const Icon(Icons.search),
                label: Text(_isScanning ? "Scanning..." : "Scan"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.lightBlue,
                  minimumSize: const Size(180, 50),
                  textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 30),
            if (_devices.isNotEmpty)
              Expanded(
                child: ListView.builder(
                  itemCount: _devices.length,
                  itemBuilder: (context, index) {
                    final device = _devices[index].device;
                    return Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      child: ListTile(
                        leading: const Icon(Icons.bluetooth, color: Colors.lightBlue),
                        title: Text(device.name ?? "Unknown Device",
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(device.address),
                        trailing: ElevatedButton(
                          onPressed: () => _connectToDevice(device),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.lightBlue),
                          child: const Text("Connect"),
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
                    "No devices found yet. Click Scan.",
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
