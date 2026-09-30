import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/local_database.dart';
import '../../../core/network/api_client.dart';

final syncServiceProvider = Provider<SyncService>((ref) {
  return SyncService(
    ref.watch(localDatabaseProvider),
    ref.watch(apiClientProvider),
  );
});

final connectivitySyncProvider = Provider<void>((ref) {
  final sync = ref.watch(syncServiceProvider);
  unawaited(sync.syncPending());
  final subscription = Connectivity().onConnectivityChanged.listen((results) {
    if (!results.contains(ConnectivityResult.none)) {
      unawaited(sync.syncPending());
    }
  });
  ref.onDispose(subscription.cancel);
});

class SyncService {
  SyncService(this._database, this._api);

  final LocalDatabase _database;
  final ApiClient _api;
  bool _running = false;

  Future<void> syncPending() async {
    if (_running) return;
    _running = true;
    try {
      final records = await _database.pendingOutbox();
      for (final record in records) {
        try {
          final completed = await _sync(record);
          if (!completed) break;
          await _database.markOutboxSynced(record.id);
        } on Object catch (error) {
          await _database.markOutboxFailed(record.id, error.toString());
          debugPrint(
            'outbox_sync_failed id=${record.id} operation=${record.operation}',
          );
          break;
        }
      }
    } finally {
      _running = false;
    }
  }

  Future<bool> _sync(OutboxRecord record) async {
    if (record.operation == 'meal_create') {
      final meal = await _api.createMeal(
        mealType: record.payload['meal_type'] as String,
        eatenAt: DateTime.parse(record.payload['eaten_at'] as String),
        idempotencyKey: record.idempotencyKey,
      );
      await _database.markMealSynced(record.aggregateLocalId, meal.id);
      return true;
    }
    if (record.operation == 'meal_item_create') {
      final localMealId = record.payload['meal_local_id'] as String;
      final localMeal = await _database.mealByLocalId(localMealId);
      if (localMeal?.serverId == null) return false;
      final meal = await _api.addMealItem(
        mealId: localMeal!.serverId!,
        foodId: record.payload['food_id'] as String,
        amount: (record.payload['amount'] as num).toDouble(),
        unit: record.payload['amount_unit'] as String,
        idempotencyKey: record.idempotencyKey,
      );
      final foodId = record.payload['food_id'] as String;
      final serverItem = meal.items.reversed.firstWhere(
        (item) => item.foodId == foodId,
      );
      await _database.markItemSynced(record.aggregateLocalId, serverItem.id);
      return true;
    }
    if (record.operation == 'workout_create') {
      final workout = await _api.createWorkout(
        id: record.payload['id'] as String,
        trainingDayId: record.payload['training_day_id'] as String?,
        startedAt: DateTime.parse(record.payload['started_at'] as String),
        idempotencyKey: record.idempotencyKey,
      );
      await _database.markWorkoutSynced(
        record.aggregateLocalId,
        workout.id,
      );
      return true;
    }
    if (record.operation == 'workout_set_create') {
      final sessionLocalId = record.payload['session_local_id'] as String;
      final localWorkout = await _database.workoutByLocalId(sessionLocalId);
      if (localWorkout?.serverId == null) return false;
      final workoutSet = await _api.createWorkoutSet(
        workoutId: localWorkout!.serverId!,
        id: record.payload['id'] as String,
        exerciseId: record.payload['exercise_id'] as String,
        setNumber: record.payload['set_number'] as int,
        setType: record.payload['set_type'] as String,
        weightKg: (record.payload['weight_kg'] as num).toDouble(),
        reps: record.payload['reps'] as int,
        rir: (record.payload['rir'] as num).toDouble(),
        restSeconds: record.payload['rest_seconds'] as int,
        idempotencyKey: record.idempotencyKey,
      );
      await _database.markWorkoutSetSynced(
        record.aggregateLocalId,
        workoutSet.id,
      );
      return true;
    }
    if (record.operation == 'workout_complete') {
      final sessionLocalId = record.payload['session_local_id'] as String;
      final localWorkout = await _database.workoutByLocalId(sessionLocalId);
      if (localWorkout?.serverId == null) return false;
      await _api.completeWorkout(
        workoutId: localWorkout!.serverId!,
        endedAt: DateTime.parse(record.payload['ended_at'] as String),
        sessionRpe: (record.payload['session_rpe'] as num?)?.toDouble(),
      );
      return true;
    }
    throw StateError('Unsupported outbox operation: ${record.operation}');
  }
}
