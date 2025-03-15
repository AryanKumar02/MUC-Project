import 'package:flutter/material.dart';

class WorkoutSummaryPage extends StatelessWidget {
  final String workoutName;
  final List<List<Map<String, dynamic>>> workoutData;
  final List<String> exercises;

  const WorkoutSummaryPage({super.key, required this.workoutName, required this.workoutData, required this.exercises});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Summary: $workoutName")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Workout Summary", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                itemCount: exercises.length,
                itemBuilder: (context, exerciseIndex) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(exercises[exerciseIndex], style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ...workoutData[exerciseIndex].map((setData) {
                        return Padding(
                          padding: const EdgeInsets.only(left: 16.0, top: 5),
                          child: Text(
                            "Set ${setData['set']}: ${setData['reps']} reps, ROM: ${setData['rom']}%",
                            style: TextStyle(fontSize: 16),
                          ),
                        );
                      }),
                      SizedBox(height: 10),
                    ],
                  );
                },
              ),
            ),
            Center(
              child: ElevatedButton(
                onPressed: () => Navigator.popUntil(context, (route) => route.isFirst),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                ),
                child: Text("Finish"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
