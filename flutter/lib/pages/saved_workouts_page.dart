import 'package:flutter/material.dart';
import '../db/db_helper.dart';
import '../models/saved_workout.dart';
import 'create_saved_workout_page.dart';
import 'live_workout_page.dart';

class SavedWorkoutsPage extends StatefulWidget {
  @override
  _SavedWorkoutsPageState createState() => _SavedWorkoutsPageState();
}

class _SavedWorkoutsPageState extends State<SavedWorkoutsPage> {
  List<SavedWorkout> savedWorkouts = [];

  @override
  void initState() {
    super.initState();
    _loadSavedWorkouts();
  }

  Future<void> _loadSavedWorkouts() async {
    final workouts = await DBHelper.instance.readAllSavedWorkouts();
    setState(() {
      savedWorkouts = workouts;
    });
  }

  Future<void> _deleteSavedWorkout(int id) async {
    await DBHelper.instance.deleteSavedWorkout(id);
    _loadSavedWorkouts(); 
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Saved Workouts"),
        actions: [
          IconButton(
            icon: Icon(Icons.add, color: Colors.amber),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => CreateSavedWorkoutPage()),
              ).then((_) {
                _loadSavedWorkouts();
              });
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                itemCount: savedWorkouts.length,
                itemBuilder: (context, index) {
                  final workout = savedWorkouts[index];
                  return Card(
                    child: ListTile(
                      title: Text(workout.name),
                      subtitle: Text("${workout.exercises.length} exercises"),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(Icons.delete_outline_outlined, color: Colors.amber),
                            onPressed: () => _deleteSavedWorkout(workout.id!),
                          ),
                          IconButton(
                            icon: Icon(Icons.play_arrow, color: Colors.amber),
                            onPressed: () {
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
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
