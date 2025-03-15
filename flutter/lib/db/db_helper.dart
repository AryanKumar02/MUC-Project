import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/saved_workout.dart';
import '../models/workout.dart';

class DBHelper {
  static final DBHelper instance = DBHelper._init();
  static Database? _database;

  DBHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('workout.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future _createDB(Database db, int version) async {

    await db.execute('''
    CREATE TABLE workouts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT,
      startTime TEXT,
      endTime TEXT,
      exercises TEXT,
      durationTime TEXT
    )
    ''');

    await db.execute('''
    CREATE TABLE saved_workouts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT,
      exercises TEXT
    )
  ''');
  }

  Future close() async {
    final db = await instance.database;
    db.close();
  }

Future<int> createWorkout(Workout workout) async {
  final db = await instance.database;
  return db.insert('workouts', workout.toMap());
}

Future<Workout?> readWorkout(int id) async {
  final db = await instance.database;

  final maps = await db.query(
    'workouts',
    columns: ['id', 'name', 'startTime', 'endTime', 'exercises', 'durationTime'],
    where: 'id = ?',
    whereArgs: [id],
  );

  if (maps.isNotEmpty) {
    return Workout.fromMap(maps.first);
  } else {
    return null;
  }
}

Future<List<Workout>> readAllWorkouts() async {
  final db = await instance.database;
  final result = await db.query('workouts');

  return result.map((row) => Workout.fromMap(row)).toList();
}

Future<int> updateWorkout(Workout workout) async {
  final db = await instance.database;
  return db.update(
    'workouts',
    workout.toMap(),
    where: 'id = ?',
    whereArgs: [workout.id],
  );
}

Future<int> deleteWorkout(int id) async {
  final db = await instance.database;
  return await db.delete(
    'workouts',
    where: 'id = ?',
    whereArgs: [id],
  );
}

Future<int> createSavedWorkout(SavedWorkout workout) async {
  final db = await instance.database;
  return db.insert('saved_workouts', workout.toMap());
}

Future<List<SavedWorkout>> readAllSavedWorkouts() async {
  final db = await instance.database;
  final result = await db.query('saved_workouts');
  return result.map((row) => SavedWorkout.fromMap(row)).toList();
}

Future<int> deleteSavedWorkout(int id) async {
  final db = await instance.database;
  return db.delete(
    'saved_workouts',
    where: 'id = ?',
    whereArgs: [id],
  );
}

}


