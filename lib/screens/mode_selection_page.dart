import 'dart:convert';
import 'dart:typed_data';

import 'package:esp/auth/auth_service.dart';
import 'package:esp/screens/bluetooth_scanner_page.dart';
import 'package:esp/screens/login_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:mqtt_client/mqtt_client.dart' as mqtt;
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  int _selectedIndex = 2; // Default to MQTT tab when opened from Config
  String userEmail = "";
  String userName = "user";

  final AuthService _authService = AuthService();

  // MQTT basic config – ONLY THESE 5 FIELDS
  final TextEditingController _mqttIpController =
      TextEditingController(text: "13.66.130.236");
  final TextEditingController _mqttPortController =
      TextEditingController(text: "1883");
  final TextEditingController _mqttUsernameController =
      TextEditingController(text: "whirlpoolindia");
  final TextEditingController _mqttPasswordController =
      TextEditingController(text: "whirl@123");
  final TextEditingController _mqttTopicController =
      TextEditingController(text: "whirlpoolindia");

  bool _mqttConnected = false;
  bool _isConnectingMqtt = false;
  String _mqttStatus = "Not Connected";

  // Device-side flags (set by ConfigurationPage)
  bool _remoteConfigured = false;
  bool _wifiConnected = false;
  String _wifiSsid = "";

  // Telemetry from cloud
  String _currentTemp = "--";
  String _acStatus = "UNKNOWN";

  // Setpoint controllers
  final TextEditingController _coolOffController =
      TextEditingController(text: "25");
  final TextEditingController _coolOnController =
      TextEditingController(text: "28");

  // MQTT client (for app → cloud)
  MqttServerClient? _mqttClient;
  final List<String> _mqttMessages = [];

  @override
  void initState() {
    super.initState();
    _initPage();
  }

  Future<void> _initPage() async {
    await _loadUserEmail();
    await _loadFlagsAndMqttConfig();

    if (!widget.showMqttConfig) {
      _selectedIndex = 0;
    }

    setState(() {});
  }

  Future<void> _loadUserEmail() async {
    final email = await _authService.getUserEmail();
    setState(() {
      userEmail = email ?? "";
      userName =
          userEmail.isNotEmpty ? userEmail.split('@').first : "user";
    });
  }

  Future<void> _loadFlagsAndMqttConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      setState(() {
        _remoteConfigured =
            prefs.getBool('remote_configured') ?? false;
        _wifiConnected = prefs.getBool('wifi_connected') ?? false;
        _wifiSsid = prefs.getString('wifi_ssid') ?? "";

        _mqttIpController.text =
            prefs.getString('mqtt_ip') ?? _mqttIpController.text;
        _mqttPortController.text =
            prefs.getString('mqtt_port') ?? _mqttPortController.text;
        _mqttUsernameController.text =
            prefs.getString('mqtt_username') ??
                _mqttUsernameController.text;
        _mqttPasswordController.text =
            prefs.getString('mqtt_password') ??
                _mqttPasswordController.text;
        _mqttTopicController.text =
            prefs.getString('mqtt_topic') ?? _mqttTopicController.text;
        _mqttConnected =
            prefs.getBool('mqtt_connected') ?? false;
        _mqttStatus = _mqttConnected ? "Connected" : "Not Connected";
      });
    } catch (e) {
      debugPrint("Error loading flags/MQTT config: $e");
    }
  }

  Future<void> _saveMqttConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('mqtt_ip', _mqttIpController.text.trim());
      await prefs.setString(
          'mqtt_port', _mqttPortController.text.trim());
      await prefs.setString('mqtt_username',
          _mqttUsernameController.text.trim());
      await prefs.setString('mqtt_password',
          _mqttPasswordController.text.trim());
      await prefs.setString(
          'mqtt_topic', _mqttTopicController.text.trim());
      await prefs.setBool('mqtt_connected', _mqttConnected);
    } catch (e) {
      debugPrint("Error saving MQTT config: $e");
    }
  }

  // ======================================================================
  //  MQTT JSON – EXACT FORMAT
  //  {
  //    "ip": "13.66.130.236",
  //    "port": 1883,
  //    "username": "whirlpoolindia",
  //    "password": "whirl@123",
  //    "topic": "whirlpoolindia"
  //  }
  // ======================================================================
  Map<String, dynamic> _buildMqttJson() {
    final port = int.tryParse(_mqttPortController.text.trim()) ?? 1883;
    return {
      "ip": _mqttIpController.text.trim(),
      "port": port,
      "username": _mqttUsernameController.text.trim(),
      "password": _mqttPasswordController.text.trim(),
      "topic": _mqttTopicController.text.trim(),
    };
  }

  // ======================================================================
  //  WIFI RECONNECT ON DEVICE (USING STORED CREDENTIALS)
  //  We only allow this if remote is configured.
  //  Command expected by ESP32 firmware: "WIFI_RECONNECT\n"
  // ======================================================================
  Future<void> _requestWifiReconnectOnDevice() async {
    if (!_remoteConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              "⚠️ Remote not configured in device.\nConfigure remote first in Configuration page."),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (widget.deviceConnection == null ||
        !(widget.deviceConnection!.isConnected)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text("❌ Bluetooth device not connected."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      final cmd = "WIFI_RECONNECT\n";
      widget.deviceConnection!.output
          .add(Uint8List.fromList(utf8.encode(cmd)));
      await widget.deviceConnection!.output.allSent;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              "📶 Requested WiFi reconnect on device (using stored credentials)."),
          backgroundColor: Colors.blue,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("❌ Failed to request WiFi reconnect: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ======================================================================
  //  MQTT APP → CLOUD CONNECT (ONLY AFTER REMOTE + WIFI)
  // ======================================================================
  Future<void> _connectToMqttBroker() async {
    if (!_remoteConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              "⚠️ Remote not configured in device.\nConfigure remote first."),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (!_wifiConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              "📶 WiFi not connected on device.\nConnect WiFi from Configuration page or use Reconnect WiFi."),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final cfg = _buildMqttJson();

    if (cfg["ip"].toString().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please enter MQTT IP"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isConnectingMqtt = true;
      _mqttStatus = "Connecting...";
    });

    try {
      final brokerIp = cfg["ip"] as String;
      final brokerPort = cfg["port"] as int;
      final username = cfg["username"] as String;
      final password = cfg["password"] as String;

      final clientId =
          "app_${userName}_${DateTime.now().millisecondsSinceEpoch}";

      _mqttClient?.disconnect();
      _mqttClient = MqttServerClient(brokerIp, clientId);
      _mqttClient!
        ..logging(on: false)
        ..port = brokerPort
        ..keepAlivePeriod = 20
        ..secure = false
        ..autoReconnect = true
        ..onDisconnected = _onMqttDisconnected;

      final connMess = mqtt.MqttConnectMessage()
          .withClientIdentifier(clientId)
          .startClean()
          .withWillQos(mqtt.MqttQos.atLeastOnce);

      _mqttClient!.connectionMessage = connMess;

      if (username.isNotEmpty) {
        await _mqttClient!.connect(username, password);
      } else {
        await _mqttClient!.connect();
      }

      if (_mqttClient!.connectionStatus?.state ==
          mqtt.MqttConnectionState.connected) {
        // SUBSCRIBE to telemetry: "<topic>/telemetry"
        final baseTopic = _mqttTopicController.text.trim();
        final telemetryTopic = "$baseTopic/telemetry";

        _mqttClient!.updates?.listen(
            (List<mqtt.MqttReceivedMessage<mqtt.MqttMessage>> c) {
          final recMess = c[0].payload as mqtt.MqttPublishMessage;
          final pt = mqtt.MqttPublishPayload.bytesToStringAsString(
              recMess.payload.message);

          setState(() {
            _mqttMessages.insert(0, "${c[0].topic}: $pt");
            if (_mqttMessages.length > 50) {
              _mqttMessages.removeLast();
            }
          });

          // Parse telemetry JSON
          try {
            final data = jsonDecode(pt);
            if (data is Map) {
              if (data["temp"] != null) {
                setState(() {
                  _currentTemp = data["temp"].toString();
                });
              }
              if (data["ac_state"] != null) {
                setState(() {
                  _acStatus = data["ac_state"].toString();
                });
              }
            }
          } catch (_) {
            // ignore parse errors
          }
        });

        _mqttClient!
            .subscribe(telemetryTopic, mqtt.MqttQos.atLeastOnce);

        setState(() {
          _mqttConnected = true;
          _mqttStatus = "Connected";
          _isConnectingMqtt = false;
        });

        await _saveMqttConfig();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  "✅ Connected to MQTT broker.\nSubscribed to $telemetryTopic"),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        throw Exception(
            "MQTT connection failed: ${_mqttClient!.connectionStatus}");
      }
    } catch (e) {
      debugPrint("MQTT connect error: $e");
      setState(() {
        _mqttConnected = false;
        _mqttStatus = "Connection Failed";
        _isConnectingMqtt = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("❌ MQTT connection failed: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _onMqttDisconnected() {
    debugPrint("MQTT disconnected");
    if (mounted) {
      setState(() {
        _mqttConnected = false;
        _mqttStatus = "Disconnected";
      });
    }
  }

  // ======================================================================
  //  SEND EXACT JSON TO ESP32 OVER BLUETOOTH
  //  Command:  MQTT:{"ip":"...","port":1883,"username":"...","password":"...","topic":"..."}
  //  ESP32 uses this JSON to connect to cloud and push temp/AC state every 30 sec
  // ======================================================================
  Future<void> _sendMqttJsonToDevice() async {
    if (!_remoteConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              "⚠️ Remote not configured.\nPlease configure remote before MQTT."),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (!_wifiConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              "📶 WiFi not connected on device.\nConnect WiFi first."),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (widget.deviceConnection == null ||
        !(widget.deviceConnection!.isConnected)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text("❌ Bluetooth device not connected."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final cfg = _buildMqttJson();
    if (cfg["ip"].toString().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please enter MQTT IP"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      final jsonString = jsonEncode(cfg);
      final command = "MQTT:$jsonString\n";

      widget.deviceConnection!.output
          .add(Uint8List.fromList(utf8.encode(command)));
      await widget.deviceConnection!.output.allSent;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              "📡 MQTT JSON sent to device:\n$jsonString"),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              "❌ Failed to send MQTT JSON to device: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ======================================================================
  //  PUBLISH SETPOINT & AC ON/OFF COMMANDS TO CLOUD
  //  – ESP32 then reads from cloud and controls AC + publishes status
  // ======================================================================
  Future<void> _publishSetpoint() async {
    if (!_mqttConnected || _mqttClient == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text("Connect Cloud MQTT first."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final topic = _mqttTopicController.text.trim();
    final coolOff = double.tryParse(_coolOffController.text) ?? 25;
    final coolOn = double.tryParse(_coolOnController.text) ?? 28;

    final payload = {
      "cmd": "SETPOINT",
      "cool_off": coolOff,
      "cool_on": coolOn,
    };

    final builder = mqtt.MqttClientPayloadBuilder();
    builder.addString(jsonEncode(payload));

    try {
      _mqttClient!.publishMessage(
        topic,
        mqtt.MqttQos.atLeastOnce,
        builder.payload!,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              "🎯 Setpoint sent: OFF at $coolOff°C, ON at $coolOn°C"),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text("❌ Setpoint publish failed: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _publishAcCommand(String cmd) async {
    if (!_mqttConnected || _mqttClient == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text("Connect Cloud MQTT first."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final topic = _mqttTopicController.text.trim();
    final payload = {"cmd": cmd};

    final builder = mqtt.MqttClientPayloadBuilder();
    builder.addString(jsonEncode(payload));

    try {
      _mqttClient!.publishMessage(
        topic,
        mqtt.MqttQos.atLeastOnce,
        builder.payload!,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("📤 $cmd sent to cloud"),
          backgroundColor:
              cmd == "AC_ON" ? Colors.green : Colors.redAccent,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text("❌ $cmd publish failed: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ======================================================================
  //  UI & NAV
  // ======================================================================
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
            const Text("Settings",
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
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
    final jsonPreview = const JsonEncoder.withIndent('  ')
        .convert(_buildMqttJson());

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status Card
          Card(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            elevation: 3,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.settings_remote,
                        color: _remoteConfigured
                            ? Colors.green
                            : Colors.redAccent,
                        size: 20,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _remoteConfigured
                            ? "Remote Configured"
                            : "Remote NOT Configured",
                        style: TextStyle(
                          fontSize: 13,
                          color: _remoteConfigured
                              ? Colors.green
                              : Colors.redAccent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        _wifiConnected
                            ? Icons.wifi
                            : Icons.wifi_off,
                        color: _wifiConnected
                            ? Colors.green
                            : Colors.redAccent,
                        size: 20,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _wifiConnected
                              ? "WiFi Connected${_wifiSsid.isNotEmpty ? ' ($_wifiSsid)' : ''}"
                              : "WiFi NOT Connected",
                          style: TextStyle(
                            fontSize: 13,
                            color: _wifiConnected
                                ? Colors.green
                                : Colors.redAccent,
                          ),
                        ),
                      ),
                      if (_remoteConfigured)
                        TextButton.icon(
                          onPressed:
                              _requestWifiReconnectOnDevice,
                          icon: const Icon(Icons.refresh,
                              size: 16),
                          label: const Text("Reconnect WiFi",
                              style: TextStyle(fontSize: 11)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.cloud_queue,
                        color: _mqttConnected
                            ? Colors.green
                            : Colors.orange,
                        size: 20,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        "MQTT: $_mqttStatus",
                        style: TextStyle(
                          fontSize: 13,
                          color: _mqttConnected
                              ? Colors.green
                              : Colors.orange,
                          fontWeight: FontWeight.w600,
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

          const Text(
            "MQTT Cloud Details",
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          const Text(
            "Only these 5 fields will be used and sent as JSON to the device.",
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),

          const SizedBox(height: 16),

          TextField(
            controller: _mqttIpController,
            decoration: const InputDecoration(
              labelText: "IP",
              hintText: "13.66.130.236",
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.dns),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _mqttPortController,
            decoration: const InputDecoration(
              labelText: "Port",
              hintText: "1883",
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.settings_ethernet),
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _mqttUsernameController,
            decoration: const InputDecoration(
              labelText: "Username",
              hintText: "whirlpoolindia",
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _mqttPasswordController,
            decoration: const InputDecoration(
              labelText: "Password",
              hintText: "whirl@123",
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.lock),
            ),
            obscureText: true,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _mqttTopicController,
            decoration: const InputDecoration(
              labelText: "Topic",
              hintText: "whirlpoolindia",
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.topic),
            ),
          ),

          const SizedBox(height: 18),

          const Text(
            "JSON sent to device:",
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text(
                jsonPreview,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isConnectingMqtt
                      ? null
                      : _connectToMqttBroker,
                  icon: const Icon(Icons.cloud_done),
                  label: const Text("Connect Cloud MQTT"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _sendMqttJsonToDevice,
                  icon: const Icon(Icons.devices),
                  label: const Text("Send JSON to Device"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Telemetry display
          Card(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                mainAxisAlignment:
                    MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      const Text(
                        "Room Temp",
                        style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _currentTemp == "--"
                            ? "--"
                            : "$_currentTemp °C",
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    children: [
                      const Text(
                        "AC Status",
                        style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _acStatus,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _acStatus.toUpperCase() ==
                                  "ON"
                              ? Colors.green
                              : (_acStatus.toUpperCase() ==
                                      "OFF"
                                  ? Colors.redAccent
                                  : Colors.grey),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Setpoint Section
          const Text(
            "Setpoint Control",
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            "ESP32 will read setpoints from cloud and control AC.\nRoom temperature is sent from device to cloud every 30 sec.",
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _coolOffController,
                  decoration: const InputDecoration(
                    labelText: "OFF Setpoint (°C)",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.ac_unit),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _coolOnController,
                  decoration: const InputDecoration(
                    labelText: "ON Setpoint (°C)",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.wb_sunny),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              onPressed: _publishSetpoint,
              icon: const Icon(Icons.save),
              label: const Text("Send Setpoint"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Manual AC ON/OFF
          const Text(
            "Manual AC Control",
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _publishAcCommand("AC_ON"),
                  icon: const Icon(Icons.power_settings_new),
                  label: const Text("AC ON"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _publishAcCommand("AC_OFF"),
                  icon: const Icon(Icons.power_settings_new),
                  label: const Text("AC OFF"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // MQTT message log (optional small log)
          if (_mqttMessages.isNotEmpty) ...[
            const Text(
              "MQTT Messages (latest):",
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Container(
              height: 120,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: Colors.grey.shade300),
              ),
              child: ListView.builder(
                reverse: true,
                itemCount: _mqttMessages.length,
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  child: Text(
                    _mqttMessages[index],
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
            ),
          ],

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _mqttIpController.dispose();
    _mqttPortController.dispose();
    _mqttUsernameController.dispose();
    _mqttPasswordController.dispose();
    _mqttTopicController.dispose();
    _coolOffController.dispose();
    _coolOnController.dispose();
    _mqttClient?.disconnect();
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
            _selectedIndex == 0
                ? "Home"
                : _selectedIndex == 1
                    ? "Profile"
                    : "MQTT Cloud",
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
            icon: const Icon(Icons.bluetooth,
                color: Colors.lightBlue),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) =>
                        const BluetoothScannerPage()),
              );
            },
          ),
        ],
      ),
      body: _selectedIndex == 0
          ? const Center(
              child: Text(
                "This is the Add Device page.\nTap the Bluetooth icon to scan & configure.",
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
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(12)),
                        elevation: 2,
                        child: ListTile(
                          leading: const Icon(Icons.person,
                              color: Colors.lightBlue,
                              size: 36),
                          title: Text(
                            userName,
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(userEmail),
                          trailing: const Icon(Icons.logout,
                              color: Colors.lightBlue),
                          onTap: _showLogoutDialog,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Card(
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(12)),
                        elevation: 2,
                        child: const ListTile(
                          leading: Icon(Icons.help_outline,
                              color: Colors.lightBlue),
                          title: Text("FAQ & Feedback"),
                          trailing:
                              Icon(Icons.arrow_forward_ios),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Card(
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(12)),
                        elevation: 2,
                        child: const ListTile(
                          leading: Icon(Icons.info_outline,
                              color: Colors.lightBlue),
                          title: Text("About"),
                          trailing:
                              Icon(Icons.arrow_forward_ios),
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
