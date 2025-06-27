// lib/screens/cloud_config_page.dart
import 'package:flutter/material.dart';
import 'dart:convert';

class CloudConfigPage extends StatefulWidget {
  const CloudConfigPage({super.key});

  @override
  State<CloudConfigPage> createState() => _CloudConfigPageState();
}

class _CloudConfigPageState extends State<CloudConfigPage> {
  // MQTT Config Controllers
  final brokerController = TextEditingController(text: 'mqtt.example.com');
  final portController = TextEditingController(text: '1883');
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();
  final topicController = TextEditingController(text: 'ac/control/command');

  // AC Config
  bool powerOn = true;
  double temperature = 24;
  bool swingOn = false;
  TimeOfDay? startTime;
  TimeOfDay? stopTime;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cloud Configuration', style: TextStyle(color: Colors.black)),
        backgroundColor: const Color(0xFF02CCFE),
        iconTheme: const IconThemeData(color: Colors.green),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          const Text('MQTT Broker Configuration', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _buildTextField('Broker URL', brokerController),
          _buildTextField('Port', portController, keyboardType: TextInputType.number),
          _buildTextField('Username', usernameController),
          _buildTextField('Password', passwordController, obscureText: true),
          _buildTextField('MQTT Topic', topicController),
          const SizedBox(height: 16),
          const Divider(),
          const Text('AC Configuration', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _buildToggle('Power', powerOn, (value) => setState(() => powerOn = value)),
          const SizedBox(height: 8),
          Text('Temperature: ${temperature.toInt()}°C'),
          Slider(
            value: temperature,
            min: 16,
            max: 30,
            divisions: 14,
            label: '${temperature.toInt()}',
            onChanged: (value) => setState(() => temperature = value),
          ),
          _buildToggle('Swing', swingOn, (value) => setState(() => swingOn = value)),
          const SizedBox(height: 8),
          _buildTimeSelector('Timer Start', startTime, (picked) {
            setState(() => startTime = picked);
          }),
          _buildTimeSelector('Timer Stop', stopTime, (picked) {
            setState(() => stopTime = picked);
          }),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _submitConfig,
            icon: const Icon(Icons.cloud_upload),
            label: const Text('Submit All'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              padding: const EdgeInsets.symmetric(vertical: 16.0),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller,
      {bool obscureText = false, TextInputType keyboardType = TextInputType.text}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _buildToggle(String label, bool value, Function(bool) onChanged) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }

  Widget _buildTimeSelector(String label, TimeOfDay? time, Function(TimeOfDay) onPicked) {
    return Row(
      children: [
        Expanded(child: Text('$label: ${time?.format(context) ?? "--:--"}')),
        ElevatedButton(
          onPressed: () async {
            TimeOfDay? picked = await showTimePicker(
              context: context,
              initialTime: TimeOfDay.now(),
            );
            if (picked != null) {
              onPicked(picked);
            }
          },
          child: const Text('Select'),
        ),
      ],
    );
  }

  void _submitConfig() {
    Map<String, dynamic> acCommand = {
      "brand": "Samsung", // This can be made dynamic later
      "power": powerOn ? "on" : "off",
      "temperature": temperature.toInt(),
      "swing": swingOn ? "on" : "off",
      "timer": {
        "start": startTime?.format(context) ?? "",
        "stop": stopTime?.format(context) ?? ""
      }
    };

    Map<String, dynamic> mqttConfig = {
      "broker": brokerController.text.trim(),
      "port": int.tryParse(portController.text.trim()) ?? 1883,
      "username": usernameController.text.trim(),
      "password": passwordController.text.trim(),
      "topic": topicController.text.trim(),
      "payload": acCommand
    };

    String payloadJson = jsonEncode(mqttConfig);
    print("Final Payload to Send via MQTT:");
    print(payloadJson);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Configuration submitted successfully.'),
        backgroundColor: Colors.green,
      ),
    );

    // TODO: Use mqtt_client to publish payloadJson to broker/topic
  }
}
