import 'package:flutter/material.dart';
import 'package:esp/service/bluetooth_service.dart';

class AcCustomizationPage extends StatefulWidget {
  final String brand;

  const AcCustomizationPage({Key? key, required this.brand}) : super(key: key);

  @override
  State<AcCustomizationPage> createState() => _AcCustomizationPageState();
}

class _AcCustomizationPageState extends State<AcCustomizationPage> {
  String? selectedModel;

  final List<String> models = [
    'LG', 'Samsung', 'Daikin', 'Voltas', 'Hitachi', 'Blue Star', 'Carrier',
    'Whirlpool', 'Panasonic', 'Godrej', 'Mitsubishi', 'Haier', 'Toshiba',
    'IFB', 'Lloyd', 'Onida', 'Sansui', 'Videocon', 'Sanyo', 'Kelvinator',
  ];

  void startListeningIR() async {
    if (selectedModel == null || selectedModel!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a brand.")),
      );
      return;
    }

    try {
      await BluetoothService().sendCommand("start_listen:$selectedModel");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Listening for remote signals for $selectedModel...")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to send command: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE3F2FD),
      appBar: AppBar(
        title: const Text("Add Remote via IR"),
        backgroundColor: const Color(0xFF2196F3),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 5)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Select AC Brand", style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              DropdownButton<String>(
                isExpanded: true,
                value: selectedModel,
                hint: const Text("Select brand"),
                items: models.map((brand) => DropdownMenuItem(
                  value: brand,
                  child: Text(brand),
                )).toList(),
                onChanged: (val) => setState(() => selectedModel = val),
              ),
              const SizedBox(height: 30),
              ElevatedButton.icon(
                icon: const Icon(Icons.settings_remote),
                label: const Text("Start Listening IR"),
                onPressed: startListeningIR,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
