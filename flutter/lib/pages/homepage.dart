import 'dart:async';

import 'package:flutter/material.dart';
import '../db/db_helper.dart';
import '../models/saved_workout.dart';
import 'connection_page.dart';
import 'create_workout_page.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'live_workout_page.dart';
import 'saved_workouts_page.dart';
import 'workout_details_page.dart';
import '../models/workout.dart';

class HomePage extends StatefulWidget {
  final BluetoothDevice? device;
  
  const HomePage({super.key, required this.device});
  
  @override
  State createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
   List<Workout> previousWorkouts = [];
   List<SavedWorkout> savedWorkouts = [];
   StreamSubscription<BluetoothConnectionState>? _connectionSubscription;

  @override
  void initState() {
    super.initState();
    _loadWorkoutsFromDB();
    _loadSavedWorkouts();
    
  if (widget.device != null) {
    _connectionSubscription = widget.device!.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        _navigateToConnectionPage();
      }
    });
  } else {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _navigateToConnectionPage();
    });
  }
}

void _navigateToConnectionPage() {
  if (mounted) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => ConnectionPage()), 
      (route) => false,
    );
  }
}


  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadWorkoutsFromDB();
  }

    @override
  void dispose() {
    _connectionSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadWorkoutsFromDB() async {
    final dbWorkouts = await DBHelper.instance.readAllWorkouts();
    final uiWorkouts = <Workout>[];

    for (var dbw in dbWorkouts) {

      final List<String> exerciseNames = dbw.exercises.map((ex) {
        return ex["name"] as String;
      }).toList();

      uiWorkouts.add(Workout(
        name: dbw.name,
        exercises: dbw.exercises,
        durationTime: dbw.durationTime,
        startTime: dbw.startTime,
        endTime: dbw.endTime
      ));
    }

    setState(() {
      previousWorkouts = uiWorkouts;
    });
  }

    Future<void> _loadSavedWorkouts() async {
    final dbSavedWorkouts = await DBHelper.instance.readAllSavedWorkouts();
    setState(() {
      savedWorkouts = dbSavedWorkouts;
    });
  }

  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.device == null
      ? 'GymDjuino - Not Connected'
      : 'GymDjuino - Connected: ${widget.device!.platformName}',
      ),
      ),
      body: RefreshIndicator(
        onRefresh:() async { await _loadWorkoutsFromDB(); await _loadSavedWorkouts();},
       child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: <Widget>[
            Text(
              'Saved Workouts:',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            SizedBox(
              height: 120,
              child: ListView.builder(
                scrollDirection: Axis.horizontal, 
                itemCount: savedWorkouts.length,
                itemBuilder: (context, index) {
                  final workout = savedWorkouts[index];
                  return Padding(
                    padding: const EdgeInsets.only(right: 12.0),
                    child: _SavedWorkoutCard(
                      workoutName: workout.name,
                      workoutExercises: workout.exercises,
                      exercisesCount: workout.exercises.length,
                      onStartWorkout: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => LiveWorkoutPage(
                              selectedExercises: workout.exercises, 
                              sessionName: workout.name,
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),

            SizedBox(height: 16),
            Text(
              'Previous Workouts:',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Column(
              children: previousWorkouts.map((dbw) {
               
                final exercisesCount = dbw.exercises.length; 
               
                return _PrevWorkoutCard(
                  workoutName: dbw.name,
                  exercises: exercisesCount,
                  totalTime: dbw.durationTime, 
                  avgROM: 0,
                  onSeeMore: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => WorkoutDetailsPage(
                          workout: dbw,
                        ),
                      ),
                    );
                  }
                );
              }).toList(),
            ),
          ],
        ),
      )
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CreateWorkoutPage(),
            ),
          ).then((_) {
            _loadWorkoutsFromDB(); 
          });
        },
        tooltip: 'Create',
        backgroundColor: const Color.fromARGB(255, 219, 164, 0),
        foregroundColor: Colors.white,
        shape: CircleBorder(),
        mini: true,
        elevation: 0,
        child: const Icon(Icons.add),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: _BottomAppBar(
        onRefreshSavedWorkouts: _loadSavedWorkouts,
      ),

    );
  }
}

class _BottomAppBar extends StatelessWidget {
   final VoidCallback onRefreshSavedWorkouts;

  const _BottomAppBar({required this.onRefreshSavedWorkouts});
  @override
  Widget build(BuildContext context) {
    return BottomAppBar(
      shape: CircularNotchedRectangle(),
      child: IconTheme(
        data: IconThemeData(color: Theme.of(context).colorScheme.onPrimary),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(padding: EdgeInsets.all(8.0)),
            IconButton(
              tooltip: 'Search',
              icon: const Icon(Icons.search),
              onPressed: () {},
              color: Colors.white,
            ),
            Padding(padding: EdgeInsets.all(8.0)),
            IconButton(
              tooltip: 'Favorite',
              icon: const Icon(Icons.favorite),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => SavedWorkoutsPage()),
                ).then((_) {
                  onRefreshSavedWorkouts();
                });
              },
              color: Colors.white,
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Workouts',
              icon: const Icon(Icons.fitness_center),
              onPressed: () {},
              color: Colors.white,
            ),
            Padding(padding: EdgeInsets.all(8.0)),
            IconButton(
              tooltip: 'Profile',
              icon: const Icon(Icons.person),
              onPressed: () {},
              color: Colors.white,
            ),
            Padding(padding: EdgeInsets.all(4.0)),
          ],
        ),
      ),
    );
  }
}

class _PrevWorkoutCard extends StatelessWidget {
  const _PrevWorkoutCard({
    required this.workoutName,
    required this.exercises,
    required this.totalTime,
    required this.avgROM,
    this.onSeeMore, 
  });

  final String workoutName;
  final int exercises;
  final String totalTime;
  final double avgROM;

  final VoidCallback? onSeeMore;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              workoutName,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildStat(Icons.fitness_center, "$exercises Exercises"),
                _buildStat(Icons.timer, totalTime),
              ],
            ),
            SizedBox(height: 8),

            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: onSeeMore,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.amber, width: 3),
                    foregroundColor: Colors.amber,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  child: Text("More Details"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStat(IconData icon, String value) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.amber),
        SizedBox(width: 6),
        Text(
          value,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}


class _SavedWorkoutCard extends StatelessWidget {
  const _SavedWorkoutCard({
    required this.workoutName,
    required this.exercisesCount,
    required this.onStartWorkout,
    required this.workoutExercises,
  });

  final String workoutName;
  final int exercisesCount;
  final VoidCallback onStartWorkout;
  final List<Map<String, dynamic>> workoutExercises;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      elevation: 4,
      child: Container(
        width: 220,
        padding: const EdgeInsets.all(12.0),
        child: Stack(
          children: [

            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  workoutName,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),

                ...workoutExercises.take(2).map((exercise) => Text(
                      "• ${exercise['name']}",
                      style: TextStyle(fontSize: 12),
                    )),

                if (workoutExercises.length > 2)
                  Text(
                    "• +${workoutExercises.length - 2} more",
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
              ],
            ),

            Positioned(
              top: 0,
              right: 0,
              child: IconButton(
                onPressed: onStartWorkout,
                icon: Icon(Icons.arrow_circle_right_outlined, color: Colors.amber, size: 38),
                tooltip: "Start Workout",
              ),
            ),
          ],
        ),
      ),
    );
  }
}
