import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

class ACRemotePage extends StatefulWidget {
  final BluetoothConnection connection;
  final String brand;
  final BluetoothDevice device;

  const ACRemotePage({
    super.key,
    required this.connection,
    required this.brand,
    required this.device,
  });

  @override
  State<ACRemotePage> createState() => _ACRemotePageState();
}

class _ACRemotePageState extends State<ACRemotePage> {
  late BluetoothConnection _connection;
  String _temperature = '--';
  final List<String> _log = [];

  @override
  void initState() {
    super.initState();
    _connection = widget.connection;
    _connection.input?.listen(_onDataReceived);
  }

  void _onDataReceived(Uint8List data) {
    final text = utf8.decode(data).trim();
    setState(() {
      _log.insert(0, text);
    });

    if (text.startsWith("TEMP:")) {
      setState(() {
        _temperature = text.replaceFirst("TEMP:", "").trim();
      });
    }
  }

  Future<void> _sendCommand(String command) async {
    if (!_connection.isConnected) return;
    try {
      final data = utf8.encode("$command\n");
      _connection.output.add(Uint8List.fromList(data));
      await _connection.output.allSent;
      setState(() {
        _log.insert(0, "You: $command");
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Send failed: $e")),
      );
    }
  }

  Widget _buildControlButton(String label, String command, IconData icon) {
    return ElevatedButton.icon(
      onPressed: () => _sendCommand(command),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.lightBlue[100],
        foregroundColor: Colors.black,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      icon: Icon(icon, size: 24),
      label: Text(label, style: const TextStyle(fontSize: 16)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text("AC Remote - ${widget.brand}"),
        backgroundColor: Colors.blueAccent,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Room Temperature: $_temperature °C",
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 20,
              runSpacing: 20,
              children: [
                _buildControlButton("Power", "SEND:POWER", Icons.power_settings_new),
                _buildControlButton("Temp +", "SEND:TEMP_UP", Icons.arrow_upward),
                _buildControlButton("Temp -", "SEND:TEMP_DOWN", Icons.arrow_downward),
                _buildControlButton("Mode", "SEND:MODE", Icons.settings),
                _buildControlButton("Swing", "SEND:SWING", Icons.swap_vert),
              ],
            ),
            const SizedBox(height: 30),
            const Text("Command Log:", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Expanded(
              child: ListView.builder(
                itemCount: _log.length,
                reverse: true,
                itemBuilder: (context, index) => ListTile(
                  title: Text(_log[index]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
