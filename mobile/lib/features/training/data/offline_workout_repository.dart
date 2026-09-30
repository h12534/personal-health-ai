import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/local_database.dart';

final offlineWorkoutRepositoryProvider = Provider<WorkoutRepository>(
  (ref) => OfflineWorkoutRepository(ref.watch(localDatabaseProvider)),
);

abstract interface class WorkoutRepository {
  Future<LocalWorkoutRecord> start({String? trainingDayId});

  Future<LocalWorkoutSetRecord> recordSet({
    required String sessionLocalId,
    required String exerciseId,
    required int setNumber,
    required double weightKg,
    required int reps,
    required double rir,
    required int restSeconds,
    String setType = 'working',
  });

  Future<void> complete(String sessionLocalId, {double? sessionRpe});

  Future<List<LocalWorkoutSetRecord>> sets(String sessionLocalId);
}

class OfflineWorkoutRepository implements WorkoutRepository {
  OfflineWorkoutRepository(this._database);

  final LocalDatabase _database;
  final Uuid _uuid = const Uuid();

  @override
  Future<LocalWorkoutRecord> start({String? trainingDayId}) async {
    final now = DateTime.now();
    final id = _uuid.v4();
    final workout = LocalWorkoutRecord(
      localId: id,
      trainingDayId: trainingDayId,
      startedAt: now,
      status: 'in_progress',
      syncStatus: 'pending',
      updatedAt: now,
    );
    await _database.transaction(() async {
      await _database.insertWorkout(workout);
      await _database.enqueue(
        OutboxRecord(
          id: _uuid.v4(),
          aggregateType: 'workout',
          aggregateLocalId: id,
          operation: 'workout_create',
          payload: {
            'id': id,
            'training_day_id': trainingDayId,
            'started_at': now.toUtc().toIso8601String(),
          },
          idempotencyKey: 'workout-$id',
          createdAt: now,
        ),
      );
    });
    return workout;
  }

  @override
  Future<LocalWorkoutSetRecord> recordSet({
    required String sessionLocalId,
    required String exerciseId,
    required int setNumber,
    required double weightKg,
    required int reps,
    required double rir,
    required int restSeconds,
    String setType = 'working',
  }) async {
    final now = DateTime.now();
    final id = _uuid.v4();
    final workoutSet = LocalWorkoutSetRecord(
      localId: id,
      sessionLocalId: sessionLocalId,
      exerciseId: exerciseId,
      setNumber: setNumber,
      setType: setType,
      weightKg: weightKg,
      reps: reps,
      rir: rir,
      restSeconds: restSeconds,
      syncStatus: 'pending',
      updatedAt: now,
    );
    await _database.transaction(() async {
      await _database.insertWorkoutSet(workoutSet);
      await _database.enqueue(
        OutboxRecord(
          id: _uuid.v4(),
          aggregateType: 'workout_set',
          aggregateLocalId: id,
          operation: 'workout_set_create',
          payload: {
            'session_local_id': sessionLocalId,
            'id': id,
            'exercise_id': exerciseId,
            'set_number': setNumber,
            'set_type': setType,
            'weight_kg': weightKg,
            'reps': reps,
            'rir': rir,
            'rest_seconds': restSeconds,
          },
          idempotencyKey: 'workout-set-$id',
          createdAt: now,
        ),
      );
    });
    return workoutSet;
  }

  @override
  Future<void> complete(String sessionLocalId, {double? sessionRpe}) async {
    final now = DateTime.now();
    await _database.transaction(() async {
      await _database.completeLocalWorkout(
        sessionLocalId,
        now,
        sessionRpe: sessionRpe,
      );
      await _database.enqueue(
        OutboxRecord(
          id: _uuid.v4(),
          aggregateType: 'workout',
          aggregateLocalId: sessionLocalId,
          operation: 'workout_complete',
          payload: {
            'session_local_id': sessionLocalId,
            'ended_at': now.toUtc().toIso8601String(),
            'session_rpe': sessionRpe,
          },
          idempotencyKey: 'workout-complete-$sessionLocalId',
          createdAt: now,
        ),
      );
    });
  }

  @override
  Future<List<LocalWorkoutSetRecord>> sets(String sessionLocalId) =>
      _database.workoutSets(sessionLocalId);
}
