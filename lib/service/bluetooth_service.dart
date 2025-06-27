import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:location/location.dart';

class BluetoothService {
  static final BluetoothService _instance = BluetoothService._internal();
  factory BluetoothService() => _instance;
  BluetoothService._internal();

  final FlutterBluetoothSerial _bluetooth = FlutterBluetoothSerial.instance;
  BluetoothConnection? connection;
  StreamSubscription<Uint8List>? _dataSubscription;
  StreamController<List<BluetoothDevice>>? _devicesController;
  Timer? _keepAliveTimer;

  Function(String)? onDataReceived;
  Function(String)? onError;
  Function(String)? onSuccess;
  Function()? onDisconnected;

  BluetoothConnection? get activeConnection => connection;
  bool get isConnected => connection?.isConnected == true;

  Future<void> initialize() async {
    try {
      for (var permission in [
        Permission.bluetooth,
        Permission.bluetoothConnect,
        Permission.bluetoothScan,
        Permission.bluetoothAdvertise,
        Permission.location,
      ]) {
        if (await permission.isDenied) {
          await permission.request();
        }
      }

      var locationServiceStatus = await Location().serviceEnabled();
      if (!locationServiceStatus) {
        if (!await Location().requestService()) {
          onError?.call('Enable Location Services');
          return;
        }
      }

      if (!(await _bluetooth.isEnabled ?? false)) {
        await _bluetooth.requestEnable();
      }
    } catch (e) {
      onError?.call('Bluetooth init failed');
    }
  }

  Stream<List<BluetoothDevice>> startScan() {
    _devicesController?.close();
    _devicesController = StreamController<List<BluetoothDevice>>();
    List<BluetoothDevice> devices = [];

    _bluetooth.startDiscovery().listen(
          (res) {
        final idx = devices.indexWhere((d) => d.address == res.device.address);
        if (idx >= 0) {
          devices[idx] = res.device;
        } else {
          devices.add(res.device);
        }
        _devicesController?.add(List.from(devices));
      },
      onDone: () {
        _devicesController?.close();
        onSuccess?.call('Scan complete');
      },
      onError: (e) {
        _devicesController?.close();
        onError?.call('Scan failed');
      },
    );

    return _devicesController!.stream;
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    try {
      connection = await BluetoothConnection.toAddress(device.address)
          .timeout(const Duration(seconds: 8));
      if (connection!.isConnected) {
        onSuccess?.call('🔗 Bluetooth Connected to ${device.name}');

        _dataSubscription?.cancel();
        _dataSubscription = connection!.input!.listen(
              (data) {
            onDataReceived?.call(utf8.decode(data));
          },
          onDone: () => _handleConnectionLoss(),
          onError: (e) => _handleConnectionLoss(),
          cancelOnError: true,
        );

        _startKeepAlive();
      }
    } catch (e) {
      onError?.call('❌ Connection failed');
      disconnect();
    }
  }

  void _startKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(Duration(seconds: 5), (timer) {
      if (isConnected) {
        sendCommand('ping');
      }
    });
  }

  Future<void> sendCommand(String command) async {
    if (!isConnected) {
      onError?.call('Not connected to any device');
      return;
    }
    try {
      final bytes = utf8.encode('$command\r\n');
      connection!.output.add(Uint8List.fromList(bytes));
      await connection!.output.allSent;
    } catch (e) {
      onError?.call('Send failed: ${e.toString()}');
    }
  }

  void _handleConnectionLoss() {
    // Do not immediately disconnect — instead notify disconnection
    if (connection != null && !connection!.isConnected) {
      _cleanupResources();
      onDisconnected?.call();
      onError?.call('❌ Bluetooth Disconnected');
    }
  }

  Future<void> disconnect() async {
    try {
      _keepAliveTimer?.cancel();
      await _dataSubscription?.cancel();
      if (connection != null && connection!.isConnected) {
        await connection!.finish();
      }
    } catch (_) {}
    finally {
      _cleanupResources();
      onDisconnected?.call();
      onSuccess?.call('🔌 Bluetooth manually disconnected');
    }
  }

  void _cleanupResources() {
    connection = null;
    _dataSubscription = null;
    _keepAliveTimer = null;
  }

  void dispose() {
    cancelScan();
    disconnect();
  }

  void cancelScan() {
    _bluetooth.cancelDiscovery();
    _devicesController?.close();
  }
}
