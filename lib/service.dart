import 'dart:async';
import 'package:esp/auth/auth_service.dart';
import 'package:esp/screens/history/history_entry.dart';
import 'package:esp/screens/history/history_page.dart';
import 'package:esp/screens/history/history_service.dart';
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
  final TextEditingController _voltageController = TextEditingController();
  final TextEditingController _ampereController = TextEditingController();
  bool isVoltageCooldown = false;
  bool isAmpereCooldown = false;
  Timer? voltageCooldownTimer;
  Timer? ampereCooldownTimer;
  bool isResetCooldown = false;
  Timer? resetCooldownTimer;

  // Added constants for validation
  static const double MIN_VOLTAGE = 10.0;
  static const double MAX_VOLTAGE = 55.0;
  static const double MIN_AMPERE = 0.0;
  static const double MAX_AMPERE = 115.0;
  String? connectedDeviceName;
  final HistoryService _historyService = HistoryService();

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
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 3),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showSuccess(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 2),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _handleReceivedData(String data) {
    if (mounted) {
      setState(() {
        receivedData = data;
      });
    }
  }

  void _handleDisconnection() {
    if (mounted) {
      setState(() {
        receivedData = '';
        connectingAddress = null;
      });
    }
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
        if (mounted) {
          setState(() {
            devices = updatedDevices;
          });
        }
      },
      onDone: () {
        if (mounted) {
          setState(() {
            isScanning = false;
          });
        }
      },
      onError: (error) {
        if (mounted) {
          setState(() {
            isScanning = false;
          });
          _showError('Scan failed: $error');
        }
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
      connectedDeviceName =
          device.name ?? 'Unknown Device'; // Store device name
    });

    try {
      await _bluetoothService.connectToDevice(device);
    } finally {
      if (mounted) {
        setState(() {
          connectingAddress = null;
        });
      }
    }
  }

  void _startVoltageCooldown() {
    setState(() {
      isVoltageCooldown = true;
    });

    voltageCooldownTimer?.cancel();
    voltageCooldownTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() {
          isVoltageCooldown = false;
        });
      }
    });
  }

  void _startAmpereCooldown() {
    setState(() {
      isAmpereCooldown = true;
    });

    ampereCooldownTimer?.cancel();
    ampereCooldownTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() {
          isAmpereCooldown = false;
        });
      }
    });
  }

// reset
  void _startResetCooldown() {
    setState(() {
      isResetCooldown = true;
    });

    resetCooldownTimer?.cancel();
    resetCooldownTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() {
          isResetCooldown = false;
        });
      }
    });
  }

  Future<void> sendReset() async {
    try {
      await _bluetoothService.sendCommand('reset');
      await _historyService.addEntry(HistoryEntry(
        action: 'Reset',
        value: 'System Reset',
        timestamp: DateTime.now(),
        deviceName: connectedDeviceName ?? 'Unknown Device',
      ));
      _voltageController.clear();
      _ampereController.clear();

      _startResetCooldown();
      _showSuccess('Reset command sent');
    } catch (e) {
      _showError('Failed to send reset command');
    }
  }

  Future<void> sendVoltage(String voltageStr) async {
    try {
      double voltage = double.parse(voltageStr);
      if (voltage < MIN_VOLTAGE || voltage > MAX_VOLTAGE) {
        _showError('Voltage must be between $MIN_VOLTAGE and $MAX_VOLTAGE');
        return;
      }
      await _bluetoothService.sendCommand('voltage=$voltage');
      await _historyService.addEntry(HistoryEntry(
        action: 'Voltage',
        value: '$voltage V',
        timestamp: DateTime.now(),
        deviceName: connectedDeviceName ?? 'Unknown Device',
      ));
      // _voltageController.clear();
      _startVoltageCooldown();
      _showSuccess('Voltage command sent: $voltage');
    } catch (e) {
      if (e is FormatException) {
        _showError('Please enter a valid number');
      } else {
        _showError('Failed to send voltage command');
      }
    }
  }

  Future<void> sendAmpere(String ampereStr) async {
    try {
      double ampere = double.parse(ampereStr);
      if (ampere < MIN_AMPERE || ampere > MAX_AMPERE) {
        _showError('Current must be between $MIN_AMPERE and $MAX_AMPERE');
        return;
      }
      await _bluetoothService.sendCommand('amperage=$ampere');
      await _historyService.addEntry(HistoryEntry(
        action: 'Current',
        value: '$ampere A',
        timestamp: DateTime.now(),
        deviceName: connectedDeviceName ?? 'Unknown Device',
      ));
      // _ampereController.clear();
      _startAmpereCooldown();
      _showSuccess('Current command sent: $ampere');
    } catch (e) {
      if (e is FormatException) {
        _showError('Please enter a valid number');
      } else {
        _showError('Failed to send Current command');
      }
    }
  }
  Future<void> _showDisconnectConfirmation(BuildContext context) async {
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Disconnect'),
          content: const Text('Are you sure you want to disconnect?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Disconnect'),
            ),
          ],
        );
      },
    );

    if (result == true) {
      await disconnect();
    }
  }

  Future<void> disconnect() async {
    await _bluetoothService.disconnect();
    _showSuccess('Disconnected');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Color(0xFF252039), // Dark blue background #252039
        title: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundImage: AssetImage('assets/images/submark.png'),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: const Text(
                'FUSIONBYTE',
                style: TextStyle(
                  color: Colors.green,
                  // FusionByte green
                  fontFamily: 'Arial',
                  // Changed to a different font family
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  // Slightly smaller text
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
          if (_bluetoothService.connection != null)
            IconButton(
              icon: const Icon(Icons.history, color: Colors.white),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => HistoryPage(
                      deviceName: connectedDeviceName,
                      showDeviceOnly: true,
                    ),
                  ),
                );
              },
            )
          else
            IconButton(
              icon: const Icon(Icons.history, color: Colors.white),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const HistoryPage(),
                  ),
                );
              },
            ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            // White logout icon
            onPressed: () async {
              final shouldLogout = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Logout'),
                  content: const Text('Are you sure you want to logout?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Logout'),
                    ),
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
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(4.0),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20.0),
                topRight: Radius.circular(20.0),
              ),
            ),
            height: 4.0,
          ),
        ),
      ),

      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                if (_bluetoothService.connection == null) ...[
                  ElevatedButton.icon(
                    onPressed: isScanning ? null : startScan,
                    icon: const Icon(Icons.search),
                    label:
                        Text(isScanning ? 'Scanning...' : 'Scan for Devices'),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.6,
                    child: devices.isEmpty
                        ? Center(
                            child: Text(
                              isScanning
                                  ? 'Searching for devices...'
                                  : 'No devices found. Tap Scan to search.',
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            physics: const AlwaysScrollableScrollPhysics(),
                            itemCount: devices.length,
                            itemBuilder: (context, index) {
                              final device = devices[index];
                              final isConnectingToThisDevice =
                                  connectingAddress == device.address;

                              return Card(
                                child: ListTile(
                                  leading: const Icon(
                                    Icons.bluetooth,
                                    color: Colors.blue,
                                  ),
                                  title: Text(device.name ?? 'Unknown Device'),
                                  subtitle: Text(device.address),
                                  trailing: ElevatedButton(
                                    onPressed: isConnectingToThisDevice
                                        ? null
                                        : () => connectToDevice(device),
                                    child: Text(isConnectingToThisDevice
                                        ? 'Connecting...'
                                        : 'Connect'),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ] else ...[
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.bluetooth_connected,
                          color: Colors.green),
                      title: Text(
                          'Connected to: ${connectedDeviceName ?? 'Unknown'}'), // Show connected device name
                      subtitle: Text(_bluetoothService.isConnected
                          ? 'Connected'
                          : 'Disconnected'),
                      trailing: ElevatedButton(
                        onPressed: () => _showDisconnectConfirmation(context),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red
                        ),
                        child: const Text('Disconnect'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Added range information text
                  // Padding(
                  //   padding: const EdgeInsets.symmetric(vertical: 8.0),
                  //   child: Text(
                  //     'Valid ranges: Voltage ($MIN_VOLTAGE-$MAX_VOLTAGE V), Current ($MIN_AMPERE-$MAX_AMPERE A)',
                  //     style: TextStyle(
                  //       fontWeight: FontWeight.bold,
                  //       color: Colors.blue[700],
                  //     ),
                  //   ),
                  // ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: _voltageController,
                            enabled: !isVoltageCooldown,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Enter Voltage',
                              helperText: 'Range: $MIN_VOLTAGE-$MAX_VOLTAGE V',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            onPressed: !isVoltageCooldown
                                ? () => sendVoltage(_voltageController.text)
                                : null,
                            icon: const Icon(Icons.send),
                            label: const Text('Send Voltage'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: _ampereController,
                            enabled: !isAmpereCooldown,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Enter Current',
                              helperText: 'Range: $MIN_AMPERE-$MAX_AMPERE A',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            onPressed: !isAmpereCooldown
                                ? () => sendAmpere(_ampereController.text)
                                : null,
                            icon: const Icon(Icons.send),
                            label: const Text('Send Current'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Card(
                  //   child: Padding(
                  //     padding: const EdgeInsets.all(16.0),
                  //     child: Column(
                  //       crossAxisAlignment: CrossAxisAlignment.start,
                  //       children: [
                  //         const Text(
                  //           'Received Data:',
                  //           style: TextStyle(fontWeight: FontWeight.bold),
                  //         ),
                  //         const SizedBox(height: 8),
                  //         Text(receivedData.isEmpty
                  //             ? 'No data received'
                  //             : receivedData),
                  //       ],
                  //     ),
                  //   ),
                  // ),
                ],
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: _bluetoothService.connection != null
          ? SizedBox(
              width: 56, // Slightly bigger than small
              height: 56, // Slightly bigger than small
              child: FloatingActionButton(
                onPressed: !isResetCooldown ? sendReset : null,
                backgroundColor: Colors.red,
                tooltip: 'Reset',
                child: const Icon(Icons.refresh,
                    color: Colors.white, size: 28), // Slightly bigger icon
              ),
            )
          : null, // Hide button if not connected
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    voltageCooldownTimer?.cancel();
    ampereCooldownTimer?.cancel();
    _bluetoothService.dispose();
    _voltageController.dispose();
    _ampereController.dispose();
    super.dispose();
  }
}
