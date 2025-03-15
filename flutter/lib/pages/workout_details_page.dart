import 'package:flutter/material.dart';
import '../models/workout.dart';

class WorkoutDetailsPage extends StatelessWidget {
  final Workout workout;

  const WorkoutDetailsPage({super.key, required this.workout});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(workout.name)),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Duration: ${workout.durationTime}",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            SizedBox(height: 8),
            Text("Exercises:", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),

            Expanded(
              child: ListView.builder(
                itemCount: workout.exercises.length,
                itemBuilder: (context, exIndex) {
                  final exercise = workout.exercises[exIndex];
                  final exName = exercise["name"] as String;
                  final setsList = exercise["sets"] as List<dynamic>;

                  return _ExerciseTile(exerciseName: exName, setsList: setsList);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExerciseTile extends StatelessWidget {
  final String exerciseName;
  final List<dynamic> setsList;

  const _ExerciseTile({
    required this.exerciseName,
    required this.setsList,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ExpansionTile(
        title: Text(exerciseName, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        children: [
          ...setsList.asMap().entries.map((entry) {
            final setIndex = entry.key;
            final setData = entry.value; 
            final repStatuses = setData["repStatuses"] as List<dynamic>;

            return _SetTile(setIndex: setIndex + 1, repStatuses: repStatuses);
          }).toList(),
        ],
      ),
    );
  }
}

class _SetTile extends StatelessWidget {
  final int setIndex;
  final List<dynamic> repStatuses;

  const _SetTile({
    required this.setIndex,
    required this.repStatuses,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: ExpansionTile(
        title: Text("Set $setIndex", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: repStatuses.asMap().entries.map((repEntry) {
                final repNo = repEntry.key + 1;
                final status = repEntry.value as String;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text("Rep $repNo: $status", style: TextStyle(fontSize: 14)),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
