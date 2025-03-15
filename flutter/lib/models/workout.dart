import 'dart:convert';

class Workout {
  final int? id;
  final String name; 
  final DateTime startTime; 
  final DateTime endTime; 
  final List<Map<String, dynamic>> exercises; 
  final String durationTime;

  Workout({
    this.id,
    required this.name,
    required this.startTime,
    required this.endTime,
    required this.exercises,
    required this.durationTime
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime.toIso8601String(),
      'exercises': jsonEncode(exercises),
      'durationTime': durationTime,
    };
  }

  factory Workout.fromMap(Map<String, dynamic> map) {
    return Workout(
      id: map['id'] as int?,
      name: map['name'] as String,
      startTime: DateTime.parse(map['startTime']),
      endTime: DateTime.parse(map['endTime']),
      durationTime: map['durationTime'] as String,
      exercises: List<Map<String, dynamic>>.from(
        jsonDecode(map['exercises'] as String),
      ),
    );
  }
}
