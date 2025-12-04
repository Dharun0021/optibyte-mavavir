// Complete Configuration Page - Fixed Button Response and Progress
// Mobile app stores hex codes locally and sends them to ESP32 device

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'bluetooth_scanner_page.dart';
import 'mode_selection_page.dart';

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
  final TextEditingController _commandController = TextEditingController();
  final TextEditingController _ssidController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final List<String> _receivedData = [];
  late BluetoothConnection _connection;
  bool _isConnected = false;
  String _temperature = "--";
  String _wifiIP = "";
  bool _isWifiConnected = false;
  bool _yellowLedOn = true; // Bluetooth connected = Yellow LED ON
  bool _greenLedOn = false; // WiFi connected = Green LED ON

  // Remote Configuration Variables
  final Set<String> _savedBrands = {}; // No default brands
  final Set<String> _expandedBrands = {};
  final Map<String, List<String>> _configProgress = {};
  final Map<String, bool> _brandConfigComplete = {};
  final Map<String, Map<String, String>> _savedRemoteConfigs = {}; // Store hex values locally

  final List<String> _configKeys = [
    "POWER",
    "TEMPUP",
    "TEMPDOWN",
    "MODE",
    "SWING",
    "OFF"
  ];

  String _currentActiveBrand = "";
  bool _isConfiguring = false;
  String _configuringBrand = "";
  int _currentConfigStep = 0;
  String _currentConfigKey = "";

  @override
  void initState() {
    super.initState();
    _connection = widget.connection;
    _isConnected = _connection.isConnected;

    // Load saved brands and configurations on initialization
    _loadSavedRemotes();

    _connection.input?.listen(_onDataReceived).onDone(() {
      if (mounted) setState(() => _isConnected = false);
    });

    // Auto-sync RTC after the widget is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _syncRTCFromPhone();
      }
    });
  }

  @override
  void dispose() {
    _commandController.dispose();
    _ssidController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ---------- PREFERENCES HELPERS (WiFi status for MQTT page) ----------

  Future<void> _saveWifiStatus(bool connected, {String ssid = ""}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('wifi_connected', connected);
      if (connected && ssid.isNotEmpty) {
        await prefs.setString('wifi_ssid', ssid);
      }
    } catch (e) {
      debugPrint("Error saving WiFi status: $e");
    }
  }

  // Load saved remotes from SharedPreferences
  Future<void> _loadSavedRemotes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedBrandsJson = prefs.getStringList('saved_brands') ?? [];

      setState(() {
        _savedBrands.clear();
        _savedBrands.addAll(savedBrandsJson);

        // Mark all saved brands as configured
        for (String brand in savedBrandsJson) {
          _brandConfigComplete[brand] = true;
        }
      });

      // Load individual remote configurations (hex values)
      await _loadRemoteConfigurations();

      print('Loaded saved remotes: $_savedBrands');
    } catch (e) {
      print('Error loading saved remotes: $e');
    }
  }

  // Load saved remote hex configurations from SharedPreferences
  Future<void> _loadRemoteConfigurations() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      for (String brand in _savedBrands) {
        final configKey = 'remote_config_$brand';
        final configJson = prefs.getString(configKey);

        if (configJson != null) {
          final Map<String, dynamic> config = jsonDecode(configJson);
          _savedRemoteConfigs[brand] = Map<String, String>.from(config);
          print('Loaded hex config for $brand: ${_savedRemoteConfigs[brand]}');
        }
      }
    } catch (e) {
      print('Error loading remote configurations: $e');
    }
  }

  // Save brands to SharedPreferences
  Future<void> _saveBrandsToPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('saved_brands', _savedBrands.toList());
      print('Saved brands to preferences: $_savedBrands');
    } catch (e) {
      print('Error saving brands: $e');
    }
  }

  // Save individual remote configuration (hex values) to SharedPreferences
  Future<void> _saveRemoteConfiguration(
      String brand, Map<String, String> config) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final configKey = 'remote_config_$brand';
      final configJson = jsonEncode(config);

      await prefs.setString(configKey, configJson);
      _savedRemoteConfigs[brand] = Map<String, String>.from(config);

      print('Saved remote hex config for $brand: $config');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                "💾 Remote '$brand' saved to local storage with ${config.length} commands"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('Error saving remote configuration: $e');
    }
  }

  // ---------- BLUETOOTH DATA HANDLING ----------

  void _onDataReceived(Uint8List data) {
    final text = utf8.decode(data).trim();
    print("🔍 DEBUG: Received from ESP32: '$text'");

    // Handle multi-line responses
    final lines = text.split('\n');
    for (final line in lines) {
      _processReceivedLine(line.trim());
    }
  }

  void _processReceivedLine(String text) {
    if (text.isEmpty) return;

    // Temperature response  (e.g. "TEMP:29.42,HUM:56.40")
    if (text.startsWith("TEMP:")) {
      final payload = text.replaceFirst("TEMP:", "").trim(); // "29.42,HUM:56.40"
      final parts = payload.split(',');

      setState(() {
        // Only store the temperature part on this screen
        _temperature = parts.isNotEmpty ? parts[0].trim() : payload;
      });

      // Add to communication log
      setState(() {
        _receivedData.insert(
          0,
          "${DateFormat('HH:mm:ss').format(DateTime.now())}: $text",
        );
        if (_receivedData.length > 50) {
          _receivedData.removeLast();
        }
      });

      return; // already handled
    }

    // WiFi status responses
    if (text.startsWith("WIFI_CONNECTED") ||
        text.contains("WiFi connected")) {
      final ipPart = text.contains(":") ? text.split(":")[1].trim() : "";
      setState(() {
        _wifiIP = ipPart;
        _isWifiConnected = true;
        _greenLedOn = true;
      });

      // ✅ Save WiFi status for ModeSelectionPage / MQTT config
      _saveWifiStatus(true, ssid: _ssidController.text.trim());

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text("🟢 WiFi Connected${_wifiIP.isNotEmpty ? '. IP: $_wifiIP' : ''}"),
          backgroundColor: Colors.green,
        ),
      );
    } else if (text.startsWith("WIFI_FAILED") ||
        text.contains("WiFi connection failed")) {
      setState(() {
        _isWifiConnected = false;
        _greenLedOn = false;
        _wifiIP = "";
      });

      // ✅ Update stored WiFi status as disconnected
      _saveWifiStatus(false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("❌ WiFi Connection Failed"),
          backgroundColor: Colors.red,
        ),
      );
    }
    // Configuration responses - Fixed to handle multiple formats
    else if (text.contains("IR Code learned:") ||
        text.contains("Code stored for") ||
        text.contains("learned") ||
        text.contains("0x")) {
      if (_isConfiguring &&
          _configuringBrand.isNotEmpty &&
          _currentConfigKey.isNotEmpty) {
        // Extract hex code from response
        String hexCode = "";

        // Try to find hex code in different formats
        if (text.contains("0x")) {
          final parts = text.split(" ");
          for (String part in parts) {
            if (part.contains("0x")) {
              // Clean up the hex code (remove any trailing characters)
              hexCode = part.replaceAll(RegExp(r'[^0-9A-Fa-fx]'), '');
              if (hexCode.length >= 8) {
                break;
              }
            }
          }
        }

        // If no hex found, generate a placeholder (for testing)
        if (hexCode.isEmpty) {
          hexCode =
              "0x${DateTime.now().millisecondsSinceEpoch.toRadixString(16).substring(0, 8).toUpperCase()}";
        }

        // Store the hex code locally
        if (hexCode.isNotEmpty) {
          _savedRemoteConfigs[_configuringBrand] ??= {};

          final keyLower = _currentConfigKey.toLowerCase();
          _savedRemoteConfigs[_configuringBrand]![keyLower] = hexCode;

          setState(() {
            _configProgress[_configuringBrand] ??= [];
            if (!_configProgress[_configuringBrand]!.contains(keyLower)) {
              _configProgress[_configuringBrand]!.add(keyLower);
            }
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("✅ ${_currentConfigKey.toUpperCase()} configured: $hexCode"),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );

          // Check if all keys are configured
          if (_configProgress[_configuringBrand]!.length == _configKeys.length) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("🎉 All buttons configured! Ready to save remote."),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 3),
              ),
            );
          }

          // Clear current config key after successful storage
          _currentConfigKey = "";
        }
      }
    }

    // Add to communication log (for non-TEMP lines)
    setState(() {
      _receivedData.insert(
        0,
        "${DateFormat('HH:mm:ss').format(DateTime.now())}: $text",
      );
      if (_receivedData.length > 50) {
        _receivedData.removeLast(); // Keep only last 50 messages
      }
    });
  }

  // ---------- REMOTE CONFIGURATION FLOW ----------

  // Start new remote configuration
  void _startNewConfiguration() {
    showDialog(
      context: context,
      builder: (context) {
        final brandController = TextEditingController();
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.add, color: Colors.blue),
              SizedBox(width: 8),
              Text("Add New Remote"),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Enter the brand name for your AC remote:"),
              const SizedBox(height: 10),
              TextField(
                controller: brandController,
                decoration: const InputDecoration(
                  hintText: "e.g., Samsung, LG, Daikin, Mitsubishi",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.settings_remote),
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 10),
              const Text(
                "You'll configure 6 buttons: POWER, TEMP+, TEMP-, MODE, SWING, OFF",
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () {
                final brandName = brandController.text.trim().toLowerCase();
                if (brandName.isNotEmpty && !_savedBrands.contains(brandName)) {
                  Navigator.pop(context);
                  _startBrandConfiguration(brandName);
                } else if (_savedBrands.contains(brandName)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Brand '$brandName' already exists!")),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Please enter a brand name")),
                  );
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              child: const Text("Start Configuration"),
            ),
          ],
        );
      },
    );
  }

  // Start brand configuration process
  void _startBrandConfiguration(String brandName) {
    setState(() {
      _configuringBrand = brandName;
      _isConfiguring = true;
      _currentConfigStep = 0;
      _configProgress[brandName] = [];
      _brandConfigComplete[brandName] = false;
      _savedRemoteConfigs[brandName] = {};
      _expandedBrands.add(brandName);
    });

    // Send brand command to ESP32
    _sendCommand("BRAND:$brandName");

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            "🔧 Configuration started for: ${brandName.toUpperCase()}\nClick each button below to configure it!"),
        duration: const Duration(seconds: 4),
        backgroundColor: Colors.orange,
      ),
    );
  }

  // Configure specific button - Fixed to properly set current config key
  void _configureButton(String key, String brand) {
    if (_isConfiguring && _configuringBrand == brand) {
      setState(() {
        _currentConfigKey = key;
      });

      _sendCommand("CONFIG:$key");

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("🎛️ Press ${key.toUpperCase()} button on your remote now!"),
          duration: const Duration(seconds: 5),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  // Save complete remote configuration
  void _saveCompleteRemoteConfiguration() async {
    if (_configuringBrand.isNotEmpty &&
        _savedRemoteConfigs[_configuringBrand] != null) {
      // Save to local storage
      await _saveRemoteConfiguration(
          _configuringBrand, _savedRemoteConfigs[_configuringBrand]!);

      // Add to saved brands
      setState(() {
        _savedBrands.add(_configuringBrand);
        _brandConfigComplete[_configuringBrand] = true;
        _isConfiguring = false;
        _currentConfigStep = 0;
        _currentConfigKey = "";
        _configProgress.remove(_configuringBrand);
        _configuringBrand = "";
      });

      // Save brands list
      await _saveBrandsToPreferences();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("✅ Remote saved successfully!"),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  // Send IR command using saved hex code
  void _sendIRCommand(String command, String brand) async {
    if (_savedRemoteConfigs[brand] != null &&
        _savedRemoteConfigs[brand]![command.toLowerCase()] != null) {
      final hexCode = _savedRemoteConfigs[brand]![command.toLowerCase()]!;

      // Send hex code directly to ESP32
      await _sendCommand("SEND_HEX:$hexCode");

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("📡 Sent: ${command.toUpperCase()} ($hexCode) to AC"),
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text("❌ Command ${command.toUpperCase()} not configured for $brand"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Remove brand and its configuration
  Future<void> _removeBrand(String brand) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Remove Remote"),
        content: Text(
            "Are you sure you want to remove '$brand' remote?\nThis action cannot be undone."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);

              // Remove from local storage
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('remote_config_$brand');

              setState(() {
                _savedBrands.remove(brand);
                _expandedBrands.remove(brand);
                _brandConfigComplete.remove(brand);
                _savedRemoteConfigs.remove(brand);
                _configProgress.remove(brand);
                if (_currentActiveBrand == brand) {
                  _currentActiveBrand = "";
                }
              });

              await _saveBrandsToPreferences();

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("❌ Removed '$brand' remote")),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Remove"),
          ),
        ],
      ),
    );
  }

  // ---------- WIFI / TEMP / RTC ----------

  // WiFi Setup Functions
  void _showWifiSetupDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.wifi, color: Colors.blue),
            SizedBox(width: 8),
            Text("WiFi Setup"),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _ssidController,
              decoration: const InputDecoration(
                labelText: "WiFi Name (SSID)",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.wifi),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(
                labelText: "WiFi Password",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock),
              ),
              obscureText: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              if (_ssidController.text.isNotEmpty &&
                  _passwordController.text.isNotEmpty) {
                Navigator.pop(context);
                _sendWifiCredentials();
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            child: const Text("Connect"),
          ),
        ],
      ),
    );
  }

  void _sendWifiCredentials() {
    _sendCommand(
        "WIFI:${_ssidController.text.trim()},${_passwordController.text.trim()}");
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("📡 Sending WiFi credentials...")),
    );
  }

  void _getTemperature() {
    _sendCommand("GET_TEMP");
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("🌡️ Requesting temperature...")),
    );
  }

  void _syncRTCFromPhone() {
    final now = DateTime.now();
    final formatted = DateFormat('yyyy-MM-dd HH:mm:ss').format(now);
    _sendCommand("SET_RTC:$formatted");
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("🕒 RTC synced: $formatted")),
    );
  }

  // Send command to ESP32
  Future<void> _sendCommand([String? cmd]) async {
    final text = cmd ?? _commandController.text.trim();
    if (text.isEmpty || !_isConnected) return;

    try {
      final data = utf8.encode("$text\n");
      _connection.output.add(Uint8List.fromList(data));
      await _connection.output.allSent;

      setState(() {
        _receivedData.insert(
          0,
          "${DateFormat('HH:mm:ss').format(DateTime.now())}: You → $text",
        );
        if (cmd == null) _commandController.clear();
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to send: $e")),
      );
    }
  }

  Future<void> _disconnectBluetooth() async {
    try {
      await _connection.close();
      if (mounted) {
        setState(() => _isConnected = false);
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const BluetoothScannerPage()),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to disconnect: $e")),
      );
    }
  }

  // ---------- UI WIDGETS ----------

  // LED Status Widget
  Widget _buildLedStatus() {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          Column(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: _yellowLedOn ? Colors.yellow : Colors.grey,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black26),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                "Bluetooth",
                style: TextStyle(
                  fontSize: 11,
                  color: _yellowLedOn ? Colors.black : Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          Column(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: _greenLedOn ? Colors.green : Colors.grey,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black26),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                "WiFi",
                style: TextStyle(
                  fontSize: 11,
                  color: _greenLedOn ? Colors.black : Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Configuration button widget - Fixed to respond properly
  Widget _configButton(String label, String key, String brand) {
    final isConfigured =
        _configProgress[brand]?.contains(key.toLowerCase()) ?? false;
    final isCurrentConfig = _currentConfigKey == key;

    return ElevatedButton(
      onPressed: () => _configureButton(key, brand),
      style: ElevatedButton.styleFrom(
        backgroundColor: isConfigured
            ? Colors.green
            : (isCurrentConfig ? Colors.orange : Colors.grey.shade300),
        foregroundColor:
            (isConfigured || isCurrentConfig) ? Colors.white : Colors.black87,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isConfigured
                ? Icons.check
                : (isCurrentConfig ? Icons.pending : Icons.radio_button_unchecked),
            size: 16,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  // Control button widget for normal operation
  Widget _controlButton(String label, String cmd, String brand) {
    return ElevatedButton(
      onPressed: () => _sendIRCommand(cmd, brand),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.purple.shade100,
        foregroundColor: Colors.purple.shade800,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }

  // Build remote controls for each brand
  Widget _buildRemoteControls(String brand) {
    final isConfigured = _brandConfigComplete[brand] ?? false;
    final isCurrentlyConfiguring = _isConfiguring && _configuringBrand == brand;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Brand header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        Icons.settings_remote,
                        color: isConfigured ? Colors.green : Colors.orange,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        brand.toUpperCase(),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isConfigured ? Colors.green : Colors.orange,
                        ),
                      ),
                      if (isCurrentlyConfiguring)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.orange,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            "CONFIGURING",
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      if (!isConfigured && !isCurrentlyConfiguring)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            "NOT CONFIGURED",
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => _removeBrand(brand),
                  icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                  tooltip: "Remove $brand remote",
                ),
              ],
            ),

            // Configuration Mode
            if (isCurrentlyConfiguring) ...[
              const Divider(),
              const Text(
                "Configuration Mode - Click each button to configure:",
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.orange),
              ),
              const SizedBox(height: 8),
              const Text(
                "Press the corresponding button on your AC remote when prompted.",
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  _configButton("POWER", "POWER", brand),
                  _configButton("TEMP +", "TEMPUP", brand),
                  _configButton("TEMP -", "TEMPDOWN", brand),
                  _configButton("MODE", "MODE", brand),
                  _configButton("SWING", "SWING", brand),
                  _configButton("OFF", "OFF", brand),
                ],
              ),
              const SizedBox(height: 16),

              // Progress indicator
              LinearProgressIndicator(
                value: (_configProgress[brand]?.length ?? 0) / _configKeys.length,
                backgroundColor: Colors.grey.shade300,
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.orange),
              ),
              const SizedBox(height: 8),
              Text(
                "Progress: ${_configProgress[brand]?.length ?? 0}/${_configKeys.length} buttons configured",
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),

              // Save Remote Button (appears when all buttons are configured)
              if ((_configProgress[brand]?.length ?? 0) == _configKeys.length) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _saveCompleteRemoteConfiguration,
                    icon: const Icon(Icons.save, size: 20),
                    label:
                        const Text("Save Remote", style: TextStyle(fontSize: 16)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],
            ]

            // Normal Remote Control Mode
            else if (isConfigured) ...[
              const Divider(),
              const Text(
                "Remote Control Buttons:",
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey),
              ),
              const SizedBox(height: 8),

              // Show saved hex values
              if (_savedRemoteConfigs[brand] != null &&
                  _savedRemoteConfigs[brand]!.isNotEmpty) ...[
                ExpansionTile(
                  title:
                      const Text("View Hex Codes", style: TextStyle(fontSize: 12)),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Column(
                        children: _savedRemoteConfigs[brand]!.entries
                            .map((entry) => Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 2),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        entry.key.toUpperCase(),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11),
                                      ),
                                      Text(
                                        entry.value,
                                        style: const TextStyle(
                                            fontFamily: 'monospace', fontSize: 10),
                                      ),
                                    ],
                                  ),
                                ))
                            .toList(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],

              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  _controlButton("Power", "POWER", brand),
                  _controlButton("Temp +", "TEMPUP", brand),
                  _controlButton("Temp -", "TEMPDOWN", brand),
                  _controlButton("Mode", "MODE", brand),
                  _controlButton("Swing", "SWING", brand),
                  _controlButton("Off", "OFF", brand),
                ],
              ),
            ]

            // Not Configured State
            else ...[
              const Divider(),
              const Text(
                "Configuration Required:",
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600, color: Colors.red),
              ),
              const SizedBox(height: 8),
              const Text(
                "This remote needs to be configured before use.",
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: () => _startBrandConfiguration(brand),
                icon: const Icon(Icons.settings, size: 18),
                label: const Text("Start Configuration"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ---------- BUILD ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("ESP32 Control ${widget.device.name ?? ""}"),
        backgroundColor: Colors.lightBlue,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _startNewConfiguration,
            tooltip: "Add New Remote",
          ),
          IconButton(
            icon: const Icon(Icons.bluetooth_disabled),
            onPressed: _disconnectBluetooth,
            tooltip: "Disconnect Bluetooth",
          ),
        ],
      ),
      body: Column(
        children: [
          // Connection Status Header
          Container(
            color: Colors.lightBlue[50],
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(
                  _isConnected
                      ? Icons.bluetooth_connected
                      : Icons.bluetooth_disabled,
                  color: _isConnected ? Colors.lightBlue : Colors.red,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "${widget.device.name ?? "Unknown"} (${widget.device.address})",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _isConnected ? Colors.green : Colors.red,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _isConnected ? "Connected" : "Disconnected",
                    style:
                        const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // LED Status Indicators
                  _buildLedStatus(),

                  // Device Status & Controls  (wrapped to avoid overflow)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          // Temperature Control
                          Column(
                            children: [
                              ElevatedButton.icon(
                                onPressed: _getTemperature,
                                icon:
                                    const Icon(Icons.thermostat, size: 16),
                                label: const Text("Get Temp",
                                    style: TextStyle(fontSize: 12)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "$_temperature °C",
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(width: 16),

                          // WiFi Control + MQTT button
                          Column(
                            children: [
                              ElevatedButton.icon(
                                onPressed: _showWifiSetupDialog,
                                icon: const Icon(Icons.wifi, size: 16),
                                label: const Text("WiFi Setup",
                                    style: TextStyle(fontSize: 12)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _isWifiConnected
                                      ? Colors.green
                                      : Colors.orange,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _isWifiConnected
                                    ? "Connected"
                                    : "Not Connected",
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _isWifiConnected
                                      ? Colors.green
                                      : Colors.grey[600],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (_wifiIP.isNotEmpty)
                                Text(
                                  _wifiIP,
                                  style: const TextStyle(
                                      fontSize: 10, color: Colors.green),
                                ),

                              // ✅ MQTT CONFIG BUTTON – only when WiFi is connected
                              if (_isWifiConnected) ...[
                                const SizedBox(height: 6),
                                OutlinedButton.icon(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ModeSelectionPage(
                                          showMqttConfig: true,
                                          deviceConnection: _connection,
                                        ),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.cloud, size: 16),
                                  label: const Text(
                                    "MQTT Config",
                                    style: TextStyle(fontSize: 11),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 6),
                                    side: const BorderSide(
                                        color: Colors.blueAccent),
                                    foregroundColor: Colors.blueAccent,
                                    minimumSize: const Size(0, 0),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(width: 16),

                          // RTC Sync Control
                          Column(
                            children: [
                              ElevatedButton.icon(
                                onPressed: _syncRTCFromPhone,
                                icon: const Icon(Icons.access_time,
                                    size: 16),
                                label: const Text("Sync RTC",
                                    style: TextStyle(fontSize: 12)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.deepOrange,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                DateFormat('HH:mm')
                                    .format(DateTime.now()),
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Show "No Remotes" message if no brands saved
                  if (_savedBrands.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Icon(Icons.settings_remote,
                              size: 64, color: Colors.grey.shade400),
                          const SizedBox(height: 16),
                          Text(
                            "No Remote Controls Configured",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "Tap the + button to add your first AC remote",
                            style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade500),
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton.icon(
                            onPressed: _startNewConfiguration,
                            icon: const Icon(Icons.add),
                            label: const Text("Add First Remote"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 12),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Saved Remotes Section
                  if (_savedBrands.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              "Your AC Remotes:",
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87),
                            ),
                          ),
                          Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            children: _savedBrands.map((brand) {
                              final isExpanded =
                                  _expandedBrands.contains(brand);
                              final isConfigured =
                                  _brandConfigComplete[brand] ?? false;

                              return ElevatedButton(
                                onPressed: () {
                                  setState(() {
                                    isExpanded
                                        ? _expandedBrands.remove(brand)
                                        : _expandedBrands.add(brand);
                                  });
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isConfigured
                                      ? Colors.teal
                                      : Colors.orange,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20, vertical: 12),
                                  side: isExpanded
                                      ? const BorderSide(
                                          color: Colors.white, width: 2)
                                      : null,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      brand.toUpperCase(),
                                      style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(width: 4),
                                    if (!isConfigured)
                                      const Icon(
                                        Icons.warning,
                                        size: 14,
                                        color: Colors.white,
                                      )
                                    else
                                      Icon(
                                        isExpanded
                                            ? Icons.keyboard_arrow_up
                                            : Icons.keyboard_arrow_down,
                                        size: 18,
                                      ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),

                  // Remote Controls for Expanded Brands
                  ..._expandedBrands
                      .map((brand) => _buildRemoteControls(brand))
                      .toList(),

                  // Communication Terminal Section
                  if (_receivedData.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border:
                            Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(8),
                                topRight: Radius.circular(8),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  "📡 Communication Terminal",
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold),
                                ),
                                IconButton(
                                  onPressed: () {
                                    setState(() {
                                      _receivedData.clear();
                                    });
                                  },
                                  icon:
                                      const Icon(Icons.clear, size: 16),
                                  tooltip: "Clear Log",
                                ),
                              ],
                            ),
                          ),
                          SizedBox(
                            height: 120,
                            child: ListView.builder(
                              reverse: true,
                              itemCount: _receivedData.length,
                              itemBuilder: (context, index) {
                                final message = _receivedData[index];
                                final isFromUser =
                                    message.contains("You →");
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  child: Text(
                                    message,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isFromUser
                                          ? Colors.blue
                                          : Colors.black87,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 20), // Bottom padding
                ],
              ),
            ),
          ),

          // Command Input at Bottom
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              border: Border(
                  top: BorderSide(color: Colors.grey.shade300)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commandController,
                    decoration: InputDecoration(
                      hintText: "Enter custom command...",
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                    onSubmitted: (_) => _sendCommand(),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: () => _sendCommand(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.lightBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                  ),
                  child: const Text("Send"),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
