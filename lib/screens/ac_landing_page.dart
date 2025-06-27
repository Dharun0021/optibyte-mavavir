import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:esp/screens/ac_dashboard.dart';
import 'package:esp/screens/ac_customization_page.dart';
import 'package:esp/service/bluetooth_service.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

DateTime? startDateTime;
DateTime? endDateTime;

class AcConfigurationPage extends StatefulWidget {
  final BluetoothConnection connection;
  const AcConfigurationPage({super.key, required this.connection});

  @override
  State<AcConfigurationPage> createState() => _AcConfigurationPageState();
}

class _AcConfigurationPageState extends State<AcConfigurationPage> {
  String? selectedModel = 'select the ac Model';
  String? selectedTemp = '24';
  String selectedSwing = 'off';
  bool isPowerOn = false;

  final List<String> models = [
    'select the ac Model', 'LG', 'Samsung', 'Daikin', 'Voltas', 'Hitachi', 'Blue Star', 'Carrier',
    'Whirlpool', 'Panasonic', 'Godrej', 'Mitsubishi', 'Haier', 'Toshiba',
    'IFB', 'Lloyd', 'Onida', 'Sansui', 'Videocon', 'Sanyo', 'Kelvinator',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F3FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF02CCFE),
        title: const Text('AC Configuration', style: TextStyle(color: Colors.black)),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            buildDropdown("Select AC Brand:", models, selectedModel, (val) async {
              setState(() => selectedModel = val);
              await BluetoothService().sendCommand("brand:$val");
            }),
            const SizedBox(height: 20),
            buildPowerSection(),
            const SizedBox(height: 20),
            buildTemperatureSelector(),
            const SizedBox(height: 20),
            buildSwingToggle(),
            const SizedBox(height: 20),
            buildTimerPicker("Set Timer:", context),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: sendConfiguration,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text("Submit", style: TextStyle(fontSize: 16, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AcCustomizationPage(brand: selectedModel ?? 'Unknown'),
            ),
          );
        },
        backgroundColor: Colors.blue,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget buildDropdown(String label, List<String> items, String? selectedValue, Function(String?) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF7F7FA),
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
            ],
          ),
          child: DropdownButton<String>(
            value: selectedValue,
            isExpanded: true,
            underline: Container(),
            icon: const Icon(Icons.keyboard_arrow_down),
            items: items.map((item) => DropdownMenuItem(
              value: item,
              child: Text(item),
            )).toList(),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget buildPowerSection() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text("Power:", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
        GestureDetector(
          onTap: () async {
            setState(() => isPowerOn = !isPowerOn);
            await BluetoothService().sendCommand(isPowerOn ? "ac_power_on" : "ac_power_off");
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 90,
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              color: isPowerOn ? Colors.green : Colors.redAccent,
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                )
              ],
            ),
            alignment: isPowerOn ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isPowerOn ? Icons.power : Icons.power_off,
                color: isPowerOn ? Colors.green : Colors.redAccent,
                size: 20,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget buildTemperatureSelector() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text("${selectedTemp}°", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: () async {
                setState(() {
                  int temp = int.parse(selectedTemp!);
                  if (temp > 16) selectedTemp = (temp - 1).toString();
                });
                await BluetoothService().sendCommand("temp:$selectedTemp");
              },
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () async {
                setState(() {
                  int temp = int.parse(selectedTemp!);
                  if (temp < 30) selectedTemp = (temp + 1).toString();
                });
                await BluetoothService().sendCommand("temp:$selectedTemp");
              },
            ),
          ],
        )
      ],
    );
  }

  Widget buildSwingToggle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Set Swing:", style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Text("Horizontal", style: TextStyle(fontSize: 16)),
                Switch(
                  value: selectedSwing == 'Horizontal' || selectedSwing == 'Both',
                  onChanged: (bool value) async {
                    setState(() {
                      if (value) {
                        selectedSwing = selectedSwing == 'Vertical' ? 'Both' : 'Horizontal';
                      } else {
                        selectedSwing = selectedSwing == 'Both' ? 'Vertical' : 'Off';
                      }
                    });
                    await BluetoothService().sendCommand("swing:$selectedSwing");
                  },
                ),
              ],
            ),
            Row(
              children: [
                const Text("Vertical", style: TextStyle(fontSize: 16)),
                Switch(
                  value: selectedSwing == 'Vertical' || selectedSwing == 'Both',
                  onChanged: (bool value) async {
                    setState(() {
                      if (value) {
                        selectedSwing = selectedSwing == 'Horizontal' ? 'Both' : 'Vertical';
                      } else {
                        selectedSwing = selectedSwing == 'Both' ? 'Horizontal' : 'Off';
                      }
                    });
                    await BluetoothService().sendCommand("swing:$selectedSwing");
                  },
                ),
              ],
            ),
          ],
        )
      ],
    );
  }

  Widget buildTimerPicker(String label, BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            OutlinedButton(
              onPressed: () async {
                final pickedDate = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now(),
                  firstDate: DateTime.now(),
                  lastDate: DateTime(2100),
                );
                if (pickedDate != null) {
                  final pickedTime = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.now(),
                  );
                  if (pickedTime != null) {
                    setState(() {
                      startDateTime = DateTime(
                        pickedDate.year,
                        pickedDate.month,
                        pickedDate.day,
                        pickedTime.hour,
                        pickedTime.minute,
                      );
                    });
                    await BluetoothService().sendCommand("start_time:${startDateTime!.toIso8601String()}");
                  }
                }
              },
              style: OutlinedButton.styleFrom(shape: const StadiumBorder()),
              child: Text(
                startDateTime != null
                    ? '${startDateTime!.day}/${startDateTime!.month}/${startDateTime!.year} ${startDateTime!.hour.toString().padLeft(2, '0')}:${startDateTime!.minute.toString().padLeft(2, '0')}'
                    : "Start Date & Time",
                style: const TextStyle(fontSize: 16),
              ),
            ),
            OutlinedButton(
              onPressed: () async {
                final pickedDate = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now(),
                  firstDate: DateTime.now(),
                  lastDate: DateTime(2100),
                );
                if (pickedDate != null) {
                  final pickedTime = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.now(),
                  );
                  if (pickedTime != null) {
                    setState(() {
                      endDateTime = DateTime(
                        pickedDate.year,
                        pickedDate.month,
                        pickedDate.day,
                        pickedTime.hour,
                        pickedTime.minute,
                      );
                    });
                    await BluetoothService().sendCommand("end_time:${endDateTime!.toIso8601String()}");
                  }
                }
              },
              style: OutlinedButton.styleFrom(shape: const StadiumBorder()),
              child: Text(
                endDateTime != null
                    ? '${endDateTime!.day}/${endDateTime!.month}/${endDateTime!.year} ${endDateTime!.hour.toString().padLeft(2, '0')}:${endDateTime!.minute.toString().padLeft(2, '0')}'
                    : "End Date & Time",
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> sendConfiguration() async {
    final payload = {
      'type': 'standard',
      'model': selectedModel,
      'temp': selectedTemp,
      'swing': selectedSwing,
      'power': isPowerOn,
      'start_time': startDateTime?.toIso8601String(),
      'end_time': endDateTime?.toIso8601String(),
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
          mode: '-',
          fan: '-',
          temp: selectedTemp ?? '',
          swing: selectedSwing,
          state: isPowerOn ? 'ON' : 'OFF',
        ),
      ),
    );
  }
}
