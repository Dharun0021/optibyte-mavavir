import 'package:flutter/material.dart';
import 'package:esp/service/saved_remotes_storage.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

class AddRemotePage extends StatefulWidget {
   final BluetoothDevice device; // 👈 required

  const AddRemotePage({super.key, required this.device});
  

  @override
  State<AddRemotePage> createState() => _AddRemotePageState();
}

class _AddRemotePageState extends State<AddRemotePage> {
  final List<String> acBrands = const ["LG", "Samsung", "Voltas", "Daikin", "Other"];
  
  get yourBluetoothDevice => null;

  @override
  void initState() {
    super.initState();
    // reload saved brands on enter
    SavedRemotesStorage.loadSavedBrands();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Add Remote"),
        backgroundColor: Colors.lightBlue,
      ),
      body: FutureBuilder<bool>(
        future: _checkIfRemotesExist(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          } else if (!snapshot.data!) {
            return const Center(child: Text("Please configure the remote with a proper brand."));
          } else {
            final savedBrands = SavedRemotesStorage.savedBrands;
            return ListView.builder(
              itemCount: savedBrands.length,
              itemBuilder: (context, index) {
                final brand = savedBrands[index];
                return ListTile(
                  leading: Image.asset("assets/images/ac.jpg", width: 40),
                  title: Text(brand, style: const TextStyle(fontSize: 18)),
                  onTap: () {
                    Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => AddRemotePage(device: yourBluetoothDevice),
  ),
);
                  },
                );
              },
            );
          }
        },
      ),
    );
  }

  Future<bool> _checkIfRemotesExist() async {
    return SavedRemotesStorage.hasSavedRemotes();
  }
}
