import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'homepage.dart';
import 'package:device_info_plus/device_info_plus.dart';

class ConnectionPage extends StatefulWidget {
  const ConnectionPage({super.key});

  @override
  _ConnectionPageState createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<ConnectionPage> {
  String statusMessage = "Scanning for BLE devices...";
  bool isSimulator = false;
  bool isConnecting = false;

  @override
  void initState() {
    super.initState();
    checkSimulatorAndConnect();
  }

  Future<bool> checkIfSimulator() async {
    if (Platform.isIOS) {
      var iosInfo = await DeviceInfoPlugin().iosInfo;
      return !iosInfo.isPhysicalDevice;
    }
    return false;
  }

  Future<void> checkSimulatorAndConnect() async {
    isSimulator = await checkIfSimulator();
    if (Platform.isIOS && isSimulator) {
      setState(() {
        statusMessage = "BLE is not supported on the iOS Simulator.\nPlease use a physical device.";
      });
    } else {
      connectBLE();
    }
  }

  Future<void> connectBLE() async {
    setState(() {
      isConnecting = true;
      statusMessage = "Scanning for BLE devices...";
    });

    FlutterBluePlus.startScan(timeout: Duration(seconds: 5));

    FlutterBluePlus.scanResults.listen((results) async {
      for (ScanResult result in results) {
        print("Found Device: ${result.device.advName} - ID: ${result.device.remoteId}");

        if (result.device.advName == "Gym_Arduino") {
          setState(() {
            statusMessage = "Device found. Connecting to ${result.device.advName}...";
          });
          try {
            await result.device.connect();
            await FlutterBluePlus.stopScan();
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => HomePage(device: result.device),
              ),
            );
          } catch (error) {
            setState(() {
              statusMessage = "Connection failed: $error\nPlease try again.";
              isConnecting = false;
            });
          }
          return;
        }
      }

      if (isConnecting) {
        setState(() {
          statusMessage = "No BLE device found. Ensure Gym_Arduino is on and in range.";
          isConnecting = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(
                statusMessage,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
              SizedBox(height: 24),
              if (!isConnecting && !(Platform.isIOS && isSimulator))
                ElevatedButton(
                  onPressed: () {
                    connectBLE();
                  },
                  child: Text("Retry Connection"),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
