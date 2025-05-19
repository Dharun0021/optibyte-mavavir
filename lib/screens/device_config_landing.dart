// lib/screens/device_config_landing.dart
import 'package:flutter/material.dart';

class LandingPage extends StatelessWidget {
  const LandingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final List<Map<String, String>> configItems = [
      {'label': 'Panel Number', 'value': '123654'},
      {'label': 'WiFi SSID', 'value': 'iAM-RnD'},
      {'label': 'WiFi PSWD', 'value': '1234567890'},
      {'label': 'DHCP', 'value': '0'},
      {'label': 'Device IP', 'value': '10.129.2.141'},
      {'label': 'Gateway', 'value': '10.129.2.1'},
      {'label': 'Subnet', 'value': '255.255.255.0'},
      {'label': 'DNS', 'value': '192.168.1.139'},
      {'label': 'AP Name', 'value': 'iESG-A1:6A:70'},
      {'label': 'AP PSWD', 'value': '12345678'},
      {'label': 'MQTT Server', 'value': '10.129.2.43'},
      {'label': 'MQTT Port', 'value': '1883'},
      {'label': 'MQTT Username', 'value': 'admin'},
      {'label': 'MQTT Password', 'value': 'admin123'},
      {'label': 'MQTT Keepalive', 'value': '60'},
      {'label': 'IR Repeat', 'value': '3'},
      {'label': 'AC Make Model', 'value': '10'},
      {'label': 'AC Mode', 'value': '1'},
      {'label': 'AC Speed', 'value': '2'},
      {'label': 'AC Swing', 'value': '1'},
      {'label': 'AC Temperature', 'value': '24'},
      {'label': 'IR FLAG', 'value': '1'},
      {'label': 'AHT2145C FLAG', 'value': '5'},
      {'label': 'HOSTNAME', 'value': 'ESP-IR-Blaster'},
      {'label': 'Slave ID', 'value': '1'},
      {'label': 'Baudrate', 'value': '9600'},
      {'label': 'Parity', 'value': ''},
      {'label': 'MQTT Base Path', 'value': 'IES/6A:70'},
      {'label': 'CHIP_ID', 'value': '28778'},
    ];

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.green),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Device Configurations', style: TextStyle(color: Colors.green)),
        backgroundColor: Color(0xFF252039),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(10),
              itemCount: configItems.length,
              itemBuilder: (context, index) {
                final item = configItems[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(item['label']!, style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      Expanded(
                        flex: 4,
                        child: TextFormField(
                          initialValue: item['value'],
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
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('All configurations submitted.'),
                    backgroundColor: Colors.green,
                  ),
                );
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
}
