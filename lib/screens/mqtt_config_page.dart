import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MqttConfigPage extends StatefulWidget {
  final BluetoothConnection connection;

  const MqttConfigPage({
    super.key,
    required this.connection,
  });

  @override
  State<MqttConfigPage> createState() => _MqttConfigPageState();
}

class _MqttConfigPageState extends State<MqttConfigPage> {
  // MQTT controllers
  final TextEditingController _mqttIpController =
      TextEditingController(text: "broker.hivemq.com");
  final TextEditingController _mqttPortController =
      TextEditingController(text: "1883");
  final TextEditingController _mqttUsernameController = TextEditingController();
  final TextEditingController _mqttPasswordController = TextEditingController();
  final TextEditingController _mqttTopicController =
      TextEditingController(text: "sustainabyte/irblaster");

  // Setpoint controllers
  final TextEditingController _offTempController =
      TextEditingController(text: "25"); // OFF at/below this
  final TextEditingController _onTempController =
      TextEditingController(text: "28"); // ON at/above this

  bool _remoteConfigured = false;
  bool _wifiConnected = false;
  bool _mqttSent = false;

  String _wifiSsid = "";
  String _activeBrand = ""; // ⭐ latest saved / selected brand

  bool _isSendingMqtt = false;
  bool _isSendingSetpoint = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _mqttIpController.dispose();
    _mqttPortController.dispose();
    _mqttUsernameController.dispose();
    _mqttPasswordController.dispose();
    _mqttTopicController.dispose();
    _offTempController.dispose();
    _onTempController.dispose();
    super.dispose();
  }

  // ---------------- Brand / Remote detection ----------------
  String _pickLastBrand(SharedPreferences prefs) {
    // Priority: selected brand
    final selected = (prefs.getString('selected_brand') ??
            prefs.getString('current_brand') ??
            prefs.getString('brand') ??
            "")
        .trim();
    if (selected.isNotEmpty) return selected;

    // Next: saved brands list
    final b1 = prefs.getStringList('saved_brands') ?? const <String>[];
    final b2 = prefs.getStringList('savedBrands') ?? const <String>[];
    final b3 = prefs.getStringList('_savedBrands') ?? const <String>[];

    final merged = <String>[...b1, ...b2, ...b3]
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    if (merged.isNotEmpty) return merged.last; // ✅ latest saved

    // Fallback: samsung if nothing (optional)
    return "";
  }

  bool _detectRemoteConfigured(SharedPreferences prefs) {
    if (prefs.getBool('remote_configured') == true) return true;

    final brands = {
      ...?prefs.getStringList('saved_brands'),
      ...?prefs.getStringList('savedBrands'),
      ...?prefs.getStringList('_savedBrands'),
    }.where((e) => e.trim().isNotEmpty).toList();

    if (brands.isNotEmpty) return true;

    // fallback: any remote key stored
    final keys = prefs.getKeys();
    return keys.any((k) {
      final lk = k.toLowerCase();
      return lk.contains('power') ||
          lk.contains('tempup') ||
          lk.contains('tempdown') ||
          lk.contains('swing') ||
          lk.contains('mode');
    });
  }

  Future<void> _loadAll() async {
    final prefs = await SharedPreferences.getInstance();

    setState(() {
      _wifiConnected = prefs.getBool('wifi_connected') ?? false;
      _wifiSsid = (prefs.getString('wifi_ssid') ?? "").trim();

      _remoteConfigured = _detectRemoteConfigured(prefs);
      _mqttSent = prefs.getBool('mqtt_sent') ?? false;

      _activeBrand = _pickLastBrand(prefs);

      // Load MQTT saved
      _mqttIpController.text = prefs.getString('mqtt_ip') ?? _mqttIpController.text;
      _mqttPortController.text = prefs.getString('mqtt_port') ?? _mqttPortController.text;
      _mqttUsernameController.text = prefs.getString('mqtt_username') ?? "";
      _mqttPasswordController.text = prefs.getString('mqtt_password') ?? "";
      _mqttTopicController.text = prefs.getString('mqtt_topic') ?? _mqttTopicController.text;

      // Load setpoints saved
      _offTempController.text = prefs.getString('sp_off') ?? _offTempController.text;
      _onTempController.text = prefs.getString('sp_on') ?? _onTempController.text;
    });
  }

  // ---------------- MQTT ----------------
  Map<String, dynamic> _buildMqttJson() => {
        "ip": _mqttIpController.text.trim(),
        "port": _mqttPortController.text.trim(),
        "user": _mqttUsernameController.text.trim(),
        "pass": _mqttPasswordController.text.trim(),
        "topic": _mqttTopicController.text.trim(),
      };

  Future<void> _sendMqttJsonToDevice() async {
    if (!_remoteConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("⚠️ Save remote first (Brand → Config → Save), then MQTT."),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (!_wifiConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("⚠️ Connect WiFi first, then send MQTT."),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final cfg = _buildMqttJson();
    if (cfg["ip"].toString().isEmpty || cfg["topic"].toString().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("❌ Please enter MQTT Host and Topic."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      setState(() => _isSendingMqtt = true);

      final cmd = "MQTT:${jsonEncode(cfg)}\n";
      widget.connection.output.add(Uint8List.fromList(utf8.encode(cmd)));
      await widget.connection.output.allSent;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('mqtt_ip', _mqttIpController.text.trim());
      await prefs.setString('mqtt_port', _mqttPortController.text.trim());
      await prefs.setString('mqtt_username', _mqttUsernameController.text.trim());
      await prefs.setString('mqtt_password', _mqttPasswordController.text.trim());
      await prefs.setString('mqtt_topic', _mqttTopicController.text.trim());
      await prefs.setBool('mqtt_sent', true);

      // update active brand from latest saved
      _activeBrand = _pickLastBrand(prefs);

      setState(() => _mqttSent = true);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("✅ MQTT details sent to Device. Now set Set Point."),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("❌ Failed to send MQTT: $e"),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSendingMqtt = false);
    }
  }

  // ---------------- SETPOINT ----------------
  int? _parseTemp(String s) {
    final v = int.tryParse(s.trim());
    if (v == null) return null;
    if (v < 10 || v > 40) return null;
    return v;
  }

  Future<void> _sendSetpointToDevice() async {
    if (!_mqttSent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("⚠️ Send MQTT details first, then Set Point."),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_activeBrand.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("⚠️ No saved brand found. Save a remote brand first."),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final offT = _parseTemp(_offTempController.text);
    final onT = _parseTemp(_onTempController.text);

    if (offT == null || onT == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("❌ Enter valid temps (10°C to 40°C)."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (onT <= offT) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("❌ ON temp must be greater than OFF temp.\nExample: OFF 25, ON 28"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      setState(() => _isSendingSetpoint = true);

      // ✅ First: Set active brand
      final brandCmd = "SET_BRAND:${_activeBrand.trim()}\n";
      widget.connection.output.add(Uint8List.fromList(utf8.encode(brandCmd)));
      await widget.connection.output.allSent;

      // ✅ Second: Send setpoint
      final spCmd = "SETPOINT:OFF=$offT,ON=$onT\n";
      widget.connection.output.add(Uint8List.fromList(utf8.encode(spCmd)));
      await widget.connection.output.allSent;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('sp_off', offT.toString());
      await prefs.setString('sp_on', onT.toString());
      await prefs.setString('selected_brand', _activeBrand.trim());

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("✅ Brand=$_activeBrand | SetPoint OFF=$offT°C ON=$onT°C sent"),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("❌ Failed to send setpoint: $e"),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSendingSetpoint = false);
    }
  }

  // ---------------- UI Helpers ----------------
  Widget _statusTile({
    required IconData icon,
    required String label,
    required String value,
    required bool ok,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: ok ? Colors.green.shade50 : Colors.orange.shade50,
        border: Border.all(
          color: ok ? Colors.green.shade200 : Colors.orange.shade200,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: ok ? Colors.green : Colors.orange),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "$label: $value",
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    bool obscure = false,
    TextInputType type = TextInputType.text,
    String? hint,
    bool enabled = true,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        enabled: enabled,
        controller: controller,
        keyboardType: type,
        obscureText: obscure,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const topLightGreen = Color(0xFFB2DFDB);
    const green = Color.fromARGB(255, 100, 170, 102);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: topLightGreen,
        elevation: 0,
        title: const Text(
          "MQTT + Set Point",
          style: TextStyle(color:Colors.green, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.green),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAll,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _statusTile(
            icon: Icons.settings_remote,
            label: "Remote",
            value: _remoteConfigured ? "Configured" : "Not Configured",
            ok: _remoteConfigured,
          ),
          _statusTile(
            icon: Icons.wifi,
            label: "WiFi",
            value: _wifiConnected ? "Connected ($_wifiSsid)" : "Not Connected",
            ok: _wifiConnected,
          ),
          _statusTile(
            icon: Icons.branding_watermark,
            label: "Active Brand",
            value: _activeBrand.isNotEmpty ? _activeBrand : "Not Found",
            ok: _activeBrand.isNotEmpty,
          ),
          _statusTile(
            icon: Icons.cloud_done,
            label: "MQTT",
            value: _mqttSent ? "Sent to device" : "Not sent yet",
            ok: _mqttSent,
          ),

          const SizedBox(height: 8),

          // MQTT Card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  blurRadius: 10,
                  color: Colors.black.withOpacity(0.06),
                  offset: const Offset(0, 4),
                )
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Cloud MQTT Details",
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 12),
                _field("MQTT Host / IP", _mqttIpController,
                    hint: "broker.hivemq.com"),
                _field("Port", _mqttPortController,
                    type: TextInputType.number, hint: "1883"),
                _field("Username (optional)", _mqttUsernameController),
                _field("Password (optional)", _mqttPasswordController,
                    obscure: true),
                _field("Topic", _mqttTopicController,
                    hint: "sustainabyte/irblaster"),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isSendingMqtt ? null : _sendMqttJsonToDevice,
                    icon: _isSendingMqtt
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_upload),
                    label: Text(_isSendingMqtt ? "Sending..." : "Send MQTT to device"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF009688),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Setpoint Card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _mqttSent ? Colors.white : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _mqttSent ? Colors.teal.shade200 : Colors.grey.shade300,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.thermostat,
                        color: _mqttSent ? Colors.teal : Colors.grey),
                    const SizedBox(width: 8),
                    const Text(
                      "Auto Temperature Set Point",
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  "OFF=25°C → AC OFF, ON=28°C → AC ON (Hysteresis control)",
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 12),

                _field(
                  "OFF Temperature (°C)",
                  _offTempController,
                  type: TextInputType.number,
                  enabled: _mqttSent,
                  hint: "25",
                ),
                _field(
                  "ON Temperature (°C)",
                  _onTempController,
                  type: TextInputType.number,
                  enabled: _mqttSent,
                  hint: "28",
                ),

                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: (_mqttSent && !_isSendingSetpoint)
                        ? _sendSetpointToDevice
                        : null,
                    icon: _isSendingSetpoint
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                    label: Text(_isSendingSetpoint
                        ? "Sending..."
                        : "Send Brand + Set Point"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _mqttSent ? Colors.teal : Colors.grey,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),

                if (!_mqttSent) ...[
                  const SizedBox(height: 10),
                  Text(
                    "⚠️ Send MQTT details first to enable Set Point.",
                    style:
                        TextStyle(fontSize: 12, color: Colors.orange.shade800),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
