import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:location/location.dart';  // Add this import

class BluetoothService {
  final FlutterBluetoothSerial _bluetooth = FlutterBluetoothSerial.instance;
  BluetoothConnection? connection;
  StreamSubscription<Uint8List>? _dataSubscription;
  StreamController<List<BluetoothDevice>>? _devicesController;
  Function(String)? onDataReceived;
  Function(String)? onError;
  Function(String)? onSuccess;
  Function()? onDisconnected;

  // Initialize Bluetooth and request permissions
  Future<void> initialize() async {
    try {
      // Request required permissions
      for (var permission in [
        Permission.bluetooth,
        Permission.bluetoothConnect,
        Permission.bluetoothScan,
        Permission.bluetoothAdvertise,
        Permission.location
      ]) {
        if (await permission.isDenied) {
          await permission.request();
        }
      }

      // Check if location services are enabled
      var locationServiceStatus = await Location().serviceEnabled();
      if (!locationServiceStatus) {
        bool isEnabled = await Location().requestService();
        if (!isEnabled) {
          onError?.call('Location services are required for Bluetooth scanning.');
          return;
        }
      }

      // Check if Bluetooth is enabled
      bool? isBluetoothEnabled = await _bluetooth.isEnabled;
      if (isBluetoothEnabled != true) {
        await _bluetooth.requestEnable();
      }
    } catch (e) {
      onError?.call('Please enable Bluetooth and location services manually.');
    }
  }

  // Start scanning for devices
  Stream<List<BluetoothDevice>> startScan() {
    _devicesController?.close();
    _devicesController = StreamController<List<BluetoothDevice>>();
    List<BluetoothDevice> currentDevices = [];

    _bluetooth.startDiscovery().listen(
          (BluetoothDiscoveryResult result) {
        final device = result.device;
        final existingIndex = currentDevices.indexWhere((d) => d.address == device.address);

        if (existingIndex >= 0) {
          currentDevices[existingIndex] = device;
        } else {
          currentDevices.add(device);
        }

        _devicesController?.add(List.from(currentDevices));
      },
      onDone: () {
        onSuccess?.call('Scan completed');
        _devicesController?.close();
      },
      onError: (error) {
        onError?.call('Failed to scan devices. Please check your Bluetooth settings and try again.');
        _devicesController?.close();
      },
    );

    return _devicesController!.stream;
  }

  // Cancel scanning
  void cancelScan() {
    _bluetooth.cancelDiscovery();
    _devicesController?.close();
    _devicesController = null;
  }

  // Connect to a Bluetooth device
  Future<void> connectToDevice(BluetoothDevice device) async {
    try {
      connection = await BluetoothConnection.toAddress(device.address)
          .timeout(const Duration(seconds: 8), onTimeout: () {
        throw TimeoutException('Connection timed out');
      });

      if (connection != null && connection!.isConnected) {
        _setupDataListener();
        onSuccess?.call('Connected to ${device.name ?? "the device"}');
      } else {
        throw Exception('Connection failed to establish');
      }
    } catch (e) {
      String message = (e is TimeoutException)
          ? 'Connection attempt timed out. Please try again.'
          : 'Unable to connect to the selected device. Please check if it is powered on and within range.';
      onError?.call(message);
      await disconnect();
    }
  }

  // Set up data listener
  void _setupDataListener() {
    _dataSubscription?.cancel();

    _dataSubscription = connection!.input!.listen(
          (Uint8List data) {
        String receivedString = utf8.decode(data);
        onDataReceived?.call(receivedString);
      },
      onError: (error) {
        _handleConnectionError();
      },
      onDone: () {
        _handleConnectionError();
      },
      cancelOnError: true,
    );
  }

  // Send command to device
  Future<void> sendCommand(String command) async {
    if (connection?.isConnected != true) {
      onError?.call('Not connected to any device. Please connect first.');
      return;
    }

    try {
      final commandBytes = utf8.encode('$command\r\n');
      connection!.output.add(Uint8List.fromList(commandBytes));
      await connection!.output.allSent;
    } catch (e) {
      onError?.call('Failed to send command. Please try again.');
    }
  }

  // Handle connection error
  void _handleConnectionError() {
    disconnect();
    onError?.call('The Bluetooth connection was lost. Please reconnect.');
  }

  // Disconnect Bluetooth
  Future<void> disconnect() async {
    try {
      await _dataSubscription?.cancel();
      await connection?.finish();
      await connection?.close();
    } finally {
      connection = null;
      _dataSubscription = null;
      onDisconnected?.call();
    }
  }

  // Check if connected
  bool get isConnected => connection?.isConnected == true;

  // Dispose resources
  void dispose() {
    cancelScan();
    disconnect();
  }
}
