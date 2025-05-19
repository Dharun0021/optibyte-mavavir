import 'dart:async';
import 'package:esp/auth/auth_service.dart';
import 'package:esp/screens/configuration_page.dart';
import 'package:esp/screens/history/history_page.dart';
import 'package:esp/service/bluetooth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final BluetoothService _bluetoothService = BluetoothService();
  StreamSubscription<List<BluetoothDevice>>? _scanSubscription;
  List<BluetoothDevice> devices = [];
  String? connectingAddress;
  bool isScanning = false;
  String receivedData = '';
  String? connectedDeviceName;

  @override
  void initState() {
    super.initState();
    _initBluetooth();
  }

  Future<void> _initBluetooth() async {
    _bluetoothService.onError = _showError;
    _bluetoothService.onSuccess = _showSuccess;
    _bluetoothService.onDataReceived = _handleReceivedData;
    _bluetoothService.onDisconnected = _handleDisconnection;
    await _bluetoothService.initialize();
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    }
  }

  void _showSuccess(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.green),
      );
    }
  }

  void _handleReceivedData(String data) {
    debugPrint("📥 Received: $data");
    setState(() {
      receivedData = data;
    });
  }

  void _handleDisconnection() {
    debugPrint("⚠️ Bluetooth Disconnected");
    setState(() {
      connectingAddress = null;
      connectedDeviceName = null;
      devices = [];
    });
  }

  Future<void> startScan() async {
    if (isScanning) return;

    setState(() {
      devices.clear();
      isScanning = true;
    });

    _scanSubscription?.cancel();
    _scanSubscription = _bluetoothService.startScan().listen(
          (List<BluetoothDevice> updatedDevices) {
        setState(() {
          devices = updatedDevices;
        });
      },
      onDone: () {
        setState(() {
          isScanning = false;
        });
      },
      onError: (error) {
        setState(() => isScanning = false);
        _showError('Scan failed: $error');
      },
    );
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    if (connectingAddress != null || _bluetoothService.isConnected) {
      _showError('Already connected or connecting to a device.');
      return;
    }

    setState(() {
      connectingAddress = device.address;
      connectedDeviceName = device.name ?? 'Unknown Device';
    });

    try {
      await _bluetoothService.connectToDevice(device);

      if (_bluetoothService.isConnected && _bluetoothService.activeConnection != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ConfigurationPage(
              connection: _bluetoothService.activeConnection!,
              bluetoothService: _bluetoothService,
            ),
          ),
        );
      } else {
        _showError("Connection not available. Please retry.");
      }
    } finally {
      setState(() => connectingAddress = null);
    }
  }

  Future<void> _showDisconnectConfirmation(BuildContext context) async {
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Disconnect'),
        content: const Text('Are you sure you want to disconnect?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Disconnect')),
        ],
      ),
    );

    if (result == true) {
      await _bluetoothService.disconnect();
      _showSuccess('Disconnected');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF252039),
        title: Row(
          children: [
            const CircleAvatar(
              radius: 20,
              backgroundImage: AssetImage('assets/images/submark.png'),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'IR-BLASTER',
                style: TextStyle(
                  color: Colors.green,
                  fontFamily: 'Arial',
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ],
        ),
        actions: [
          if (isScanning)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(color: Colors.white),
            ),
          IconButton(
            icon: const Icon(Icons.history, color: Colors.white),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => HistoryPage(
                    deviceName: connectedDeviceName,
                    showDeviceOnly: _bluetoothService.connection != null,
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () async {
              final shouldLogout = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Logout'),
                  content: const Text('Are you sure you want to logout?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                    TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Logout')),
                  ],
                ),
              );

              if (shouldLogout == true && mounted) {
                await AuthService().logout();
                await _bluetoothService.disconnect();
                Navigator.of(context).pushReplacementNamed('/login');
              }
            },
          ),
          const SizedBox(width: 8),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(4.0),
          child: Divider(
            color: Colors.white,
            thickness: 4,
            indent: 0,
            endIndent: 0,
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              ElevatedButton.icon(
                onPressed: isScanning ? null : startScan,
                icon: const Icon(Icons.search),
                label: Text(isScanning ? 'Scanning...' : 'Scan for Devices'),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: devices.isEmpty
                    ? Center(
                  child: Text(
                    isScanning ? 'Searching for devices...' : 'No devices found. Tap Scan to search.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                )
                    : ListView.builder(
                  itemCount: devices.length,
                  itemBuilder: (context, index) {
                    final device = devices[index];
                    final isConnecting = connectingAddress == device.address;

                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.bluetooth, color: Colors.blue),
                        title: Text(device.name ?? 'Unknown Device'),
                        subtitle: Text(device.address),
                        trailing: ElevatedButton(
                          onPressed: isConnecting ? null : () => connectToDevice(device),
                          child: Text(isConnecting ? 'Connecting...' : 'Connect'),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _bluetoothService.dispose();
    super.dispose();
  }
}
