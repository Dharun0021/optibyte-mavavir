import 'package:flutter/material.dart';
import 'package:esp/screens/device_config_landing.dart';
import 'package:esp/screens/ac_landing_page.dart';
import 'package:esp/service.dart';
import 'package:esp/service/bluetooth_service.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

class ConfigurationPage extends StatelessWidget {
  final BluetoothConnection connection;
  final BluetoothService bluetoothService;

  const ConfigurationPage({
    super.key,
    required this.connection,
    required this.bluetoothService,
  });

  Future<void> _disconnectAndNavigate(BuildContext context) async {
    try {
      // Properly close Bluetooth connection
      if (bluetoothService.connection != null &&
          bluetoothService.connection!.isConnected) {
        await bluetoothService.disconnect();
      }

      // Show feedback
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Bluetooth disconnected")),
      );

      // Navigate back to Bluetooth scan page (HomePage)
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const HomePage()),
            (Route<dynamic> route) => false,
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error during disconnect: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Configuration Page", style: TextStyle(color: Colors.green)),
        backgroundColor: const Color(0xFF252039),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.green),
          onPressed: () => _disconnectAndNavigate(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.bluetooth_disabled, color: Colors.red),
            tooltip: 'Disconnect',
            onPressed: () => _disconnectAndNavigate(context), // ✅ disconnect properly
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.settings),
              label: const Text("Device Configuration", style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 20.0),
                backgroundColor: Colors.green,
                textStyle: const TextStyle(fontSize: 18),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const LandingPage()),
                );
              },
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.ac_unit),
              label: const Text("AC Configuration", style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 20.0),
                backgroundColor: Colors.blueAccent,
                textStyle: const TextStyle(fontSize: 18),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AcConfigurationPage(connection: connection),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
