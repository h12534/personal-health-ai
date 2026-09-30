import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../features/nutrition/data/nutrition_models.dart';

final localDatabaseProvider = Provider<LocalDatabase>((ref) {
  final database = LocalDatabase();
  ref.onDispose(database.close);
  return database;
});

class LocalDatabase extends GeneratedDatabase {
  LocalDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 3;

  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];

  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (migrator) async {
          await customStatement('''
            CREATE TABLE local_meals (
              local_id TEXT PRIMARY KEY,
              server_id TEXT,
              meal_type TEXT NOT NULL,
              eaten_at TEXT NOT NULL,
              local_date TEXT NOT NULL,
              sync_status TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              deleted_at TEXT
            )
          ''');
          await customStatement('''
            CREATE TABLE local_meal_items (
              local_id TEXT PRIMARY KEY,
              meal_local_id TEXT NOT NULL,
              server_id TEXT,
              food_id TEXT NOT NULL,
              food_name_snapshot TEXT NOT NULL,
              amount REAL NOT NULL,
              amount_unit TEXT NOT NULL,
              calories REAL NOT NULL,
              protein REAL NOT NULL,
              carbs REAL NOT NULL,
              fat REAL NOT NULL,
              fiber REAL NOT NULL,
              sync_status TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              deleted_at TEXT,
              FOREIGN KEY(meal_local_id) REFERENCES local_meals(local_id)
            )
          ''');
          await customStatement('''
            CREATE TABLE sync_outbox (
              id TEXT PRIMARY KEY,
              aggregate_type TEXT NOT NULL,
              aggregate_local_id TEXT NOT NULL,
              operation TEXT NOT NULL,
              payload_json TEXT NOT NULL,
              idempotency_key TEXT NOT NULL UNIQUE,
              status TEXT NOT NULL,
              attempts INTEGER NOT NULL DEFAULT 0,
              last_error TEXT,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
          ''');
          await customStatement('''
            CREATE TABLE food_cache (
              id TEXT PRIMARY KEY,
              name_normalized TEXT NOT NULL,
              payload_json TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
          ''');
          await customStatement(
            'CREATE INDEX ix_outbox_pending ON sync_outbox(status, created_at)',
          );
          await customStatement(
            'CREATE INDEX ix_local_meal_day ON local_meals(local_date, meal_type)',
          );
          await _createVisionTaskTable();
          await _createWorkoutTables();
        },
        onUpgrade: (migrator, from, to) async {
          if (from < 2) await _createVisionTaskTable();
          if (from < 3) await _createWorkoutTables();
        },
      );

  Future<void> _createVisionTaskTable() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS local_vision_tasks (
        local_id TEXT PRIMARY KEY,
        image_path TEXT NOT NULL,
        meal_type TEXT NOT NULL,
        location_context TEXT NOT NULL,
        analysis_id TEXT,
        status TEXT NOT NULL,
        upload_progress REAL NOT NULL DEFAULT 0,
        last_error TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS ix_vision_task_status
      ON local_vision_tasks(status, created_at)
    ''');
  }

  Future<void> _createWorkoutTables() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS local_workout_sessions (
        local_id TEXT PRIMARY KEY,
        server_id TEXT,
        training_day_id TEXT,
        started_at TEXT NOT NULL,
        ended_at TEXT,
        status TEXT NOT NULL,
        session_rpe REAL,
        sync_status TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS local_workout_sets (
        local_id TEXT PRIMARY KEY,
        server_id TEXT,
        session_local_id TEXT NOT NULL,
        exercise_id TEXT NOT NULL,
        set_number INTEGER NOT NULL,
        set_type TEXT NOT NULL,
        weight_kg REAL NOT NULL,
        reps INTEGER NOT NULL,
        rir REAL,
        rest_seconds INTEGER NOT NULL,
        sync_status TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY(session_local_id) REFERENCES local_workout_sessions(local_id)
      )
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS ix_local_workout_status
      ON local_workout_sessions(status, started_at)
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS ix_local_workout_set_session
      ON local_workout_sets(session_local_id, set_number)
    ''');
  }

  Future<void> insertWorkout(LocalWorkoutRecord workout) async {
    await customInsert(
      '''
        INSERT OR IGNORE INTO local_workout_sessions
          (local_id, server_id, training_day_id, started_at, ended_at, status,
           session_rpe, sync_status, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      variables: [
        Variable<String>(workout.localId),
        Variable<String>(workout.serverId),
        Variable<String>(workout.trainingDayId),
        Variable<String>(workout.startedAt.toUtc().toIso8601String()),
        Variable<String>(workout.endedAt?.toUtc().toIso8601String()),
        Variable<String>(workout.status),
        Variable<double>(workout.sessionRpe),
        Variable<String>(workout.syncStatus),
        Variable<String>(workout.updatedAt.toUtc().toIso8601String()),
      ],
    );
  }

  Future<void> insertWorkoutSet(LocalWorkoutSetRecord workoutSet) async {
    await customInsert(
      '''
        INSERT OR IGNORE INTO local_workout_sets
          (local_id, server_id, session_local_id, exercise_id, set_number,
           set_type, weight_kg, reps, rir, rest_seconds, sync_status, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      variables: [
        Variable<String>(workoutSet.localId),
        Variable<String>(workoutSet.serverId),
        Variable<String>(workoutSet.sessionLocalId),
        Variable<String>(workoutSet.exerciseId),
        Variable<int>(workoutSet.setNumber),
        Variable<String>(workoutSet.setType),
        Variable<double>(workoutSet.weightKg),
        Variable<int>(workoutSet.reps),
        Variable<double>(workoutSet.rir),
        Variable<int>(workoutSet.restSeconds),
        Variable<String>(workoutSet.syncStatus),
        Variable<String>(workoutSet.updatedAt.toUtc().toIso8601String()),
      ],
    );
  }

  Future<LocalWorkoutRecord?> workoutByLocalId(String localId) async {
    final row = await customSelect(
      'SELECT * FROM local_workout_sessions WHERE local_id = ?',
      variables: [Variable<String>(localId)],
    ).getSingleOrNull();
    return row == null ? null : LocalWorkoutRecord.fromRow(row);
  }

  Future<void> markWorkoutSynced(String localId, String serverId) async {
    await customUpdate(
      '''
        UPDATE local_workout_sessions
        SET server_id = ?, sync_status = 'synced', updated_at = ?
        WHERE local_id = ?
      ''',
      variables: [
        Variable<String>(serverId),
        Variable<String>(DateTime.now().toUtc().toIso8601String()),
        Variable<String>(localId),
      ],
    );
  }

  Future<void> markWorkoutSetSynced(String localId, String serverId) async {
    await customUpdate(
      '''
        UPDATE local_workout_sets
        SET server_id = ?, sync_status = 'synced', updated_at = ?
        WHERE local_id = ?
      ''',
      variables: [
        Variable<String>(serverId),
        Variable<String>(DateTime.now().toUtc().toIso8601String()),
        Variable<String>(localId),
      ],
    );
  }

  Future<void> completeLocalWorkout(
    String localId,
    DateTime endedAt, {
    double? sessionRpe,
  }) async {
    await customUpdate(
      '''
        UPDATE local_workout_sessions
        SET ended_at = ?, status = 'completed', session_rpe = ?,
            sync_status = 'pending', updated_at = ?
        WHERE local_id = ?
      ''',
      variables: [
        Variable<String>(endedAt.toUtc().toIso8601String()),
        Variable<double>(sessionRpe),
        Variable<String>(DateTime.now().toUtc().toIso8601String()),
        Variable<String>(localId),
      ],
    );
  }

  Future<List<LocalWorkoutSetRecord>> workoutSets(String sessionLocalId) async {
    final rows = await customSelect(
      '''
        SELECT * FROM local_workout_sets
        WHERE session_local_id = ?
        ORDER BY set_number, updated_at
      ''',
      variables: [Variable<String>(sessionLocalId)],
    ).get();
    return rows.map(LocalWorkoutSetRecord.fromRow).toList();
  }

  Future<void> saveVisionTask(VisionTaskRecord task) async {
    await customInsert(
      '''
        INSERT OR REPLACE INTO local_vision_tasks
          (local_id, image_path, meal_type, location_context, analysis_id,
           status, upload_progress, last_error, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      variables: [
        Variable<String>(task.localId),
        Variable<String>(task.imagePath),
        Variable<String>(task.mealType),
        Variable<String>(task.locationContext),
        Variable<String>(task.analysisId),
        Variable<String>(task.status),
        Variable<double>(task.uploadProgress),
        Variable<String>(task.lastError),
        Variable<String>(task.createdAt.toUtc().toIso8601String()),
        Variable<String>(task.updatedAt.toUtc().toIso8601String()),
      ],
    );
  }

  Future<void> updateVisionTask(
    String localId, {
    String? analysisId,
    String? status,
    double? uploadProgress,
    String? lastError,
  }) async {
    final current = await visionTask(localId);
    if (current == null) return;
    await saveVisionTask(
      current.copyWith(
        analysisId: analysisId,
        status: status,
        uploadProgress: uploadProgress,
        lastError: lastError,
        clearError: lastError == null && status != null,
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<VisionTaskRecord?> visionTask(String localId) async {
    final row = await customSelect(
      'SELECT * FROM local_vision_tasks WHERE local_id = ?',
      variables: [Variable<String>(localId)],
    ).getSingleOrNull();
    return row == null ? null : VisionTaskRecord.fromRow(row);
  }

  Future<List<VisionTaskRecord>> pendingVisionTasks() async {
    final rows = await customSelect('''
      SELECT * FROM local_vision_tasks
      WHERE status NOT IN ('confirmed', 'cancelled')
      ORDER BY created_at DESC
    ''').get();
    return rows.map(VisionTaskRecord.fromRow).toList();
  }

  Future<void> deleteVisionTask(
    String localId, {
    bool deleteImage = true,
  }) async {
    final task = await visionTask(localId);
    await customUpdate(
      'DELETE FROM local_vision_tasks WHERE local_id = ?',
      variables: [Variable<String>(localId)],
    );
    if (deleteImage && task != null) {
      try {
        await File(task.imagePath).delete();
      } on FileSystemException {
        // The picker cache or OS may already have removed the local image.
      }
    }
  }

  Future<LocalMealRecord?> pendingMeal(
    String localDate,
    String mealType,
  ) async {
    final row = await customSelect(
      '''
        SELECT * FROM local_meals
        WHERE local_date = ? AND meal_type = ? AND deleted_at IS NULL
        ORDER BY updated_at DESC LIMIT 1
      ''',
      variables: [Variable<String>(localDate), Variable<String>(mealType)],
    ).getSingleOrNull();
    return row == null ? null : LocalMealRecord.fromRow(row);
  }

  Future<int> insertMeal(LocalMealRecord meal) => customInsert(
        '''
          INSERT INTO local_meals
            (local_id, server_id, meal_type, eaten_at, local_date, sync_status, updated_at)
          VALUES (?, NULL, ?, ?, ?, ?, ?)
        ''',
        variables: [
          Variable<String>(meal.localId),
          Variable<String>(meal.mealType),
          Variable<String>(meal.eatenAt.toUtc().toIso8601String()),
          Variable<String>(meal.localDate),
          Variable<String>(meal.syncStatus),
          Variable<String>(meal.updatedAt.toUtc().toIso8601String()),
        ],
      );

  Future<int> insertItem(LocalMealItemRecord item) => customInsert(
        '''
          INSERT INTO local_meal_items
            (local_id, meal_local_id, server_id, food_id, food_name_snapshot,
             amount, amount_unit, calories, protein, carbs, fat, fiber,
             sync_status, updated_at)
          VALUES (?, ?, NULL, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        variables: [
          Variable<String>(item.localId),
          Variable<String>(item.mealLocalId),
          Variable<String>(item.foodId),
          Variable<String>(item.foodName),
          Variable<double>(item.amount),
          Variable<String>(item.unit),
          Variable<double>(item.nutrition.calories),
          Variable<double>(item.nutrition.protein),
          Variable<double>(item.nutrition.carbs),
          Variable<double>(item.nutrition.fat),
          Variable<double>(item.nutrition.fiber),
          Variable<String>(item.syncStatus),
          Variable<String>(item.updatedAt.toUtc().toIso8601String()),
        ],
      );

  Future<int> enqueue(OutboxRecord record) => customInsert(
        '''
          INSERT OR IGNORE INTO sync_outbox
            (id, aggregate_type, aggregate_local_id, operation, payload_json,
             idempotency_key, status, attempts, created_at, updated_at)
          VALUES (?, ?, ?, ?, ?, ?, 'pending', 0, ?, ?)
        ''',
        variables: [
          Variable<String>(record.id),
          Variable<String>(record.aggregateType),
          Variable<String>(record.aggregateLocalId),
          Variable<String>(record.operation),
          Variable<String>(jsonEncode(record.payload)),
          Variable<String>(record.idempotencyKey),
          Variable<String>(record.createdAt.toUtc().toIso8601String()),
          Variable<String>(record.createdAt.toUtc().toIso8601String()),
        ],
      );

  Future<List<OutboxRecord>> pendingOutbox() async {
    final rows = await customSelect('''
        SELECT * FROM sync_outbox
        WHERE status IN ('pending', 'failed')
        ORDER BY created_at ASC
      ''').get();
    return rows.map(OutboxRecord.fromRow).toList();
  }

  Future<LocalMealRecord?> mealByLocalId(String localId) async {
    final row = await customSelect(
      'SELECT * FROM local_meals WHERE local_id = ?',
      variables: [Variable<String>(localId)],
    ).getSingleOrNull();
    return row == null ? null : LocalMealRecord.fromRow(row);
  }

  Future<int> markMealSynced(String localId, String serverId) => customUpdate(
        '''
          UPDATE local_meals
          SET server_id = ?, sync_status = 'synced', updated_at = ?
          WHERE local_id = ?
        ''',
        variables: [
          Variable<String>(serverId),
          Variable<String>(DateTime.now().toUtc().toIso8601String()),
          Variable<String>(localId),
        ],
      );

  Future<int> markItemSynced(String localId, String serverId) => customUpdate(
        '''
          UPDATE local_meal_items
          SET server_id = ?, sync_status = 'synced', updated_at = ?
          WHERE local_id = ?
        ''',
        variables: [
          Variable<String>(serverId),
          Variable<String>(DateTime.now().toUtc().toIso8601String()),
          Variable<String>(localId),
        ],
      );

  Future<int> markOutboxSynced(String id) => customUpdate(
        "UPDATE sync_outbox SET status = 'synced', last_error = NULL, updated_at = ? WHERE id = ?",
        variables: [
          Variable<String>(DateTime.now().toUtc().toIso8601String()),
          Variable<String>(id),
        ],
      );

  Future<int> markOutboxFailed(String id, String error) => customUpdate(
        '''
          UPDATE sync_outbox
          SET status = 'failed', attempts = attempts + 1, last_error = ?, updated_at = ?
          WHERE id = ?
        ''',
        variables: [
          Variable<String>(
            error.substring(0, error.length > 500 ? 500 : error.length),
          ),
          Variable<String>(DateTime.now().toUtc().toIso8601String()),
          Variable<String>(id),
        ],
      );

  Future<List<MealModel>> pendingMealsForDate(String localDate) async {
    final mealRows = await customSelect(
      '''
        SELECT * FROM local_meals
        WHERE local_date = ? AND deleted_at IS NULL AND (
          sync_status != 'synced' OR EXISTS (
            SELECT 1 FROM local_meal_items item
            WHERE item.meal_local_id = local_meals.local_id
              AND item.sync_status != 'synced' AND item.deleted_at IS NULL
          )
        )
        ORDER BY eaten_at ASC
      ''',
      variables: [Variable<String>(localDate)],
    ).get();
    final meals = <MealModel>[];
    for (final mealRow in mealRows) {
      final meal = LocalMealRecord.fromRow(mealRow);
      final itemRows = await customSelect(
        '''
          SELECT * FROM local_meal_items
          WHERE meal_local_id = ? AND sync_status != 'synced' AND deleted_at IS NULL
          ORDER BY updated_at ASC
        ''',
        variables: [Variable<String>(meal.localId)],
      ).get();
      final items = itemRows.map(LocalMealItemRecord.fromRow).toList();
      meals.add(
        MealModel(
          id: meal.localId,
          mealType: meal.mealType,
          eatenAt: meal.eatenAt,
          totals: _sum(items),
          items: items
              .map(
                (item) => MealItemModel(
                  id: item.localId,
                  foodId: item.foodId,
                  foodName: item.foodName,
                  amount: item.amount,
                  unit: item.unit,
                  nutrition: item.nutrition,
                ),
              )
              .toList(),
          pending: true,
        ),
      );
    }
    return meals;
  }

  Future<void> cacheFoods(List<FoodModel> foods) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await transaction(() async {
      for (final food in foods) {
        await customInsert(
          '''
            INSERT OR REPLACE INTO food_cache
              (id, name_normalized, payload_json, updated_at)
            VALUES (?, ?, ?, ?)
          ''',
          variables: [
            Variable<String>(food.id),
            Variable<String>(food.name.toLowerCase()),
            Variable<String>(jsonEncode(food.toCacheJson())),
            Variable<String>(now),
          ],
        );
      }
    });
  }

  Future<List<FoodModel>> searchCachedFoods(String query) async {
    final rows = await customSelect(
      '''
        SELECT payload_json FROM food_cache
        WHERE name_normalized LIKE ? OR payload_json LIKE ?
        ORDER BY updated_at DESC LIMIT 30
      ''',
      variables: [
        Variable<String>('%${query.toLowerCase()}%'),
        Variable<String>('%$query%'),
      ],
    ).get();
    return rows
        .map(
          (row) => FoodModel.fromJson(
            jsonDecode(row.read<String>('payload_json'))
                as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  Future<void> clearPrivateData() async {
    final visionTasks = await pendingVisionTasks();
    await transaction(() async {
      await customStatement('DELETE FROM local_vision_tasks');
      await customStatement('DELETE FROM sync_outbox');
      await customStatement('DELETE FROM local_meal_items');
      await customStatement('DELETE FROM local_meals');
      await customStatement('DELETE FROM food_cache');
      await customStatement('DELETE FROM local_workout_sets');
      await customStatement('DELETE FROM local_workout_sessions');
    });
    for (final task in visionTasks) {
      try {
        await File(task.imagePath).delete();
      } on FileSystemException {
        // Private file was already removed.
      }
    }
  }

  Future<void> updatePendingItem(String localId, double amount) async {
    await transaction(() async {
      final row = await customSelect(
        'SELECT * FROM local_meal_items WHERE local_id = ? AND deleted_at IS NULL',
        variables: [Variable<String>(localId)],
      ).getSingleOrNull();
      if (row == null) throw StateError('Local meal item not found');
      final item = LocalMealItemRecord.fromRow(row);
      final factor = amount / item.amount;
      final now = DateTime.now().toUtc().toIso8601String();
      await customUpdate(
        '''
          UPDATE local_meal_items
          SET amount = ?, calories = ?, protein = ?, carbs = ?, fat = ?, fiber = ?,
              updated_at = ?
          WHERE local_id = ?
        ''',
        variables: [
          Variable<double>(amount),
          Variable<double>(item.nutrition.calories * factor),
          Variable<double>(item.nutrition.protein * factor),
          Variable<double>(item.nutrition.carbs * factor),
          Variable<double>(item.nutrition.fat * factor),
          Variable<double>(item.nutrition.fiber * factor),
          Variable<String>(now),
          Variable<String>(localId),
        ],
      );
      final outbox = await customSelect(
        "SELECT id, payload_json FROM sync_outbox WHERE aggregate_local_id = ? AND status != 'synced'",
        variables: [Variable<String>(localId)],
      ).getSingleOrNull();
      if (outbox != null) {
        final payload = jsonDecode(
          outbox.read<String>('payload_json'),
        ) as Map<String, dynamic>;
        payload['amount'] = amount;
        await customUpdate(
          "UPDATE sync_outbox SET payload_json = ?, status = 'pending', updated_at = ? WHERE id = ?",
          variables: [
            Variable<String>(jsonEncode(payload)),
            Variable<String>(now),
            Variable<String>(outbox.read<String>('id')),
          ],
        );
      }
    });
  }

  Future<void> deletePendingItem(String localId) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await transaction(() async {
      await customUpdate(
        "UPDATE local_meal_items SET deleted_at = ?, sync_status = 'cancelled' WHERE local_id = ?",
        variables: [Variable<String>(now), Variable<String>(localId)],
      );
      await customUpdate(
        "UPDATE sync_outbox SET status = 'cancelled', updated_at = ? WHERE aggregate_local_id = ? AND status != 'synced'",
        variables: [Variable<String>(now), Variable<String>(localId)],
      );
    });
  }

  static NutritionTotals _sum(List<LocalMealItemRecord> items) =>
      NutritionTotals(
        calories: items.fold(
          0,
          (value, item) => value + item.nutrition.calories,
        ),
        protein: items.fold(0, (value, item) => value + item.nutrition.protein),
        carbs: items.fold(0, (value, item) => value + item.nutrition.carbs),
        fat: items.fold(0, (value, item) => value + item.nutrition.fat),
        fiber: items.fold(0, (value, item) => value + item.nutrition.fiber),
      );
}

class LocalMealRecord {
  const LocalMealRecord({
    required this.localId,
    required this.mealType,
    required this.eatenAt,
    required this.localDate,
    required this.syncStatus,
    required this.updatedAt,
    this.serverId,
  });

  factory LocalMealRecord.fromRow(QueryRow row) => LocalMealRecord(
        localId: row.read<String>('local_id'),
        serverId: row.readNullable<String>('server_id'),
        mealType: row.read<String>('meal_type'),
        eatenAt: DateTime.parse(row.read<String>('eaten_at')).toLocal(),
        localDate: row.read<String>('local_date'),
        syncStatus: row.read<String>('sync_status'),
        updatedAt: DateTime.parse(row.read<String>('updated_at')),
      );

  final String localId;
  final String? serverId;
  final String mealType;
  final DateTime eatenAt;
  final String localDate;
  final String syncStatus;
  final DateTime updatedAt;
}

class LocalMealItemRecord {
  const LocalMealItemRecord({
    required this.localId,
    required this.mealLocalId,
    required this.foodId,
    required this.foodName,
    required this.amount,
    required this.unit,
    required this.nutrition,
    required this.syncStatus,
    required this.updatedAt,
    this.serverId,
  });

  factory LocalMealItemRecord.fromRow(QueryRow row) => LocalMealItemRecord(
        localId: row.read<String>('local_id'),
        mealLocalId: row.read<String>('meal_local_id'),
        serverId: row.readNullable<String>('server_id'),
        foodId: row.read<String>('food_id'),
        foodName: row.read<String>('food_name_snapshot'),
        amount: row.read<double>('amount'),
        unit: row.read<String>('amount_unit'),
        nutrition: NutritionTotals(
          calories: row.read<double>('calories'),
          protein: row.read<double>('protein'),
          carbs: row.read<double>('carbs'),
          fat: row.read<double>('fat'),
          fiber: row.read<double>('fiber'),
        ),
        syncStatus: row.read<String>('sync_status'),
        updatedAt: DateTime.parse(row.read<String>('updated_at')),
      );

  final String localId;
  final String mealLocalId;
  final String? serverId;
  final String foodId;
  final String foodName;
  final double amount;
  final String unit;
  final NutritionTotals nutrition;
  final String syncStatus;
  final DateTime updatedAt;
}

class OutboxRecord {
  const OutboxRecord({
    required this.id,
    required this.aggregateType,
    required this.aggregateLocalId,
    required this.operation,
    required this.payload,
    required this.idempotencyKey,
    required this.createdAt,
  });

  factory OutboxRecord.fromRow(QueryRow row) => OutboxRecord(
        id: row.read<String>('id'),
        aggregateType: row.read<String>('aggregate_type'),
        aggregateLocalId: row.read<String>('aggregate_local_id'),
        operation: row.read<String>('operation'),
        payload: jsonDecode(row.read<String>('payload_json'))
            as Map<String, dynamic>,
        idempotencyKey: row.read<String>('idempotency_key'),
        createdAt: DateTime.parse(row.read<String>('created_at')),
      );

  final String id;
  final String aggregateType;
  final String aggregateLocalId;
  final String operation;
  final Map<String, dynamic> payload;
  final String idempotencyKey;
  final DateTime createdAt;
}

class VisionTaskRecord {
  const VisionTaskRecord({
    required this.localId,
    required this.imagePath,
    required this.mealType,
    required this.locationContext,
    required this.status,
    required this.uploadProgress,
    required this.createdAt,
    required this.updatedAt,
    this.analysisId,
    this.lastError,
  });

  factory VisionTaskRecord.fromRow(QueryRow row) => VisionTaskRecord(
        localId: row.read<String>('local_id'),
        imagePath: row.read<String>('image_path'),
        mealType: row.read<String>('meal_type'),
        locationContext: row.read<String>('location_context'),
        analysisId: row.readNullable<String>('analysis_id'),
        status: row.read<String>('status'),
        uploadProgress: row.read<double>('upload_progress'),
        lastError: row.readNullable<String>('last_error'),
        createdAt: DateTime.parse(row.read<String>('created_at')).toLocal(),
        updatedAt: DateTime.parse(row.read<String>('updated_at')).toLocal(),
      );

  VisionTaskRecord copyWith({
    String? analysisId,
    String? status,
    double? uploadProgress,
    String? lastError,
    bool clearError = false,
    DateTime? updatedAt,
  }) =>
      VisionTaskRecord(
        localId: localId,
        imagePath: imagePath,
        mealType: mealType,
        locationContext: locationContext,
        analysisId: analysisId ?? this.analysisId,
        status: status ?? this.status,
        uploadProgress: uploadProgress ?? this.uploadProgress,
        lastError: clearError ? null : lastError ?? this.lastError,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  final String localId;
  final String imagePath;
  final String mealType;
  final String locationContext;
  final String? analysisId;
  final String status;
  final double uploadProgress;
  final String? lastError;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class LocalWorkoutRecord {
  const LocalWorkoutRecord({
    required this.localId,
    required this.startedAt,
    required this.status,
    required this.syncStatus,
    required this.updatedAt,
    this.serverId,
    this.trainingDayId,
    this.endedAt,
    this.sessionRpe,
  });

  factory LocalWorkoutRecord.fromRow(QueryRow row) => LocalWorkoutRecord(
        localId: row.read<String>('local_id'),
        serverId: row.readNullable<String>('server_id'),
        trainingDayId: row.readNullable<String>('training_day_id'),
        startedAt: DateTime.parse(row.read<String>('started_at')).toLocal(),
        endedAt: row.readNullable<String>('ended_at') == null
            ? null
            : DateTime.parse(row.read<String>('ended_at')).toLocal(),
        status: row.read<String>('status'),
        sessionRpe: row.readNullable<double>('session_rpe'),
        syncStatus: row.read<String>('sync_status'),
        updatedAt: DateTime.parse(row.read<String>('updated_at')).toLocal(),
      );

  final String localId;
  final String? serverId;
  final String? trainingDayId;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String status;
  final double? sessionRpe;
  final String syncStatus;
  final DateTime updatedAt;
}

class LocalWorkoutSetRecord {
  const LocalWorkoutSetRecord({
    required this.localId,
    required this.sessionLocalId,
    required this.exerciseId,
    required this.setNumber,
    required this.setType,
    required this.weightKg,
    required this.reps,
    required this.rir,
    required this.restSeconds,
    required this.syncStatus,
    required this.updatedAt,
    this.serverId,
  });

  factory LocalWorkoutSetRecord.fromRow(QueryRow row) => LocalWorkoutSetRecord(
        localId: row.read<String>('local_id'),
        serverId: row.readNullable<String>('server_id'),
        sessionLocalId: row.read<String>('session_local_id'),
        exerciseId: row.read<String>('exercise_id'),
        setNumber: row.read<int>('set_number'),
        setType: row.read<String>('set_type'),
        weightKg: row.read<double>('weight_kg'),
        reps: row.read<int>('reps'),
        rir: row.readNullable<double>('rir'),
        restSeconds: row.read<int>('rest_seconds'),
        syncStatus: row.read<String>('sync_status'),
        updatedAt: DateTime.parse(row.read<String>('updated_at')).toLocal(),
      );

  final String localId;
  final String? serverId;
  final String sessionLocalId;
  final String exerciseId;
  final int setNumber;
  final String setType;
  final double weightKg;
  final int reps;
  final double? rir;
  final int restSeconds;
  final String syncStatus;
  final DateTime updatedAt;
}

LazyDatabase _openConnection() => LazyDatabase(() async {
      final directory = await getApplicationDocumentsDirectory();
      final file = File(path.join(directory.path, 'personal_health_os.sqlite'));
      return NativeDatabase.createInBackground(file);
    });
