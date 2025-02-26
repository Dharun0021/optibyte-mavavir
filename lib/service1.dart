import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}
class VoltageCalculator {
  static final List<(double, double)> voltageData = [
    (15.1, 0.0),    // Starting point
    (17.0, 30.0),   // +30 degrees
    (23.4, 60.0),   // +30 degrees
    (28.4, 90.0),   // +30 degrees
    (32.9, 120.0),  // +30 degrees
    (36.8, 150.0),  // +30 degrees
    (40.1, 180.0),  // +30 degrees
    (42.9, 210.0),  // +30 degrees
    (46.0, 240.0),  // +30 degrees
    (47.9, 270.0),  // +30 degrees
    (50.1, 300.0)   // Final point
  ];


  static double? calculateDegree(double voltage) {
    for (int i = 0; i < voltageData.length - 1; i++) {
      var v1 = voltageData[i].$1;
      var theta1 = voltageData[i].$2;
      var v2 = voltageData[i + 1].$1;
      var theta2 = voltageData[i + 1].$2;

      if (v1 <= voltage && voltage <= v2) {
        double ratio = (voltage - v1) / (v2 - v1);
        double degree = theta1 + (ratio * (theta2 - theta1));
        return double.parse(degree.toStringAsFixed(3)); // Increased precision to 3 decimal places
      }
    }
    return null;
  }
}

// AmpereCalculator class with floating point values
class AmpereCalculator {
  static final List<(double, double)> ampereData = [
    (0.0, 0.0),     // Starting point
    (30.0, 11.0),   // First point
    (60.0, 31.0),   // Second point
    (90.0, 45.0),   // Third point
    (120.0, 59.0),  // Fourth point
    (150.0, 68.0),  // Fifth point
    (180.0, 74.0),  // Sixth point
    (210.0, 84.0),  // Seventh point
    (240.0, 91.0),  // Eighth point
    (270.0, 102.0),  // Ninth point
    (300.0, 108.0), // Tenth point
  ];

  static double? calculateAmpere(double degree) {
    for (int i = 0; i < ampereData.length - 1; i++) {
      var theta1 = ampereData[i].$1;
      var a1 = ampereData[i].$2;
      var theta2 = ampereData[i + 1].$1;
      var a2 = ampereData[i + 1].$2;

      if (theta1 <= degree && degree <= theta2) {
        double ratio = (degree - theta1) / (theta2 - theta1);
        double ampere = a1 + (ratio * (a2 - a1));
        return double.parse(ampere.toStringAsFixed(3)); // Increased precision to 3 decimal places
      }
    }
    return null;
  }
}


class _HomePageState extends State<HomePage> {
  FlutterBluetoothSerial bluetooth = FlutterBluetoothSerial.instance;
  List<BluetoothDevice> devices = [];
  BluetoothConnection? connection;
  String? connectingAddress;
  bool isScanning = false;
  String receivedData = '';
  final TextEditingController _voltageController = TextEditingController();
  final TextEditingController _ampereController = TextEditingController();
  StreamSubscription<Uint8List>? dataSubscription;
  bool isConnecting = false;
  Timer? timeoutTimer;

  double? initial_voltage;
  double? final_degree;
  double? initial_degree;

  double? final_voltage;
  double? initial_ampere;
  double? final_ampere;
  bool isFirstVoltage = true;
  bool isFirstAmpere = true;
  // Add cooldown states
  bool isVoltageCooldown = false;
  bool isAmpereCooldown = false;
  Timer? voltageCooldownTimer;
  Timer? ampereCooldownTimer;

  @override
  void initState() {
    super.initState();
    _initBluetooth();
  }

  Future<void> _initBluetooth() async {
    try {
      for (var permission in [
        Permission.bluetooth,
        Permission.bluetoothConnect,
        Permission.bluetoothScan,
        Permission.bluetoothAdvertise,
        Permission.location
      ]) {
        if (await permission.isDenied) {
          await permission.request();
        }
      }

      bool? isEnabled = await bluetooth.isEnabled;
      if (isEnabled != true) {
        await bluetooth.requestEnable();
      }
    } catch (e) {
      print('Init Bluetooth error: $e');
      _showError(
          'Please enable Bluetooth manually and grant required permissions.');
    }
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

  Future<void> startScan() async {
    if (isScanning) return;

    setState(() {
      devices.clear();
      isScanning = true;
    });

    try {
      bool? isEnabled = await bluetooth.isEnabled;
      if (isEnabled != true) {
        await bluetooth.requestEnable();
      }

      List<BluetoothDevice> bondedDevices = await bluetooth.getBondedDevices();
      setState(() {
        devices = bondedDevices;
      });

      bluetooth.startDiscovery().listen(
            (BluetoothDiscoveryResult result) {
          final device = result.device;
          if (mounted) {
            setState(() {
              final existingIndex =
              devices.indexWhere((d) => d.address == device.address);
              if (existingIndex >= 0) {
                devices[existingIndex] = device;
              } else {
                devices.add(device);
              }
            });
          }
        },
        onDone: () {
          if (mounted) {
            setState(() {
              isScanning = false;
            });
            _showSuccess('Scan completed: ${devices.length} devices found');
          }
        },
        onError: (error) {
          print('Discovery error: $error');
          if (mounted) {
            setState(() {
              isScanning = false;
            });
            _showError('Scan failed: $error');
          }
        },
        cancelOnError: true,
      );

      await Future.delayed(const Duration(seconds: 30));
      bluetooth.cancelDiscovery();
      if (mounted && isScanning) {
        setState(() {
          isScanning = false;
        });
      }
    } catch (e) {
      print('Scan error: $e');
      if (mounted) {
        setState(() {
          isScanning = false;
        });
        _showError('Scan failed: $e');
      }
    }
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    if (isConnecting || connection?.isConnected == true) {
      _showError('Already connected or connecting to a device.');
      return;
    }

    setState(() {
      isConnecting = true;
      connectingAddress = device.address;
    });

    try {
      connection = await BluetoothConnection.toAddress(device.address)
          .timeout(const Duration(seconds: 8), onTimeout: () {
        throw TimeoutException('Connection timed out');
      });

      if (connection != null && connection!.isConnected) {
        _setupDataListener();
        _showSuccess('Connected to ${device.name ?? "device"}');

        // Send initial values
        await sendInitialCommands();

        // Reset tracking variables
        setState(() {
          initial_voltage = null;
          final_voltage = null;
          initial_ampere = null;
          final_ampere = null;
          isFirstVoltage = true;
          isFirstAmpere = true;
        });
      } else {
        throw Exception('Connection failed to establish');
      }
    } catch (e) {
      print('Connection error: $e');
      _showError('Failed to connect: $e');
      await _cleanupConnection();
    } finally {
      if (mounted) {
        setState(() {
          isConnecting = false;
          connectingAddress = null;
        });
      }
    }
  }

  Future<void> sendInitialCommands() async {
    try {
      // Send initial voltage command
      connection!.output.add(Uint8List.fromList(utf8.encode('v cw 300\r\n')));
      await connection!.output.allSent;

      // Wait briefly between commands
      await Future.delayed(const Duration(seconds: 5));

      // Send initial ampere command
      connection!.output.add(Uint8List.fromList(utf8.encode('a cw 300\r\n')));
      await connection!.output.allSent;

      print('Initial commands sent successfully');
    } catch (e) {
      print('Error sending initial commands: $e');
      _showError('Failed to send initial commands');
    }
  }

  void _setupDataListener() {
    dataSubscription?.cancel();

    dataSubscription = connection!.input!.listen(
          (Uint8List data) {
        String receivedString = utf8.decode(data);
        if (mounted) {
          setState(() {
            receivedData = receivedString;
          });
        }
        print('Received: $receivedString');
      },
      onError: (error) {
        print('Data receive error: $error');
        _handleConnectionError();
      },
      onDone: () {
        print('Device disconnected');
        _handleConnectionError();
      },
      cancelOnError: true,
    );
  }

  // Add cooldown management functions
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

  Future<void> sendVoltage(String voltageStr) async {
    if (connection?.isConnected != true) {
      _showError('Not connected to any device');
      return;
    }

    try {
      double voltage = double.parse(voltageStr);
      double? degree = VoltageCalculator.calculateDegree(voltage);

      if (degree == null) {
        _showError('Voltage is out of valid range (14.4V - 50.1V)');
        return;
      }

      String command;
      if (isFirstVoltage) {
        initial_voltage = voltage;
        initial_degree = degree;
        command = 'v acw ${degree.toStringAsFixed(3)}'; // Increased precision
        isFirstVoltage = false;
      } else {
        final_voltage = voltage;
        final_degree = degree;

        double degreeDifference = (final_degree! - initial_degree!);
        String formattedDifference = degreeDifference.abs().toStringAsFixed(3);

        command = degreeDifference < 0 ? 'v cw $formattedDifference' : 'v acw $formattedDifference';

        initial_voltage = final_voltage;
        initial_degree = final_degree;
      }

      final commandBytes = utf8.encode('$command\r\n');
      connection!.output.add(Uint8List.fromList(commandBytes));
      await connection!.output.allSent;
      print('commandBytes: $commandBytes (commandBytes)');
      print('Sent: $command (Voltage: ${voltage.toStringAsFixed(3)}V, Degree: ${degree.toStringAsFixed(3)}°)');
      _voltageController.clear();
      _startVoltageCooldown();
      _showSuccess('Command sent - Degree: ${degree.toStringAsFixed(3)}°');
    } catch (e) {
      if (e is FormatException) {
        _showError('Please enter a valid number');
      } else {
        print('Send voltage error: $e');
        _showError('Failed to send voltage command');
      }
    }
  }

  Future<void> sendAmpere(String ampereStr) async {
    if (connection?.isConnected != true) {
      _showError('Not connected to any device');
      return;
    }

    try {
      double ampere = double.parse(ampereStr);
      double? degree = null;

      for (int i = 0; i < AmpereCalculator.ampereData.length - 1; i++) {
        var a1 = AmpereCalculator.ampereData[i].$2;
        var theta1 = AmpereCalculator.ampereData[i].$1;
        var a2 = AmpereCalculator.ampereData[i + 1].$2;
        var theta2 = AmpereCalculator.ampereData[i + 1].$1;

        if (a1 <= ampere && ampere <= a2) {
          double ratio = (ampere - a1) / (a2 - a1);
          degree = theta1 + (ratio * (theta2 - theta1));
          degree = double.parse(degree.toStringAsFixed(3)); // Increased precision
          break;
        }
      }

      if (degree == null) {
        _showError('Ampere value out of valid range (9.0A - 108.0A)');
        return;
      }

      String command;
      if (isFirstAmpere) {
        initial_ampere = degree;
        command = 'a acw ${degree.toStringAsFixed(3)}';
        isFirstAmpere = false;
      } else {
        final_ampere = degree;
        double difference = final_ampere! - initial_ampere!;
        String formattedDifference = difference.abs().toStringAsFixed(3);

        command = difference < 0 ? 'a cw $formattedDifference' : 'a acw $formattedDifference';
        initial_ampere = final_ampere;
      }

      connection!.output.add(Uint8List.fromList(utf8.encode('$command\r\n')));
      await connection!.output.allSent;

      print('Sent: $command (Ampere: ${ampere.toStringAsFixed(3)}A, Degree: ${degree.toStringAsFixed(3)}°)');
      _ampereController.clear();
      _startAmpereCooldown();
      _showSuccess('Ampere command sent - Degree: ${degree.toStringAsFixed(3)}°');
    } catch (e) {
      if (e is FormatException) {
        _showError('Please enter a valid number');
      } else {
        print('Send ampere error: $e');
        _showError('Failed to send ampere command');
      }
    }
  }


  Future<void> _cleanupConnection() async {
    try {
      await dataSubscription?.cancel();
      await connection?.finish();
      await connection?.close();
    } catch (e) {
      print('Cleanup error: $e');
    } finally {
      connection = null;
      dataSubscription = null;
    }
  }

  void _handleConnectionError() async {
    await _cleanupConnection();
    if (mounted) {
      setState(() {
        receivedData = '';
        connectingAddress = null;
        isConnecting = false;
        connection = null;
      });
      _showError('Connection lost');
    }
  }

  Future<void> disconnect() async {
    await _cleanupConnection();
    if (mounted) {
      setState(() {
        receivedData = '';
        connectingAddress = null;
        isConnecting = false;
      });
      _showSuccess('Disconnected');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PMEL TECH'),
        actions: [
          if (isScanning)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(color: Colors.white),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            if (connection == null) ...[
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
                    isScanning
                        ? 'Searching for devices...'
                        : 'No devices found. Tap Scan to search.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                )
                    : ListView.builder(
                  itemCount: devices.length,
                  itemBuilder: (context, index) {
                    final device = devices[index];
                    final isConnectingToThisDevice =
                        connectingAddress == device.address;

                    return Card(
                      child: ListTile(
                        leading: Icon(
                          device.bondState == BluetoothBondState.bonded
                              ? Icons.bluetooth_connected
                              : Icons.bluetooth,
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
                  title: const Text('Connected Device'),
                  subtitle: Text(
                      connection!.isConnected ? 'Connected' : 'Disconnected'),
                  trailing: ElevatedButton(
                    onPressed: disconnect,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                    ),
                    child: const Text('Disconnect'),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Voltage Control
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
                          labelText: 'Voltage (14.4V - 50.1V)',
                          border: const OutlineInputBorder(),
                          helperText: initial_voltage != null
                              ? 'Current voltage: ${initial_voltage!.toString()} V ' +
                              (VoltageCalculator.calculateDegree(initial_voltage!)?.toStringAsFixed(2) ?? 'N/A') + '°'
                              : 'Enter first voltage value',
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
              // Ampere Control
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
                          labelText: 'Ampere',
                          border: const OutlineInputBorder(),
                          helperText: initial_ampere != null
                              ? 'Current ampere: ${initial_ampere!.toString()}'
                              : 'Enter first ampere value',
                        ),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: !isAmpereCooldown
                            ? () => sendAmpere(_ampereController.text)
                            : null,
                        icon: const Icon(Icons.send),
                        label: const Text('Send Ampere'),
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Received Data:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(receivedData.isEmpty
                          ? 'No data received'
                          : receivedData),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    timeoutTimer?.cancel();
    voltageCooldownTimer?.cancel();
    ampereCooldownTimer?.cancel();
    _cleanupConnection();
    _voltageController.dispose();
    _ampereController.dispose();
    super.dispose();
  }
}
