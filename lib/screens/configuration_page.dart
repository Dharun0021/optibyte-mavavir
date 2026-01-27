import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bluetooth_scanner_page.dart';

class ConfigurationPage extends StatefulWidget {
  final BluetoothConnection connection;
  final BluetoothDevice device;

  const ConfigurationPage({
    super.key,
    required this.connection,
    required this.device,
  });

  @override
  State<ConfigurationPage> createState() => _ConfigurationPageState();
}

class _ConfigurationPageState extends State<ConfigurationPage> {
  late BluetoothConnection _connection;
  late BluetoothDevice _device;

  // ====== Theme ======
  static const Color _themeGreen = Color(0xFFC8E6C9);
  static const Color _green = Colors.green;
  static const Color _red = Colors.red;
  static const Color _orange = Colors.orange;
  static const Color _blue = Colors.blue;

  // ====== Connection Flags ======
  bool _isConnected = false;
  bool _isWifiConnected = false;
  bool _isGreenLedOn = false;
  bool _isYellowLedOn = false;

  // ====== WiFi Info ======
  String _wifiIP = "";
  String _wifiStatus = "WiFi not connected";
  final TextEditingController _ssidController = TextEditingController();
  final TextEditingController _wifiPasswordController = TextEditingController();

  // ====== Temp / RTC ======
  String _temperatureText = "-- °C";
  String _deviceTimeText = "--";

  // ====== Terminal ======
  bool _showTerminal = true;
  final TextEditingController _terminalController = TextEditingController();
  String _incomingBuffer = "";

  // ====== Saved Remotes ======
  List<String> _savedBrands = [];

  // ====== Remote Config ======
  bool _showRemoteConfigDetails = true;
  bool _configInProgress = false;
  bool _configCompleted = false;
  double _configProgress = 0.0;
  String _configStatusText = "Not started";
  String _configBrand = "";
  String _waitingKey = "";
  int _currentConfigStep = 0;
  final Set<String> _configuredKeys = <String>{};

  // Save status
  String _savingBrand = "";
  bool _isSavingRemote = false;
  Timer? _saveTimeoutTimer;

  /// ✅ REQUIRED ORDER (Power On -> Temp+ -> Temp- -> Swing -> Mode -> Power Off)
  final List<Map<String, dynamic>> _steps = const [
    {"label": "POWER ON", "key": "POWER_ON", "icon": Icons.power_settings_new},
    {"label": "TEMP +", "key": "TEMPUP", "icon": Icons.arrow_upward},
    {"label": "TEMP -", "key": "TEMPDOWN", "icon": Icons.arrow_downward},
    {"label": "SWING", "key": "SWING", "icon": Icons.swap_horiz},
    {"label": "MODE", "key": "MODE", "icon": Icons.tune},
    {"label": "POWER OFF", "key": "POWER_OFF", "icon": Icons.power_off},
  ];

  // Bottom sheet timers
  final TextEditingController _onTimeController = TextEditingController();
  final TextEditingController _offTimeController = TextEditingController();

  // ===================== MQTT + SETPOINT (NEW DROPDOWN) =====================
  bool _showMqttDropdown = false;

  // MQTT status from device
  bool _isMqttConnected = false;
  String _mqttStatus = "MQTT not connected";

  // MQTT input fields
  final TextEditingController _mqttHostController = TextEditingController(text: "13.66.130.236");
  final TextEditingController _mqttPortController = TextEditingController(text: "1883");
  final TextEditingController _mqttUserController = TextEditingController(text: "mahavirir");
  final TextEditingController _mqttPassController = TextEditingController(text: "mahavir@123");
  final TextEditingController _mqttTopicController = TextEditingController(text: "mahavirir");

  // Setpoint
  bool _autoControlEnabled = false;
  final TextEditingController _autoOnController = TextEditingController(text: "28");
  final TextEditingController _autoOffController = TextEditingController(text: "25");

  // ===================== Lifecycle =====================
  @override
  void initState() {
    super.initState();
    _connection = widget.connection;
    _device = widget.device;

    _isConnected = _connection.isConnected;
    _isYellowLedOn = _isConnected;

    _loadSavedState();
    _listenBluetooth();
  }

  @override
  void dispose() {
    _saveTimeoutTimer?.cancel();

    _ssidController.dispose();
    _wifiPasswordController.dispose();

    _terminalController.dispose();
    _onTimeController.dispose();
    _offTimeController.dispose();

    // mqtt controllers
    _mqttHostController.dispose();
    _mqttPortController.dispose();
    _mqttUserController.dispose();
    _mqttPassController.dispose();
    _mqttTopicController.dispose();

    // setpoint controllers
    _autoOnController.dispose();
    _autoOffController.dispose();

    super.dispose();
  }

  // ===================== Storage =====================
  Future<void> _loadSavedState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final brands = prefs.getStringList('saved_brands') ?? [];

      // ✅ Remove default samsung always
      brands.removeWhere((b) => b.trim().toLowerCase() == 'samsung');
      await prefs.setStringList('saved_brands', brands);

      setState(() {
        _savedBrands = brands;
        _isWifiConnected = prefs.getBool('wifi_connected') ?? false;
        _wifiIP = prefs.getString('wifi_ip') ?? "";
        _wifiStatus = _isWifiConnected ? "WiFi connected: $_wifiIP" : "WiFi not connected";
      });

      // load mqtt + setpoint prefs (NEW)
      final h = prefs.getString('mqtt_host');
      final p = prefs.getInt('mqtt_port');
      final u = prefs.getString('mqtt_user');
      final pw = prefs.getString('mqtt_pass');
      final t = prefs.getString('mqtt_topic');

      if (h != null && h.isNotEmpty) _mqttHostController.text = h;
      if (p != null && p > 0) _mqttPortController.text = p.toString();
      if (u != null) _mqttUserController.text = u;
      if (pw != null) _mqttPassController.text = pw;
      if (t != null && t.isNotEmpty) _mqttTopicController.text = t;

      _autoControlEnabled = prefs.getBool('auto_enabled') ?? false;
      final aon = prefs.getDouble('auto_on');
      final aoff = prefs.getDouble('auto_off');
      if (aon != null) _autoOnController.text = aon.toString();
      if (aoff != null) _autoOffController.text = aoff.toString();
    } catch (_) {}
  }

  Future<void> _saveBrands() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('saved_brands', _savedBrands);
    } catch (_) {}
  }

  Future<void> _saveWifiStatus(bool connected, {required String ip}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('wifi_connected', connected);
      await prefs.setString('wifi_ip', ip);
    } catch (_) {}
  }

  Future<void> _saveMqttPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('mqtt_host', _mqttHostController.text.trim());
      await prefs.setInt('mqtt_port', int.tryParse(_mqttPortController.text.trim()) ?? 1883);
      await prefs.setString('mqtt_user', _mqttUserController.text);
      await prefs.setString('mqtt_pass', _mqttPassController.text);
      await prefs.setString('mqtt_topic', _mqttTopicController.text.trim());
    } catch (_) {}
  }

  Future<void> _saveAutoPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('auto_enabled', _autoControlEnabled);
      await prefs.setDouble('auto_on', double.tryParse(_autoOnController.text.trim()) ?? 28.0);
      await prefs.setDouble('auto_off', double.tryParse(_autoOffController.text.trim()) ?? 25.0);
    } catch (_) {}
  }

  // ===================== BT Rx =====================
  void _listenBluetooth() {
    _connection.input?.listen((Uint8List data) {
      final chunk = String.fromCharCodes(data);
      _log("RX: $chunk");
      _incomingBuffer += chunk;

      String line;
      while ((line = _extractLine()) != "") {
        _handleLine(line.trim());
      }
    }).onDone(() {
      setState(() {
        _isConnected = false;
        _isYellowLedOn = false;
      });
      _showSnack("Bluetooth disconnected", _red);
    });
  }

  // ✅ Robust line extraction for \n or \r\n or \r
  String _extractLine() {
    if (_incomingBuffer.isEmpty) return "";
    final nIdx = _incomingBuffer.indexOf('\n');
    final rIdx = _incomingBuffer.indexOf('\r');

    int idx;
    if (nIdx == -1 && rIdx == -1) return "";
    if (nIdx == -1) {
      idx = rIdx;
    } else if (rIdx == -1) {
      idx = nIdx;
    } else {
      idx = (nIdx < rIdx) ? nIdx : rIdx;
    }

    final line = _incomingBuffer.substring(0, idx);
    // remove \r\n or \n or \r
    int cut = idx + 1;
    if (idx + 1 < _incomingBuffer.length) {
      final a = _incomingBuffer[idx];
      final b = _incomingBuffer[idx + 1];
      if (a == '\r' && b == '\n') cut = idx + 2;
    }
    _incomingBuffer = _incomingBuffer.substring(cut);
    return line;
  }

  void _handleLine(String line) {
    if (line.isEmpty) return;

    // WiFi
    if (line.startsWith("WIFI_CONNECTED:")) {
      final ip = line.replaceFirst("WIFI_CONNECTED:", "").trim();
      setState(() {
        _isWifiConnected = true;
        _wifiIP = ip;
        _wifiStatus = "WiFi connected: $ip";
        _isGreenLedOn = true;

        // ✅ show MQTT dropdown automatically once WiFi connected
        _showMqttDropdown = true;
      });
      _saveWifiStatus(true, ip: ip);

      // Optional: auto-trigger MQTT connect using already saved fields
      // (ESP32 code already auto-connects, but this ensures correct creds if you changed them)
      _sendMqttSettingsToDevice(connect: true);
      return;
    }
    if (line.startsWith("WIFI_FAILED")) {
      setState(() {
        _isWifiConnected = false;
        _wifiIP = "";
        _wifiStatus = "WiFi connection failed";
        _isGreenLedOn = false;

        _isMqttConnected = false;
        _mqttStatus = "MQTT not connected";
      });
      _saveWifiStatus(false, ip: "");
      return;
    }

    // MQTT
    if (line.startsWith("MQTT_CONNECTED")) {
      setState(() {
        _isMqttConnected = true;
        _mqttStatus = "MQTT connected ✅";
      });
      _showSnack("MQTT connected ✅", _green);
      return;
    }
    if (line.startsWith("MQTT_FAILED")) {
      setState(() {
        _isMqttConnected = false;
        _mqttStatus = "MQTT failed ❌";
      });
      _showSnack("MQTT failed ❌", _red);
      return;
    }
    if (line.startsWith("MQTT_PUBLISHED")) {
      // from firmware debug
      setState(() => _mqttStatus = "MQTT published ✅");
      return;
    }
    if (line.startsWith("DBG:MQTT_NOT_CONNECTED")) {
      setState(() => _mqttStatus = line);
      return;
    }

    // Temp & Time
    if (line.startsWith("TEMP:")) {
      setState(() => _temperatureText = line.replaceFirst("TEMP:", "").trim());
      return;
    }
    if (line.startsWith("TIME:")) {
      setState(() => _deviceTimeText = line.replaceFirst("TIME:", "").trim());
      return;
    }
    if (line.startsWith("RTC:")) {
      setState(() => _deviceTimeText = line.replaceFirst("RTC:", "").trim());
      return;
    }
    if (line.startsWith("RTC_TIME:")) {
      setState(() => _deviceTimeText = line.replaceFirst("RTC_TIME:", "").trim());
      return;
    }
    if (line.startsWith("DEVICE_RTC:")) {
      setState(() => _deviceTimeText = line.replaceFirst("DEVICE_RTC:", "").trim());
      return;
    }
    if (line.startsWith("TIME_SET:")) {
      setState(() => _deviceTimeText = line.replaceFirst("TIME_SET:", "").trim());
      return;
    }

    // Remote saved confirmation
    if (line.startsWith("REMOTE_SAVED:")) {
      final brand = line.replaceFirst("REMOTE_SAVED:", "").trim();
      _onRemoteSavedFromDevice(brand);
      return;
    }

    // Config handshake from ESP32
    if (line.startsWith("APP_CFG:WAIT:")) {
      final key = line.replaceFirst("APP_CFG:WAIT:", "").trim();
      _onConfigWaitKey(key);
      return;
    }
    if (line.startsWith("APP_CFG:DONE:")) {
      final key = line.replaceFirst("APP_CFG:DONE:", "").trim();
      _onConfigDoneKey(key);
      return;
    }

    // Progress (optional)
    if (line.startsWith("IR_LEARNING_PROGRESS:")) {
      final pStr = line.replaceFirst("IR_LEARNING_PROGRESS:", "").trim();
      final v = double.tryParse(pStr) ?? 0;
      setState(() {
        _configProgress = (v / 100.0).clamp(0.0, 1.0);
        _configStatusText = "Learning... ${v.toStringAsFixed(0)}%";
      });
      return;
    }

    if (line.startsWith("IR_SENT")) {
      _showSnack("IR sent ✅", _green);
      return;
    }

    // LEDs
    if (line.startsWith("YELLOW_LED:")) {
      final s = line.replaceFirst("YELLOW_LED:", "").trim().toLowerCase();
      setState(() => _isYellowLedOn = (s == "on"));
      return;
    }
    if (line.startsWith("GREEN_LED:")) {
      final s = line.replaceFirst("GREEN_LED:", "").trim().toLowerCase();
      setState(() => _isGreenLedOn = (s == "on"));
      return;
    }

    // Generic error
    if (line.startsWith("ERR:")) {
      _showSnack(line, _red);
      return;
    }
  }

  // ===================== Commands =====================
  Future<void> _sendCommand(String cmd) async {
    if (!_connection.isConnected) {
      _showSnack("Bluetooth not connected", _red);
      return;
    }
    try {
      _log("TX: $cmd");
      _connection.output.add(Uint8List.fromList(utf8.encode("$cmd\n")));
      await _connection.output.allSent;
    } catch (e) {
      _showSnack("Send failed: $e", _red);
    }
  }

  // ===================== MQTT + SETPOINT SEND (NEW) =====================
  Future<void> _sendMqttSettingsToDevice({bool connect = false}) async {
    if (!_isWifiConnected) {
      _showSnack("Connect WiFi first", _orange);
      return;
    }

    final host = _mqttHostController.text.trim();
    final port = int.tryParse(_mqttPortController.text.trim()) ?? 1883;
    final user = _mqttUserController.text.trim();
    final pass = _mqttPassController.text;
    final topic = _mqttTopicController.text.trim();

    if (host.isEmpty || topic.isEmpty) {
      _showSnack("MQTT Host and Topic required", _red);
      return;
    }

    await _saveMqttPrefs();

    // Firmware supports these BT commands
    await _sendCommand("MQTT_HOST:$host");
    await _sendCommand("MQTT_PORT:$port");
    await _sendCommand("MQTT_USER:$user");
    await _sendCommand("MQTT_PASS:$pass");
    await _sendCommand("MQTT_TOPIC:$topic");

    _showSnack("MQTT details sent ✅", _green);

    if (connect) {
      await _sendCommand("MQTT_CONNECT");
    }
  }

  Future<void> _sendAutoSetpointsToDevice() async {
    final onV = double.tryParse(_autoOnController.text.trim());
    final offV = double.tryParse(_autoOffController.text.trim());
    if (onV == null || offV == null) {
      _showSnack("Enter valid setpoints", _red);
      return;
    }
    await _saveAutoPrefs();

    if (_autoControlEnabled) {
      await _sendCommand("AUTO_ON:${onV.toStringAsFixed(1)}");
      await _sendCommand("AUTO_OFF:${offV.toStringAsFixed(1)}");
      _showSnack("Auto control enabled ✅", _green);
    } else {
      await _sendCommand("AUTO_DISABLE");
      _showSnack("Auto control disabled", _orange);
    }
  }

  // ===================== Remote Config =====================
  String _normalizeBrand(String s) => s.trim();

  void _startNewConfiguration() {
    if (!_connection.isConnected) {
      _showSnack("Bluetooth not connected", _red);
      return;
    }

    final brandCtrl = TextEditingController(text: _configBrand);

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Enter Brand"),
        content: TextField(
          controller: brandCtrl,
          decoration: const InputDecoration(
            labelText: "Brand (ex: Voltas, LG, Daikin)",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () {
              final b = _normalizeBrand(brandCtrl.text);
              if (b.isEmpty) {
                _showSnack("Please enter brand name", _red);
                return;
              }
              if (b.toLowerCase() == "samsung") {
                _showSnack("Samsung default remote disabled here. Use another brand.", _orange);
                return;
              }
              Navigator.pop(context);

              setState(() {
                _configBrand = b;
                _configInProgress = true;
                _configCompleted = false;
                _configProgress = 0.0;
                _configStatusText = "Starting configuration for: $b";
                _configuredKeys.clear();
                _currentConfigStep = 0;
                _waitingKey = "POWER_ON";
                _isSavingRemote = false;
                _savingBrand = "";
              });

              // ✅ YOUR REQUIRED FLOW:
              // START_CONFIG -> BRAND:<brand> -> CONFIG:POWER_ON -> ... -> CONFIG:POWER_OFF -> SAVE_REMOTE
              _sendCommand("START_CONFIG");
              _sendCommand("BRAND:$b");
              _sendCommand("CONFIG:POWER_ON");
            },
            child: const Text("Start"),
          ),
        ],
      ),
    );
  }

  void _onConfigWaitKey(String key) {
    setState(() {
      _waitingKey = key;
      _currentConfigStep = _stepIndexForKey(key);
      _configStatusText = "Waiting: $key (press remote key)";
      _configInProgress = true;
    });
  }

  void _onConfigDoneKey(String key) {
    final stepIdx = _stepIndexForKey(key);

    setState(() {
      _configuredKeys.add(key);
      _configProgress = ((stepIdx + 1) / _steps.length).clamp(0.0, 1.0);
      if (_waitingKey == key) _waitingKey = "";
      _configStatusText = "Received $key ✅";
      _currentConfigStep = stepIdx;
    });

    final next = _nextKey(key);
    if (next.isEmpty) {
      setState(() {
        _configInProgress = false;
        _configCompleted = true;
        _waitingKey = "";
        _configStatusText = "All keys learned ✅ Tap 'Save Remote'";
      });
      return;
    }

    setState(() {
      _waitingKey = next;
      _currentConfigStep = _stepIndexForKey(next);
      _configStatusText = "Next: $next (press remote key)";
    });

    _sendCommand("CONFIG:$next");
  }

  int _stepIndexForKey(String key) {
    for (int i = 0; i < _steps.length; i++) {
      if (_steps[i]["key"] == key) return i;
    }
    return 0;
  }

  String _nextKey(String current) {
    final idx = _stepIndexForKey(current);
    if (idx >= _steps.length - 1) return "";
    return _steps[idx + 1]["key"] as String;
  }

  // ✅ Save command must be SAVE_REMOTE
  void _saveRemoteNow() {
    final cleanBrand = _normalizeBrand(_configBrand);
    if (cleanBrand.isEmpty) {
      _showSnack("Brand missing. Please start config again.", _orange);
      return;
    }
    if (cleanBrand.toLowerCase() == 'samsung') {
      _showSnack("Samsung default remote disabled here.", _orange);
      return;
    }

    // add to UI immediately
    if (!_savedBrands.any((b) => b.toLowerCase() == cleanBrand.toLowerCase())) {
      setState(() => _savedBrands.add(cleanBrand));
      _saveBrands();
    }

    // send to ESP32
    setState(() {
      _isSavingRemote = true;
      _savingBrand = cleanBrand;
      _configStatusText = "Saving remote: $cleanBrand ...";
    });

    _sendCommand("SAVE_REMOTE");

    _saveTimeoutTimer?.cancel();
    _saveTimeoutTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      if (_isSavingRemote) {
        setState(() {
          _isSavingRemote = false;
          _configStatusText = "Saved in app ✅ (device confirmation not received)";
        });
        _showSnack("Saved in app ✅ (ESP32 not confirming REMOTE_SAVED)", _orange);
      }
    });
  }

  void _onRemoteSavedFromDevice(String brand) {
    final clean = _normalizeBrand(brand);
    if (clean.isEmpty) return;
    if (clean.toLowerCase() == 'samsung') return;

    if (!_savedBrands.any((b) => b.toLowerCase() == clean.toLowerCase())) {
      setState(() => _savedBrands.add(clean));
      _saveBrands();
    }

    _saveTimeoutTimer?.cancel();
    setState(() {
      _isSavingRemote = false;
      _savingBrand = "";
      _configStatusText = "Remote saved ✅ $clean";
    });
    _showSnack("Remote saved ✅ $clean", _green);
  }

  Future<void> _deleteRemote(String brand) async {
    final clean = _normalizeBrand(brand);
    if (clean.isEmpty) return;
    if (clean.toLowerCase() == 'samsung') return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Delete Remote"),
        content: Text("Are you sure you want to delete '$clean'?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Delete", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (ok != true) return;

    setState(() {
      _savedBrands.removeWhere((b) => b.trim().toLowerCase() == clean.toLowerCase());
    });
    await _saveBrands();

    _showSnack("Deleted ✅ $clean", _orange);
  }

  // ===================== WiFi =====================
  void _showWifiSetupDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("WiFi Setup"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _ssidController,
              decoration: const InputDecoration(labelText: "SSID", border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _wifiPasswordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: "Password", border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _connectWifi();
            },
            child: const Text("Send"),
          ),
        ],
      ),
    );
  }

  Future<void> _connectWifi() async {
    final ssid = _ssidController.text.trim();
    final pass = _wifiPasswordController.text.trim();
    if (ssid.isEmpty || pass.isEmpty) {
      _showSnack("Enter SSID and password", _red);
      return;
    }
    setState(() => _wifiStatus = "Connecting to WiFi...");
    await _sendCommand("WIFI:$ssid,$pass");
  }

  // ===================== Remote Controls UI =====================
  void _showRemoteControls(String brand) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 12,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      "$brand Remote",
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                    ),
                  ),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _remoteBtn("POWER ON", Icons.power_settings_new, () => _sendCommand("SEND:POWER_ON")),
                  _remoteBtn("TEMP +", Icons.arrow_upward, () => _sendCommand("SEND:TEMPUP")),
                  _remoteBtn("TEMP -", Icons.arrow_downward, () => _sendCommand("SEND:TEMPDOWN")),
                  _remoteBtn("SWING", Icons.swap_horiz, () => _sendCommand("SEND:SWING")),
                  _remoteBtn("MODE", Icons.tune, () => _sendCommand("SEND:MODE")),
                  _remoteBtn("POWER OFF", Icons.power_off, () => _sendCommand("SEND:POWER_OFF")),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _onTimeController,
                      readOnly: true,
                      decoration: const InputDecoration(labelText: "ON Time (HH:MM)", border: OutlineInputBorder()),
                      onTap: () => _pickTime(_onTimeController, "SCHEDULE_ON"),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _offTimeController,
                      readOnly: true,
                      decoration: const InputDecoration(labelText: "OFF Time (HH:MM)", border: OutlineInputBorder()),
                      onTap: () => _pickTime(_offTimeController, "SCHEDULE_OFF"),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _remoteBtn(String label, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 110,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(color: _themeGreen, borderRadius: BorderRadius.circular(14)),
        child: Column(
          children: [
            Icon(icon, color: Colors.black),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }

  Future<void> _pickTime(TextEditingController controller, String cmdPrefix) async {
    final now = TimeOfDay.now();
    final picked = await showTimePicker(context: context, initialTime: now);
    if (picked == null) return;

    final hh = picked.hour.toString().padLeft(2, '0');
    final mm = picked.minute.toString().padLeft(2, '0');
    final timeStr = "$hh:$mm";
    setState(() => controller.text = timeStr);
    await _sendCommand("$cmdPrefix:$timeStr");
  }

  // ===================== UI =====================
  Widget _buildStatusCard() {
    final title = _isConnected ? "Connected: ${_device.name ?? 'Device'}" : "Bluetooth not connected";
    return Card(
      elevation: 2,
      margin: const EdgeInsets.all(12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(_isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                color: _isConnected ? _blue : _red),
            const SizedBox(width: 10),
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800))),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(children: [
                  Icon(Icons.circle, size: 12, color: _isYellowLedOn ? Colors.yellow : Colors.grey),
                  const SizedBox(width: 4),
                  const Text("BT"),
                ]),
                const SizedBox(height: 4),
                Row(children: [
                  Icon(Icons.circle, size: 12, color: _isGreenLedOn ? Colors.green : Colors.grey),
                  const SizedBox(width: 4),
                  const Text("WiFi"),
                ]),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWifiCard() {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.wifi, color: _themeGreen),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _wifiStatus,
                    style: TextStyle(fontWeight: FontWeight.w800, color: _isWifiConnected ? _green : _red),
                  ),
                  if (_wifiIP.isNotEmpty) Text(_wifiIP, style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _showWifiSetupDialog,
                        icon: const Icon(Icons.settings, size: 16),
                        label: const Text("WiFi Setup"),
                        style: ElevatedButton.styleFrom(backgroundColor: _themeGreen, foregroundColor: Colors.black),
                      ),
                      if (_isWifiConnected)
                        OutlinedButton.icon(
                          onPressed: () => setState(() => _showMqttDropdown = !_showMqttDropdown),
                          icon: Icon(_showMqttDropdown ? Icons.expand_less : Icons.expand_more, size: 16),
                          label: Text(_showMqttDropdown ? "Hide MQTT" : "Show MQTT"),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMqttDropdownCard() {
    if (!_isWifiConnected) return const SizedBox.shrink();
    if (!_showMqttDropdown) return const SizedBox.shrink();

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text("MQTT Settings", style: TextStyle(fontWeight: FontWeight.w900)),
                ),
                Chip(
                  label: Text(_mqttStatus, style: const TextStyle(fontSize: 12)),
                  backgroundColor: _isMqttConnected ? Colors.green.shade100 : Colors.red.shade100,
                ),
              ],
            ),
            const SizedBox(height: 10),

            _field("Host / IP", _mqttHostController),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _field("Port", _mqttPortController, keyboard: TextInputType.number)),
                const SizedBox(width: 10),
                Expanded(child: _field("Topic", _mqttTopicController)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _field("Username", _mqttUserController)),
                const SizedBox(width: 10),
                Expanded(child: _field("Password", _mqttPassController, obscure: true)),
              ],
            ),

            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _sendMqttSettingsToDevice(connect: false),
                  icon: const Icon(Icons.save, size: 16),
                  label: const Text("Save & Send"),
                  style: ElevatedButton.styleFrom(backgroundColor: _themeGreen, foregroundColor: Colors.black),
                ),
                ElevatedButton.icon(
                  onPressed: () => _sendMqttSettingsToDevice(connect: true),
                  icon: const Icon(Icons.cloud_done, size: 16),
                  label: const Text("Connect MQTT"),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                ),
                OutlinedButton.icon(
                  onPressed: () => _sendCommand("PUBLISH"),
                  icon: const Icon(Icons.send, size: 16),
                  label: const Text("Test Publish"),
                ),
              ],
            ),

            const Divider(height: 22),

            // ================= SETPOINT section under MQTT =================
            Row(
              children: [
                const Expanded(
                  child: Text("Auto Control Setpoint", style: TextStyle(fontWeight: FontWeight.w900)),
                ),
                Switch(
                  value: _autoControlEnabled,
                  onChanged: (v) async {
                    setState(() => _autoControlEnabled = v);
                    await _saveAutoPrefs();
                    await _sendAutoSetpointsToDevice();
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _field("Auto ON Temp (°C)", _autoOnController, keyboard: TextInputType.number)),
                const SizedBox(width: 10),
                Expanded(child: _field("Auto OFF Temp (°C)", _autoOffController, keyboard: TextInputType.number)),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: _sendAutoSetpointsToDevice,
                  icon: const Icon(Icons.tune, size: 16),
                  label: const Text("Apply Setpoint"),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    setState(() {
                      _autoControlEnabled = false;
                    });
                    await _saveAutoPrefs();
                    await _sendAutoSetpointsToDevice();
                  },
                  icon: const Icon(Icons.pause_circle, size: 16),
                  label: const Text("Disable Auto"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController c, {
    TextInputType keyboard = TextInputType.text,
    bool obscure = false,
  }) {
    return TextField(
      controller: c,
      keyboardType: keyboard,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }

  Widget _buildTempRtcCard() {
    final sub = TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w700);

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.thermostat, color: Colors.orange),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Room Temp ", style: sub),
                      const SizedBox(height: 2),
                      Text(_temperatureText, style: const TextStyle(fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
                IconButton(icon: const Icon(Icons.refresh), onPressed: () => _sendCommand("GET_TEMP")),
              ],
            ),
            const Divider(height: 18),
            Row(
              children: [
                Icon(Icons.access_time, color: _blue),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Device RTC", style: sub),
                      const SizedBox(height: 2),
                      Text(_deviceTimeText, style: const TextStyle(fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
                IconButton(icon: const Icon(Icons.schedule), onPressed: () => _sendCommand("GET_TIME")),
                IconButton(
                  icon: const Icon(Icons.sync),
                  onPressed: () {
                    final now = DateTime.now();
                    final formatted = DateFormat('yyyy-MM-dd HH:mm:ss').format(now);
                    setState(() => _deviceTimeText = formatted);
                    _sendCommand("SET_TIME:$formatted");
                    Future.delayed(const Duration(milliseconds: 500), () {
                      if (mounted) _sendCommand("GET_TIME");
                    });
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRemoteConfigSection() {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text("Remote Configuration", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                ),
                IconButton(
                  onPressed: () => setState(() => _showRemoteConfigDetails = !_showRemoteConfigDetails),
                  icon: Icon(_showRemoteConfigDetails ? Icons.expand_less : Icons.expand_more),
                ),
              ],
            ),
            if (_showRemoteConfigDetails) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: _configProgress,
                minHeight: 6,
                backgroundColor: Colors.grey.shade200,
                color: _themeGreen,
              ),
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerLeft, child: Text(_configStatusText, style: const TextStyle(fontSize: 12))),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _steps.map((s) {
                  final key = s["key"] as String;
                  final label = s["label"] as String;
                  final icon = s["icon"] as IconData;

                  final isDone = _configuredKeys.contains(key);
                  final isWaiting = _waitingKey == key;

                  Color bg = Colors.grey.shade200;
                  Color fg = Colors.black;

                  if (isDone) {
                    bg = Colors.green;
                    fg = Colors.white;
                  } else if (isWaiting) {
                    bg = Colors.orange;
                    fg = Colors.white;
                  }

                  return Chip(
                    avatar: Icon(icon, size: 16, color: fg),
                    label: Text(label, style: TextStyle(color: fg)),
                    backgroundColor: bg,
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: _configInProgress ? null : _startNewConfiguration,
                    icon: const Icon(Icons.play_arrow),
                    label: Text(_configInProgress ? "Configuring..." : "Start Config"),
                    style: ElevatedButton.styleFrom(backgroundColor: _themeGreen, foregroundColor: Colors.black),
                  ),
                  const SizedBox(width: 10),
                  if (_configCompleted)
                    ElevatedButton.icon(
                      onPressed: _isSavingRemote ? null : _saveRemoteNow,
                      icon: _isSavingRemote
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.save),
                      label: Text(_isSavingRemote ? "Saving..." : "Save Remote"),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSavedRemotes() {
    if (_savedBrands.isEmpty) return const SizedBox.shrink();

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Saved Remotes", style: TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            Column(
              children: _savedBrands.map((b) {
                return ListTile(
                  leading: const Icon(Icons.ac_unit),
                  title: Text(b, style: const TextStyle(fontWeight: FontWeight.w800)),
                  trailing: Wrap(
                    spacing: 8,
                    children: [
                      ElevatedButton(
                        onPressed: () => _showRemoteControls(b),
                        style: ElevatedButton.styleFrom(backgroundColor: _themeGreen, foregroundColor: Colors.black),
                        child: const Text("Open"),
                      ),
                      IconButton(
                        tooltip: "Delete",
                        onPressed: () => _deleteRemote(b),
                        icon: const Icon(Icons.delete, color: Colors.red),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTerminal() {
    if (!_showTerminal) {
      return Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: () => setState(() => _showTerminal = true),
          icon: const Icon(Icons.developer_mode),
          label: const Text("Show Logs"),
        ),
      );
    }

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(child: Text("Terminal / Logs", style: TextStyle(fontWeight: FontWeight.w900))),
                IconButton(onPressed: () => setState(() => _showTerminal = false), icon: const Icon(Icons.close)),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              height: 160,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12)),
              child: SingleChildScrollView(
                reverse: true,
                child: Text(
                  _terminalController.text,
                  style: const TextStyle(fontFamily: 'monospace', color: Colors.greenAccent, fontSize: 11),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===================== Helpers =====================
  void _log(String msg) {
    final t = DateFormat("HH:mm:ss").format(DateTime.now());
    _terminalController.text += "[$t] $msg\n";
    setState(() {});
  }

  void _showSnack(String msg, Color c) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: c));
  }

  void _disconnectBluetooth() {
    if (_connection.isConnected) _connection.close();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const BluetoothScannerPage()),
      (_) => false,
    );
  }

  // ===================== Build =====================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Configuration", style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900)),
        backgroundColor: _themeGreen,
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          IconButton(icon: const Icon(Icons.add), onPressed: _configInProgress ? null : _startNewConfiguration),
          IconButton(icon: const Icon(Icons.bluetooth_disabled), onPressed: _disconnectBluetooth),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildStatusCard(),
            _buildWifiCard(),
            _buildMqttDropdownCard(), // ✅ NEW DROPDOWN (MQTT + SETPOINT)
            _buildTempRtcCard(),
            _buildRemoteConfigSection(),
            _buildSavedRemotes(),
            _buildTerminal(),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
