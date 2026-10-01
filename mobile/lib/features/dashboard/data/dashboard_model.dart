import '../../supervision/data/supervision_models.dart';

class DashboardModel {
  const DashboardModel({
    required this.date,
    required this.todayWeightKg,
    required this.average7dKg,
    required this.weekChangeKg,
    required this.caloriesConsumed,
    required this.caloriesTarget,
    required this.proteinG,
    required this.proteinTargetG,
    this.carbsG = 0,
    this.carbsTargetG,
    this.fatG = 0,
    this.fatTargetG,
    this.fiberG = 0,
    this.fiberTargetG,
    required this.steps,
    required this.stepsTarget,
    required this.waterMl,
    required this.trainingCompleted,
    required this.morningWeightCompleted,
    required this.aiNextAction,
    this.keyTasks = const [],
  });

  factory DashboardModel.fromJson(Map<String, dynamic> json) => DashboardModel(
        date: DateTime.parse(json['date'] as String),
        todayWeightKg: (json['today_weight_kg'] as num?)?.toDouble(),
        average7dKg: (json['average_7d_kg'] as num?)?.toDouble(),
        weekChangeKg: (json['week_change_kg'] as num?)?.toDouble(),
        caloriesConsumed: json['calories_consumed'] as int? ?? 0,
        caloriesTarget: json['calories_target'] as int?,
        proteinG: (json['protein_g'] as num?)?.toDouble() ?? 0,
        proteinTargetG: (json['protein_target_g'] as num?)?.toDouble(),
        carbsG: (json['carbs_g'] as num?)?.toDouble() ?? 0,
        carbsTargetG: (json['carbs_target_g'] as num?)?.toDouble(),
        fatG: (json['fat_g'] as num?)?.toDouble() ?? 0,
        fatTargetG: (json['fat_target_g'] as num?)?.toDouble(),
        fiberG: (json['fiber_g'] as num?)?.toDouble() ?? 0,
        fiberTargetG: (json['fiber_target_g'] as num?)?.toDouble(),
        steps: json['steps'] as int?,
        stepsTarget: json['steps_target'] as int? ?? 8000,
        waterMl: json['water_ml'] as int? ?? 0,
        trainingCompleted: json['training_completed'] as bool? ?? false,
        morningWeightCompleted:
            json['morning_weight_completed'] as bool? ?? false,
        aiNextAction: json['ai_next_action'] as String,
        keyTasks: (json['key_tasks'] as List<dynamic>? ?? const [])
            .map(
              (item) => DailyTaskModel.fromJson(
                item as Map<String, dynamic>,
              ),
            )
            .toList(),
      );

  final DateTime date;
  final double? todayWeightKg;
  final double? average7dKg;
  final double? weekChangeKg;
  final int caloriesConsumed;
  final int? caloriesTarget;
  final double proteinG;
  final double? proteinTargetG;
  final double carbsG;
  final double? carbsTargetG;
  final double fatG;
  final double? fatTargetG;
  final double fiberG;
  final double? fiberTargetG;
  final int? steps;
  final int stepsTarget;
  final int waterMl;
  final bool trainingCompleted;
  final bool morningWeightCompleted;
  final String aiNextAction;
  final List<DailyTaskModel> keyTasks;
}
