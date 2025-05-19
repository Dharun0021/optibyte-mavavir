import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:esp/screens/ac_dashboard.dart';
import 'package:esp/service/bluetooth_service.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

class AcConfigurationPage extends StatefulWidget {
  final BluetoothConnection connection;
  const AcConfigurationPage({super.key, required this.connection});

  @override
  State<AcConfigurationPage> createState() => _AcConfigurationPageState();
}

class _AcConfigurationPageState extends State<AcConfigurationPage> {
  String? selectedModel;
  String? selectedMode;
  String? selectedFan;
  String? selectedTemp;
  String? selectedSwing;
  String? selectedState;

  final List<String> models = [
    'LG', 'Samsung', 'Daikin', 'Voltas', 'Hitachi', 'Blue Star', 'Carrier',
    'Whirlpool', 'Panasonic', 'Godrej', 'Mitsubishi', 'Haier', 'Toshiba',
    'IFB', 'Lloyd', 'Onida', 'Sansui', 'Videocon', 'Sanyo', 'Kelvinator',
  ];

  final List<String> modes = ['Cool', 'Heat', 'Dry', 'Auto'];
  final List<String> fans = ['Low', 'Medium', 'High'];
  final List<String> temps = ['16', '18', '20', '22', '24', '26', '28', '30'];
  final List<String> swings = ['On', 'Off'];
  final List<String> states = ['ON', 'OFF'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AC Control', style: TextStyle(color: Colors.green)),
        backgroundColor: const Color(0xFF252039),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.green),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("AC Control", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            buildDropdown("Select AC Model:", models, selectedModel, (val) => setState(() => selectedModel = val)),
            buildDropdown("Set Mode:", modes, selectedMode, (val) => setState(() => selectedMode = val)),
            buildDropdown("Set Fan Speed:", fans, selectedFan, (val) => setState(() => selectedFan = val)),
            buildDropdown("Set Temperature:", temps, selectedTemp, (val) => setState(() => selectedTemp = val)),
            buildDropdown("Set Swing:", swings, selectedSwing, (val) => setState(() => selectedSwing = val)),
            buildDropdown("Set State:", states, selectedState, (val) => setState(() => selectedState = val)),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                final payload = {
                  'type': 'standard',
                  'model': selectedModel,
                  'mode': selectedMode,
                  'fan': selectedFan,
                  'temp': selectedTemp,
                  'swing': selectedSwing,
                  'state': selectedState,
                };
                String jsonString = jsonEncode(payload);
                print('Sending to ESP32 via BT: $jsonString');

                try {
                  await BluetoothService().sendCommand("ac_config:$jsonString");
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to send config: $e')),
                  );
                }

                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AcDashboardPage(
                      model: selectedModel ?? '',
                      mode: selectedMode ?? '',
                      fan: selectedFan ?? '',
                      temp: selectedTemp ?? '',
                      swing: selectedSwing ?? '',
                      state: selectedState ?? '',
                    ),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 16.0),
              ),
              child: const Text("Submit"),
            )
          ],
        ),
      ),
    );
  }

  Widget buildDropdown(String label, List<String> items, String? selectedValue, Function(String?) onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.green),
              borderRadius: BorderRadius.circular(4),
            ),
            child: DropdownButton<String>(
              value: selectedValue,
              isExpanded: true,
              underline: Container(),
              items: items.map((item) => DropdownMenuItem(
                value: item,
                child: Text(item),
              )).toList(),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
