class ExerciseModel {
  const ExerciseModel({
    required this.id,
    required this.name,
    required this.movementPattern,
    required this.primaryMuscles,
    required this.equipment,
    required this.instructions,
    required this.executionCues,
    required this.safetyNotes,
    required this.compound,
  });

  factory ExerciseModel.fromJson(Map<String, dynamic> json) => ExerciseModel(
        id: json['id'] as String,
        name: json['name'] as String,
        movementPattern: json['movement_pattern'] as String,
        primaryMuscles: (json['primary_muscles'] as List<dynamic>)
            .map((value) => value as String)
            .toList(),
        equipment: (json['equipment'] as List<dynamic>)
            .map((value) => value as String)
            .toList(),
        instructions: json['instructions'] as String,
        executionCues: (json['execution_cues'] as List<dynamic>)
            .map((value) => value as String)
            .toList(),
        safetyNotes: (json['safety_notes'] as List<dynamic>)
            .map((value) => value as String)
            .toList(),
        compound: json['compound'] as bool? ?? true,
      );

  final String id;
  final String name;
  final String movementPattern;
  final List<String> primaryMuscles;
  final List<String> equipment;
  final String instructions;
  final List<String> executionCues;
  final List<String> safetyNotes;
  final bool compound;
}

class TrainingExerciseModel {
  const TrainingExerciseModel({
    required this.id,
    required this.exercise,
    required this.targetSets,
    required this.repMin,
    required this.repMax,
    required this.targetRir,
    required this.restSeconds,
    this.targetWeightKg,
  });

  factory TrainingExerciseModel.fromJson(Map<String, dynamic> json) =>
      TrainingExerciseModel(
        id: json['id'] as String,
        exercise: ExerciseModel.fromJson(
          json['exercise'] as Map<String, dynamic>,
        ),
        targetSets: json['target_sets'] as int,
        repMin: json['target_rep_min'] as int,
        repMax: json['target_rep_max'] as int,
        targetWeightKg: (json['target_weight_kg'] as num?)?.toDouble(),
        targetRir: (json['target_rir'] as num?)?.toDouble(),
        restSeconds: json['rest_seconds'] as int? ?? 120,
      );

  final String id;
  final ExerciseModel exercise;
  final int targetSets;
  final int repMin;
  final int repMax;
  final double? targetWeightKg;
  final double? targetRir;
  final int restSeconds;
}

class TrainingDayModel {
  const TrainingDayModel({
    required this.id,
    required this.name,
    required this.focus,
    required this.estimatedDurationMin,
    required this.exercises,
  });

  factory TrainingDayModel.fromJson(Map<String, dynamic> json) =>
      TrainingDayModel(
        id: json['id'] as String,
        name: json['name'] as String,
        focus: json['focus'] as String,
        estimatedDurationMin: json['estimated_duration_min'] as int,
        exercises: (json['exercises'] as List<dynamic>)
            .map(
              (value) => TrainingExerciseModel.fromJson(
                value as Map<String, dynamic>,
              ),
            )
            .toList(),
      );

  final String id;
  final String name;
  final String focus;
  final int estimatedDurationMin;
  final List<TrainingExerciseModel> exercises;
}

class TrainingPlanModel {
  const TrainingPlanModel({
    required this.id,
    required this.name,
    required this.difficulty,
    required this.sessionsPerWeek,
    required this.active,
    required this.days,
  });

  factory TrainingPlanModel.fromJson(Map<String, dynamic> json) =>
      TrainingPlanModel(
        id: json['id'] as String,
        name: json['name'] as String,
        difficulty: json['difficulty'] as String,
        sessionsPerWeek: json['sessions_per_week'] as int,
        active: json['active'] as bool,
        days: (json['days'] as List<dynamic>)
            .map(
              (value) => TrainingDayModel.fromJson(
                value as Map<String, dynamic>,
              ),
            )
            .toList(),
      );

  final String id;
  final String name;
  final String difficulty;
  final int sessionsPerWeek;
  final bool active;
  final List<TrainingDayModel> days;
}

class WorkoutSetModel {
  const WorkoutSetModel({
    required this.id,
    required this.exerciseId,
    required this.setNumber,
    required this.setType,
    required this.weightKg,
    required this.reps,
    required this.rir,
  });

  factory WorkoutSetModel.fromJson(Map<String, dynamic> json) =>
      WorkoutSetModel(
        id: json['id'] as String,
        exerciseId: json['exercise_id'] as String,
        setNumber: json['set_number'] as int,
        setType: json['set_type'] as String,
        weightKg: (json['weight_kg'] as num).toDouble(),
        reps: json['reps'] as int,
        rir: (json['rir'] as num?)?.toDouble(),
      );

  final String id;
  final String exerciseId;
  final int setNumber;
  final String setType;
  final double weightKg;
  final int reps;
  final double? rir;
}

class WorkoutModel {
  const WorkoutModel({
    required this.id,
    required this.trainingDayId,
    required this.startedAt,
    required this.status,
    required this.durationMin,
    required this.sets,
  });

  factory WorkoutModel.fromJson(Map<String, dynamic> json) => WorkoutModel(
        id: json['id'] as String,
        trainingDayId: json['training_day_id'] as String?,
        startedAt: DateTime.parse(json['started_at'] as String),
        status: json['status'] as String,
        durationMin: json['duration_min'] as int?,
        sets: (json['sets'] as List<dynamic>)
            .map(
              (value) => WorkoutSetModel.fromJson(
                value as Map<String, dynamic>,
              ),
            )
            .toList(),
      );

  final String id;
  final String? trainingDayId;
  final DateTime startedAt;
  final String status;
  final int? durationMin;
  final List<WorkoutSetModel> sets;
}

class PersonalRecordModel {
  const PersonalRecordModel({
    required this.exerciseId,
    required this.type,
    required this.value,
    required this.achievedAt,
    required this.confidence,
  });

  factory PersonalRecordModel.fromJson(Map<String, dynamic> json) =>
      PersonalRecordModel(
        exerciseId: json['exercise_id'] as String,
        type: json['pr_type'] as String,
        value: (json['value'] as num).toDouble(),
        achievedAt: DateTime.parse(json['achieved_at'] as String),
        confidence: json['confidence'] as String,
      );

  final String exerciseId;
  final String type;
  final double value;
  final DateTime achievedAt;
  final String confidence;
}

class TrainingCoachReply {
  const TrainingCoachReply({
    required this.message,
    required this.intent,
    required this.riskLevel,
    required this.safetyNotice,
    required this.actions,
  });

  factory TrainingCoachReply.fromJson(Map<String, dynamic> json) =>
      TrainingCoachReply(
        message: json['message'] as String,
        intent: json['intent'] as String,
        riskLevel: json['risk_level'] as String,
        safetyNotice: json['safety_notice'] as String?,
        actions: (json['suggested_actions'] as List<dynamic>)
            .map((value) => value as Map<String, dynamic>)
            .toList(),
      );

  final String message;
  final String intent;
  final String riskLevel;
  final String? safetyNotice;
  final List<Map<String, dynamic>> actions;
}

class HealthPermissionModel {
  const HealthPermissionModel({
    required this.dataType,
    required this.enabled,
    required this.authorizationStatus,
  });

  factory HealthPermissionModel.fromJson(Map<String, dynamic> json) =>
      HealthPermissionModel(
        dataType: json['data_type'] as String,
        enabled: json['enabled'] as bool,
        authorizationStatus: json['authorization_status'] as String,
      );

  final String dataType;
  final bool enabled;
  final String authorizationStatus;
}
