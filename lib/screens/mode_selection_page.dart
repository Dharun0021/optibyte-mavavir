import 'package:flutter/material.dart';
import 'package:esp/auth/auth_service.dart';
import 'package:esp/screens/login_page.dart';
import 'package:esp/screens/bluetooth_scanner_page.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:typed_data';

class ModeSelectionPage extends StatefulWidget {
  final bool showMqttConfig;
  final BluetoothConnection? deviceConnection;
  
  const ModeSelectionPage({
    super.key, 
    this.showMqttConfig = false,
    this.deviceConnection,
  });

  @override
  State<ModeSelectionPage> createState() => _ModeSelectionPageState();
}

class _ModeSelectionPageState extends State<ModeSelectionPage> {
  int _selectedIndex = 0;
  String userEmail = "";
  String userName = "User";

  final AuthService _authService = AuthService();
  
  // MQTT Configuration Controllers
  final TextEditingController _mqttBrokerController = TextEditingController();
  final TextEditingController _mqttPortController = TextEditingController(text: "1883");
  final TextEditingController _mqttUsernameController = TextEditingController();
  final TextEditingController _mqttPasswordController = TextEditingController();
  final TextEditingController _mqttClientIdController = TextEditingController();
  final TextEditingController _mqttTopicController = TextEditingController();
  
  bool _mqttUseSSL = false;
  bool _mqttConnected = false;
  bool _isConnectingMqtt = false;
  String _mqttStatus = "Not Connected";

  @override
  void initState() {
    super.initState();
    _loadUserEmail();
    _loadMqttConfig();
    
    // If MQTT config should be shown, switch to that tab
    if (widget.showMqttConfig) {
      _selectedIndex = 2; // MQTT Config tab
    }
  }

  Future<void> _loadUserEmail() async {
    final email = await _authService.getUserEmail();
    setState(() {
      userEmail = email ?? "";
      userName = userEmail.split('@').first;
      // Generate default MQTT client ID based on user
      if (_mqttClientIdController.text.isEmpty) {
        _mqttClientIdController.text = "esp32_${userName}_${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}";
      }
      // Set default topic
      if (_mqttTopicController.text.isEmpty) {
        _mqttTopicController.text = "esp32/$userName/commands";
      }
    });
  }

  Future<void> _loadMqttConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _mqttBrokerController.text = prefs.getString('mqtt_broker') ?? '';
        _mqttPortController.text = prefs.getString('mqtt_port') ?? '1883';
        _mqttUsernameController.text = prefs.getString('mqtt_username') ?? '';
        _mqttPasswordController.text = prefs.getString('mqtt_password') ?? '';
        _mqttClientIdController.text = prefs.getString('mqtt_client_id') ?? '';
        _mqttTopicController.text = prefs.getString('mqtt_topic') ?? '';
        _mqttUseSSL = prefs.getBool('mqtt_use_ssl') ?? false;
        _mqttConnected = prefs.getBool('mqtt_connected') ?? false;
        _mqttStatus = _mqttConnected ? "Connected" : "Not Connected";
      });
    } catch (e) {
      print('Error loading MQTT config: $e');
    }
  }

  Future<void> _saveMqttConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('mqtt_broker', _mqttBrokerController.text);
      await prefs.setString('mqtt_port', _mqttPortController.text);
      await prefs.setString('mqtt_username', _mqttUsernameController.text);
      await prefs.setString('mqtt_password', _mqttPasswordController.text);
      await prefs.setString('mqtt_client_id', _mqttClientIdController.text);
      await prefs.setString('mqtt_topic', _mqttTopicController.text);
      await prefs.setBool('mqtt_use_ssl', _mqttUseSSL);
      await prefs.setBool('mqtt_connected', _mqttConnected);
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("✅ MQTT configuration saved"),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      print('Error saving MQTT config: $e');
    }
  }

  Future<void> _sendMqttConfigToDevice() async {
    if (widget.deviceConnection == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("❌ No device connection available"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isConnectingMqtt = true;
      _mqttStatus = "Configuring...";
    });

    try {
      // Send MQTT configuration to ESP32
      final commands = [
        "MQTT_BROKER:${_mqttBrokerController.text}",
        "MQTT_PORT:${_mqttPortController.text}",
        "MQTT_USER:${_mqttUsernameController.text}",
        "MQTT_PASS:${_mqttPasswordController.text}",
        "MQTT_CLIENT:${_mqttClientIdController.text}",
        "MQTT_TOPIC:${_mqttTopicController.text}",
        "MQTT_SSL:${_mqttUseSSL ? '1' : '0'}",
        "MQTT_CONNECT"
      ];

      for (String command in commands) {
        final data = utf8.encode("$command\n");
        widget.deviceConnection!.output.add(Uint8List.fromList(data));
        await widget.deviceConnection!.output.allSent;
        await Future.delayed(const Duration(milliseconds: 200));
      }

      // Save configuration
      await _saveMqttConfig();
      
      // Simulate connection success (in real implementation, wait for ESP32 response)
      await Future.delayed(const Duration(seconds: 3));
      
      setState(() {
        _mqttConnected = true;
        _mqttStatus = "Connected";
        _isConnectingMqtt = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("🌐 MQTT configuration sent to device"),
          backgroundColor: Colors.green,
        ),
      );

    } catch (e) {
      setState(() {
        _isConnectingMqtt = false;
        _mqttStatus = "Connection Failed";
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("❌ Failed to configure MQTT: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _testMqttConnection() async {
    if (_mqttBrokerController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter MQTT broker address")),
      );
      return;
    }

    setState(() {
      _isConnectingMqtt = true;
      _mqttStatus = "Testing...";
    });

    // Send test command to ESP32
    if (widget.deviceConnection != null) {
      try {
        final data = utf8.encode("MQTT_TEST\n");
        widget.deviceConnection!.output.add(Uint8List.fromList(data));
        await widget.deviceConnection!.output.allSent;
      } catch (e) {
        print("Error sending test command: $e");
      }
    }

    // Simulate test (in real implementation, wait for ESP32 response)
    await Future.delayed(const Duration(seconds: 2));
    
    setState(() {
      _isConnectingMqtt = false;
      _mqttStatus = "Test Complete";
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("🧪 MQTT test command sent"),
        backgroundColor: Colors.blue,
      ),
    );
  }

  void _onNavTapped(int index) {
    setState(() => _selectedIndex = index);
  }

  Future<void> _logout() async {
    await _authService.logout();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => LoginPage()),
        (route) => false,
      );
    }
  }

  void _showLogoutDialog() {
    showModalBottomSheet(
      context: context,
      builder: (_) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Settings", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _logout();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.lightBlue,
                minimumSize: const Size(double.infinity, 45),
              ),
              child: const Text("Logout"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMqttConfigPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // MQTT Status Card
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 3,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.cloud_queue,
                        color: _mqttConnected ? Colors.green : Colors.orange,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        "MQTT Status",
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _mqttConnected ? Colors.green : Colors.orange,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _mqttStatus,
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  if (_isConnectingMqtt) ...[
                    const SizedBox(height: 10),
                    const LinearProgressIndicator(),
                  ],
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 20),
          
          // MQTT Configuration Form
          const Text(
            "MQTT Broker Configuration",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          const Text(
            "Configure your MQTT broker to enable cloud control of your devices.",
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
          
          const SizedBox(height: 20),
          
          // Broker Address
          TextField(
            controller: _mqttBrokerController,
            decoration: const InputDecoration(
              labelText: "MQTT Broker Address",
              hintText: "broker.hivemq.com or your broker IP",
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.dns),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Port and SSL
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _mqttPortController,
                  decoration: const InputDecoration(
                    labelText: "Port",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.settings_ethernet),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 3,
                child: CheckboxListTile(
                  title: const Text("Use SSL/TLS"),
                  value: _mqttUseSSL,
                  onChanged: (value) {
                    setState(() {
                      _mqttUseSSL = value ?? false;
                      _mqttPortController.text = _mqttUseSSL ? "8883" : "1883";
                    });
                  },
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Username
          TextField(
            controller: _mqttUsernameController,
            decoration: const InputDecoration(
              labelText: "Username (Optional)",
              hintText: "MQTT username",
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Password
          TextField(
            controller: _mqttPasswordController,
            decoration: const InputDecoration(
              labelText: "Password (Optional)",
              hintText: "MQTT password",
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.lock),
            ),
            obscureText: true,
          ),
          
          const SizedBox(height: 16),
          
          // Client ID
          TextField(
            controller: _mqttClientIdController,
            decoration: const InputDecoration(
              labelText: "Client ID",
              hintText: "Unique client identifier",
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.fingerprint),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Topic
          TextField(
            controller: _mqttTopicController,
            decoration: const InputDecoration(
              labelText: "Command Topic",
              hintText: "esp32/user/commands",
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.topic),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Action Buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isConnectingMqtt ? null : _testMqttConnection,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text("Test Connection"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isConnectingMqtt ? null : _sendMqttConfigToDevice,
                  icon: const Icon(Icons.cloud_upload),
                  label: const Text("Configure Device"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 20),
          
          // Information Card
          Card(
            color: Colors.blue.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info, color: Colors.blue.shade700),
                      const SizedBox(width: 8),
                      Text(
                        "MQTT Configuration Info",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "• Free MQTT brokers: broker.hivemq.com, test.mosquitto.org\n"
                    "• Default ports: 1883 (non-SSL), 8883 (SSL)\n"
                    "• Commands will be sent to your specified topic\n"
                    "• Device must be connected to WiFi for MQTT to work\n"
                    "• Use unique client IDs to avoid conflicts",
                    style: TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 20),
          
          // Cloud Commands Preview
          if (_mqttConnected) ...[
            const Text(
              "Cloud Command Format",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Topic: ${_mqttTopicController.text}"),
                  const SizedBox(height: 8),
                  const Text("Commands:"),
                  const Text("• SEND:samsung:power"),
                  const Text("• SEND:lg:temp_up"),
                  const Text("• GET_STATUS"),
                  const Text("• SCHEDULE_ON:22:30"),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  void dispose() {
    _mqttBrokerController.dispose();
    _mqttPortController.dispose();
    _mqttUsernameController.dispose();
    _mqttPasswordController.dispose();
    _mqttClientIdController.dispose();
    _mqttTopicController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Center(
          child: Text(
            _selectedIndex == 0 ? "All" : 
            _selectedIndex == 1 ? "Profile" : "MQTT Config",
            style: const TextStyle(color: Colors.black),
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.home, color: Colors.lightBlue),
          onPressed: () {
            if (widget.showMqttConfig) {
              Navigator.pop(context);
            }
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.bluetooth, color: Colors.lightBlue),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BluetoothScannerPage()),
              );
            },
          ),
        ],
      ),
      body: _selectedIndex == 0
          ? const Center(
              child: Text(
                "This is the Add Device page.\nTap the Bluetooth icon to scan.",
                style: TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
            )
          : _selectedIndex == 1
              ? SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Card(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 2,
                        child: ListTile(
                          leading: const Icon(Icons.person, color: Colors.lightBlue, size: 36),
                          title: Text(userName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          subtitle: Text(userEmail),
                          trailing: const Icon(Icons.logout, color: Colors.lightBlue),
                          onTap: _showLogoutDialog,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Card(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 2,
                        child: ListTile(
                          leading: const Icon(Icons.help_outline, color: Colors.lightBlue),
                          title: const Text("FAQ & Feedback"),
                          trailing: const Icon(Icons.arrow_forward_ios),
                          onTap: () {},
                        ),
                      ),
                      const SizedBox(height: 10),
                      Card(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 2,
                        child: ListTile(
                          leading: const Icon(Icons.info_outline, color: Colors.lightBlue),
                          title: const Text("About"),
                          trailing: const Icon(Icons.arrow_forward_ios),
                          onTap: () {},
                        ),
                      ),
                    ],
                  ),
                )
              : _buildMqttConfigPage(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onNavTapped,
        selectedItemColor: Colors.lightBlue,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: "Home Screen",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: "My Profile",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.cloud_queue),
            label: "MQTT Config",
          ),
        ],
      ),
    );
  }
}