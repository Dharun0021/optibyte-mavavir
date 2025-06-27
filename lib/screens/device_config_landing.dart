// lib/screens/device_config_landing.dart
import 'package:flutter/material.dart';
import 'cloud_config_page.dart';

class LandingPage extends StatelessWidget {
  const LandingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final List<Map<String, String>> configItems = [
      {'label': 'Panel Number', 'value': '123654'},
      {'label': 'WiFi SSID', 'value': 'iAM-RnD'},
      {'label': 'WiFi PSWD', 'value': '1234567890'},
    ];

    // Controllers for SSID and Password fields
    final TextEditingController ssidController = TextEditingController(text: configItems[1]['value']);
    final TextEditingController passwordController = TextEditingController(text: configItems[2]['value']);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.green),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Device Configurations', style: TextStyle(color: Colors.black)),
        backgroundColor: const Color(0xFF02CCFE),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(10),
              children: [
                _buildConfigRow('Panel Number', configItems[0]['value']!, enabled: false),
                _buildConfigRow('WiFi SSID', ssidController),
                _buildConfigRow('WiFi PSWD', passwordController, obscure: true),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton.icon(
              onPressed: () async {
                String ssid = ssidController.text;
                String password = passwordController.text;

                bool success = await sendToESP32(ssid, password);

                if (success) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CloudConfigPage()),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Failed to connect to ESP32'), backgroundColor: Colors.red),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 32.0),
              ),
              icon: const Icon(Icons.save),
              label: const Text('Submit All'),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildConfigRow(String label, dynamic value, {bool obscure = false, bool enabled = true}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 3,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          Expanded(
            flex: 4,
            child: value is TextEditingController
                ? TextFormField(
              controller: value,
              obscureText: obscure,
              enabled: enabled,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(vertical: 5, horizontal: 8),
              ),
            )
                : TextFormField(
              initialValue: value,
              enabled: false,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(vertical: 5, horizontal: 8),
              ),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () {},
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  Future<bool> sendToESP32(String ssid, String password) async {
    // Simulate sending to ESP32 via BLE or Serial
    print('Sending to ESP32: SSID=$ssid, Password=$password');
    await Future.delayed(const Duration(seconds: 2));
    return true; // simulate WiFi connected
  }
}

