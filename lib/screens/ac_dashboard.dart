import 'package:flutter/material.dart';

class AcDashboardPage extends StatelessWidget {
  final String model;
  final String mode;
  final String fan;
  final String temp;
  final String swing;
  final String state;

  const AcDashboardPage({
    super.key,
    required this.model,
    required this.mode,
    required this.fan,
    required this.temp,
    required this.swing,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final double temperature = double.tryParse(temp) ?? 24.0;

    return Scaffold(
      backgroundColor: const Color(0xFF90EE90),
      appBar: AppBar(
        backgroundColor: const Color(0xFF90EE90),
        elevation: 0,
        title: Text(model, style: const TextStyle(color: Colors.white)),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              dashboardIcon(Icons.ac_unit, mode),
              dashboardIcon(Icons.air, fan),
              dashboardIcon(Icons.sync_alt, swing),
              dashboardIcon(Icons.power_settings_new, state),
            ],
          ),
          const SizedBox(height: 40),
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                height: 180,
                width: 180,
                child: CircularProgressIndicator(
                  value: (temperature - 16) / (30 - 16),
                  strokeWidth: 12,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                  backgroundColor: Colors.white.withOpacity(0.2),
                ),
              ),
              Text(
                "$temp°",
                style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text("Swing Mode: $swing", style: const TextStyle(color: Colors.white70)),
          const Text("Room Temperature 78°", style: TextStyle(color: Colors.white70)),
          const Text("Humidity 45%", style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 30),
          ElevatedButton(
            onPressed: () {
              print("Power toggled: $state");
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            ),
            child: Text(
              state == "ON" ? "Power Off" : "Power On",
              style: const TextStyle(color: Color(0xFF1D8BF1), fontSize: 18),
            ),
          )
        ],
      ),
    );
  }

  Widget dashboardIcon(IconData icon, String label) {
    return Column(
      children: [
        CircleAvatar(
          radius: 30,
          backgroundColor: Colors.white.withOpacity(0.2),
          child: Icon(icon, color: Colors.white, size: 30),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(color: Colors.white)),
      ],
    );
  }
}
