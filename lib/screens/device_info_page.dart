import 'package:flutter/material.dart';

class DeviceInfoPage extends StatelessWidget {
  const DeviceInfoPage({super.key});

  @override
  Widget build(BuildContext context) {
    final Map<String, String> info = {
      'Model': '16WMDIR',
      'Version': '1.02',
      'Release Date': 'Mar-10-2025',
      'Release Time': '15:51:40',
      'MAC Address': 'C8:2E:18:A1:6A:70',
      'STA Status': '0',
      'STA IP Address': '0.0.0.0',
      'Devices connected': '0',
      'MQTT Status': '0',
      'MQTT Client Id': 'IES-706AA1182EC8'
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text("Device and Network Information"),
        backgroundColor: const Color(0xFF252039),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: info.entries.map((entry) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      entry.key,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 4,
                    child: TextField(
                      readOnly: true,
                      controller: TextEditingController(text: entry.value),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
