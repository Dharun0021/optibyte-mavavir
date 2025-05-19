import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:esp/service/bluetooth_service.dart';

class AcCustomizationPage extends StatefulWidget {
  const AcCustomizationPage({super.key});

  @override
  State<AcCustomizationPage> createState() => _AcCustomizationPageState();
}

class _AcCustomizationPageState extends State<AcCustomizationPage> {
  final List<String> allBrands = [
    'LG', 'Samsung', 'Daikin', 'Voltas', 'Hitachi', 'Blue Star', 'Carrier',
    'Whirlpool', 'Panasonic', 'Godrej', 'Mitsubishi Electric', 'Haier',
    'Lloyd (by Havells)', 'O General', 'IFB', 'Toshiba', 'Electrolux', 'Cruise',
    'MarQ', 'Sansui', 'Hyundai', 'Kelvinator', 'Sharp', 'Sanyo', 'Croma',
  ];
  String searchQuery = '';
  String? selectedBrand;
  bool powerState = false;
  int temperature = 24;
  String selectedMode = 'Cool';

  final List<String> modes = ['Cool', 'Heat', 'Dry', 'Auto'];

  @override
  Widget build(BuildContext context) {
    List<String> filteredBrands = allBrands
        .where((brand) => brand.toLowerCase().contains(searchQuery.toLowerCase()))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customize AC', style: TextStyle(color: Colors.green)),
        backgroundColor: const Color(0xFF252039),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.green),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              decoration: const InputDecoration(
                labelText: 'Search Brand',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() {
                  searchQuery = value;
                });
              },
            ),
            const SizedBox(height: 10),
            if (searchQuery.isNotEmpty)
              ...filteredBrands.map((brand) => ListTile(
                title: Text(brand),
                trailing: selectedBrand == brand
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : null,
                onTap: () {
                  setState(() {
                    selectedBrand = brand;
                  });
                },
              )),
            if (selectedBrand != null) ...[
              const SizedBox(height: 20),
              const Text('Step 1: Power Control', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              SwitchListTile(
                title: Text(powerState ? 'Power: ON' : 'Power: OFF'),
                value: powerState,
                onChanged: (val) {
                  setState(() => powerState = val);
                },
              ),
              const SizedBox(height: 20),
              const Text('Step 2: Temperature Control', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle),
                    onPressed: () {
                      setState(() {
                        if (temperature > 16) temperature--;
                      });
                    },
                  ),
                  Text('$temperature°C', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.add_circle),
                    onPressed: () {
                      setState(() {
                        if (temperature < 30) temperature++;
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text('Step 3: Mode Selection', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              DropdownButton<String>(
                value: selectedMode,
                items: modes
                    .map((mode) => DropdownMenuItem(value: mode, child: Text(mode)))
                    .toList(),
                onChanged: (val) => setState(() => selectedMode = val!),
              ),
              const SizedBox(height: 30),
              Center(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final config = {
                      'type': 'custom',
                      'brand': selectedBrand,
                      'power': powerState ? 'ON' : 'OFF',
                      'temperature': temperature,
                      'mode': selectedMode,
                    };
                    String jsonConfig = jsonEncode(config);
                    print('Sending Custom Config: $jsonConfig');

                    try {
                      await BluetoothService().sendCommand("ac_config:$jsonConfig");
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Custom config sent to ESP32")),
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("Failed: $e")),
                      );
                    }
                  },
                  icon: const Icon(Icons.save),
                  label: const Text('Save Configuration'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 14.0),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
