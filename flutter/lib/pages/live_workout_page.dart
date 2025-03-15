import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../db/db_helper.dart';
import '../models/workout.dart';

class LiveWorkoutPage extends StatefulWidget {
  final List<Map<String, dynamic>> selectedExercises;
  final String sessionName;

  const LiveWorkoutPage({super.key, required this.selectedExercises, required this.sessionName});

  @override
  _LiveWorkoutPageState createState() => _LiveWorkoutPageState();
}

class _LiveWorkoutPageState extends State<LiveWorkoutPage> {
  BluetoothDevice? device;
  BluetoothCharacteristic? repChar, romChar, movementChar, exerciseStateChar, classStateChar;

  List<List<List<String>>> repStatusesAll = [];
  List<List<bool>> setActiveAll = [];

  List<List<String>> repStatuses = [];
  List<bool> setActive = [];

  int currentExerciseIndex = 0;
  bool isServicesReady = false;

  DateTime? workoutStart;
  DateTime? workoutEnd;
  final AudioPlayer _audioPlayer = AudioPlayer();

  void playChime() async {
  await _audioPlayer.play(AssetSource('sounds/starting_calibration.mp3'));
  await Future.delayed(Duration(seconds: 2));
  await _audioPlayer.play(AssetSource('sounds/start_exercise.mp3'));
}

  void playStartExercise() async {
  await _audioPlayer.play(AssetSource('sounds/start_exercise.mp3'));
}

  StreamSubscription<List<int>>? romSubscription;

  double rom = 0.0;

  @override
  void initState() {
    super.initState();
    workoutStart = DateTime.now();
    buildAllRepStatuses();
    copyCurrentExerciseData();
    scanAndConnect();
  }

  void buildAllRepStatuses() {
    repStatusesAll.clear();
    setActiveAll.clear();

    for (int e = 0; e < widget.selectedExercises.length; e++) {
      final exercise = widget.selectedExercises[e];
      int sets = exercise['sets'];
      int reps = exercise['reps'];

      final repStatusesForExercise = List.generate(
        sets,
        (_) => List.generate(reps, (_) => ""),
      );
      final setActiveForExercise = List.generate(sets, (_) => false);

      repStatusesAll.add(repStatusesForExercise);
      setActiveAll.add(setActiveForExercise);
    }
  }

  void copyCurrentExerciseData() {
    repStatuses = repStatusesAll[currentExerciseIndex];
    setActive = setActiveAll[currentExerciseIndex];

    final exName = widget.selectedExercises[currentExerciseIndex]['name'];
    print("Initialized workout data for: $exName");
  }

  Future<void> scanAndConnect() async {
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
    FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult r in results) {
        if (r.advertisementData.advName == "Gym_Arduino") {
          device = r.device;
          device!.connect().then((_) async {
            discoverServices();
          });
          FlutterBluePlus.stopScan();
          break;
        }
      }
    });
  }

  Future<void> discoverServices() async {
    if (device == null) return;
    print("Discovering services...");

    final services = await device!.discoverServices();
    for (BluetoothService service in services) {
      for (BluetoothCharacteristic characteristic in service.characteristics) {
        final uuidStr = characteristic.uuid.toString().toLowerCase();
        print("Found characteristic: $uuidStr");

        if (uuidStr.contains("793d")) {
          repChar = characteristic;
          await repChar!.setNotifyValue(true);
          repChar!.lastValueStream.listen((value) {
            if (value.isNotEmpty) {
              handleRepData(value);
            }
          });
        } else if (uuidStr.contains("ff7f")) {
          romChar = characteristic;
          await romChar!.setNotifyValue(true);
          romSubscription = romChar!.lastValueStream.listen((value) {
            handleROMData(value);
          });
        } else if (uuidStr.contains("330d")) {
          movementChar = characteristic;
          print("Found Movement Type Characteristic (330d)");
        } else if (uuidStr.contains("a200")) {
          exerciseStateChar = characteristic;
          print("Found Exercise State Characteristic (a200)");
        } else if (uuidStr.contains("8a1d")) {
          exerciseStateChar = characteristic;
          print("Found Exercise State Characteristic (8a1d)");
        } else if (uuidStr.contains("00a3")) { 
          classStateChar = characteristic;
          print("Found Classification Label Characteristic (00a3)");

          await classStateChar!.setNotifyValue(true);
          classStateChar!.lastValueStream.listen((value) {
            handleClassificationData(value);
          });
        }
      }
    }
    print("Services discovered. Ready to go.");

    setState(() {
      isServicesReady = true;
    });
  }

void handleClassificationData(List<int> value) async {
  if (value.isEmpty) return;

  await Future.delayed(Duration(milliseconds: 100));
  
  String classification = utf8.decode(value).trim();
  int setIndex = setActive.indexOf(true);
  if (setIndex == -1) return;
  
  final exercise = widget.selectedExercises[currentExerciseIndex];
  int maxReps = exercise['reps'];
  
  int repIndex = repStatuses[setIndex].lastIndexWhere((rep) => rep == "Pending");

  if (repIndex == -1) {
    repIndex = repStatuses[setIndex].indexWhere((rep) => rep.isEmpty);
  }
  
  if (repIndex == -1 || repIndex >= maxReps) {
    print("No rep slot available for classification.");
    return;
  }
  
  setState(() {
    repStatuses[setIndex][repIndex] = classification;
  });
  
  print("Classification arrived: $classification => repIndex=$repIndex in set=$setIndex");
}


 void handleRepData(List<int> value) {
  if (value.isEmpty) return;

  int rawByte = value[0];
  int setIndex = setActive.indexOf(true);
  if (setIndex == -1) {
    print("Received rep data but no set active. Ignoring.");
    return;
  }

  if (rawByte == 0) {
    print("Ignoring rawByte=0 as stale");
    return;
  }

  final exercise = widget.selectedExercises[currentExerciseIndex];
  int maxReps = exercise['reps'];

  int repIndex = repStatuses[setIndex].indexWhere((rep) => rep.isEmpty);
  if (repIndex == -1 || repIndex >= maxReps) {
    print("No empty rep slot available.");
    return;
  }

  setState(() {
    repStatuses[setIndex][repIndex] = "Pending";
  });

  print("Rep detected for set=$setIndex, rep=$repIndex. Classification pending.");

  if (repIndex + 1 >= maxReps) {

    Future.delayed(Duration(seconds: 1), () {

      stopSet(setIndex);
    });
  }
}


  void handleROMData(List<int> value) {
    print("Raw ROM Data Received: $value");
    setState(() {
      rom = (value.length >= 4)
          ? byteArrayToFloat(value)
          : value[0].toDouble();
    });
    print("Converted ROM: $rom");
  }

  double byteArrayToFloat(List<int> bytes) {
    if (bytes.length < 4) return 0.0;
    final bd = ByteData.sublistView(Uint8List.fromList(bytes));
    return bd.getFloat32(0, Endian.little);
  }

  void startSet(int setIndex) {
  if (!isServicesReady) {
    print("Services not ready yet!");
    return;
  }

  int movementType = getMovementType(widget.selectedExercises[currentExerciseIndex]);

  if (movementType == 2 || movementType == 3) { 
    print("Playing chime for push or row exercise. Calibrate now!");
    playChime();
    _beginSet(setIndex, movementType);
  } else {

    _beginSet(setIndex, movementType);
  }
}


void _beginSet(int setIndex, int movementType) {
  sendMovementType(movementType);

  setState(() {
    setActive[setIndex] = true;
    final exercise = widget.selectedExercises[currentExerciseIndex];
    int reps = exercise['reps'];
    repStatuses[setIndex] = List.generate(reps, (_) => "");
  });

  sendExerciseState(1);
  print("Start Set ${setIndex + 1} for exerciseIndex=$currentExerciseIndex");
}


  void stopSet(int setIndex) {
    sendExerciseState(0);
    setState(() {
      setActive[setIndex] = false;
    });
    print("Stop Set ${setIndex + 1} for exerciseIndex=$currentExerciseIndex");
  }

  void nextExercise() {
    repStatusesAll[currentExerciseIndex] = repStatuses;
    setActiveAll[currentExerciseIndex] = setActive;

    if (currentExerciseIndex < widget.selectedExercises.length - 1) {
      setState(() {
        currentExerciseIndex++;
      });
      print("Now on exercise: ${widget.selectedExercises[currentExerciseIndex]['name']}");

      repStatuses = repStatusesAll[currentExerciseIndex];
      setActive = setActiveAll[currentExerciseIndex];

      sendMovementType(getMovementType(widget.selectedExercises[currentExerciseIndex]));
      sendExerciseState(0);

    } else {
      print("All exercises complete!");
      endWorkout();
    }
  }

  void endWorkout() async {
    print("Ending workout => set movementType=0, exerciseState=0");

    repStatusesAll[currentExerciseIndex] = repStatuses;
    setActiveAll[currentExerciseIndex] = setActive;

    final String workoutName = widget.sessionName;
    workoutEnd = DateTime.now();

    final duration = workoutEnd!.difference(workoutStart!);

    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;

    final workoutDuration = "${hours}h ${minutes}m";
    print("Workout Duration: $workoutDuration");

    String formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h == 0) {
      return "${m}m";
    } else {
      return "${h}h ${m.toString().padLeft(2, '0')}m";
    }
  }

  final durationString = formatDuration(workoutEnd!.difference(workoutStart!));
  print(durationString);


    
    final List<Map<String, dynamic>> exercisesData = [];

    for (int e = 0; e < widget.selectedExercises.length; e++) {
      final exObj = widget.selectedExercises[e];
      final exName = exObj['name'];
      int sets = exObj['sets'];
      
      final repStatuses2D = repStatusesAll[e];

      
      final setsList = <Map<String, dynamic>>[];
      for (int s = 0; s < sets; s++) {
        setsList.add({
          "repStatuses": repStatuses2D[s]
        });
      }

      exercisesData.add({
        "name": exName,
        "sets": setsList
      });
    }

    final workoutData = {
      "workoutName": workoutName,
      "exercises": exercisesData
    };

    final newWorkout = Workout(
      name: widget.sessionName,         
      startTime: workoutStart!,        
      endTime: workoutEnd!,             
      exercises: exercisesData,         
      durationTime: durationString,     
    );


    try {
      final db = await DBHelper.instance.database;
      final id = await db.insert(
        'workouts',
        newWorkout.toMap(), 
      );
      print("Saved workout with id=$id");
    } catch (e) {
      print("Error inserting workout to DB: $e");
    }

    sendMovementType(0); 
    sendExerciseState(0);
    device?.disconnect();
    print("Bluetooth Device Disconnected.");

    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  int getMovementType(Map<String, dynamic> exerciseMap) {
    final exName = exerciseMap['name'] as String;
    List<String> pushPull = ["Bench Press", "Shoulder Press", "Deadlift", "Pull-Ups"];
    List<String> curls = ["Bicep Curls", "Dumbbell Curl"];
    List<String> rows = ["Seated Rows"];
    List<String> steps = ["Step Count"];

    if(steps.contains(exName))  return 4;
    if(rows.contains(exName))  return 3;
    if (pushPull.contains(exName)) return 2;
    if (curls.contains(exName)) return 1;
    return 0;
  }

  void sendMovementType(int movementType) {
    print("sendMovementType($movementType) called");
    if (device == null || movementChar == null) {
      print("movementChar is null => cannot send movement type");
      return;
    }
    movementChar!.write([movementType], withoutResponse: false).then((_) {
      print("Sent Movement Type: $movementType");
    }).catchError((err) {
      print("Error sending movement type: $err");
    });
  }

  void sendExerciseState(int state) {
    print("sendExerciseState($state) called");
    if (device == null || exerciseStateChar == null) {
      print("exerciseStateChar is null => cannot send exercise state");
      return;
    }
    exerciseStateChar!.write([state], withoutResponse: false).then((_) {
      print("Sent Exercise State: $state");
    }).catchError((err) {
      print("Error sending exercise state: $err");
    });
  }

  @override
  void dispose() {
    sendMovementType(0);
    romSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final exObj = widget.selectedExercises[currentExerciseIndex];
    final exName = exObj['name'];
    final sets = exObj['sets'];
    final reps = exObj['reps'];

    return Scaffold(
      appBar: AppBar(title: Text("Live Workout: $exName")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Exercise: $exName", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            
            Expanded(
              child: ListView.builder(
                itemCount: sets,
                itemBuilder: (context, setIndex) {
                  int completedReps = repStatuses[setIndex].where((r) => r.isNotEmpty).length;
                  return ExpansionTile(
                    title: Text("Set ${setIndex + 1} - Reps: $completedReps/$reps"),
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton(
                            onPressed: (!isServicesReady || setActive[setIndex])
                                ? null
                                : () => startSet(setIndex),
                            child: const Text("Start Set"),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton(
                            onPressed: !setActive[setIndex] 
                                ? null 
                                : () => stopSet(setIndex),
                            child: const Text("Stop Set"),
                          ),
                        ],
                      ),
                      Column(
                        children: repStatuses[setIndex].asMap().entries.map((entry) {
                          final repNo = entry.key + 1;
                          final repVal = entry.value.isNotEmpty ? entry.value : "Pending";
                          return ListTile(
                            title: Text("Rep $repNo: $repVal"),
                          );
                        }).toList(),
                      ),
                    ],
                  );
                },
              ),
            ),

            Center(
              child: ElevatedButton(
                onPressed: (currentExerciseIndex < widget.selectedExercises.length - 1)
                    ? nextExercise
                    : endWorkout,
                child: Text((currentExerciseIndex < widget.selectedExercises.length - 1)
                    ? "Next Exercise"
                    : "End Workout"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
