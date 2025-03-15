import 'dart:convert';

class SavedWorkout {
  final int? id;
  final String name;
  final List<Map<String, dynamic>> exercises;

  SavedWorkout({
    this.id,
    required this.name,
    required this.exercises,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'exercises': jsonEncode(exercises),
    };
  }

  factory SavedWorkout.fromMap(Map<String, dynamic> map) {
    return SavedWorkout(
      id: map['id'] as int?,
      name: map['name'] as String,
      exercises: List<Map<String, dynamic>>.from(
        jsonDecode(map['exercises'] as String),
      ),
    );
  }
}
