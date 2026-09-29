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
    required this.steps,
    required this.stepsTarget,
    required this.waterMl,
    required this.trainingCompleted,
    required this.morningWeightCompleted,
    required this.aiNextAction,
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
        steps: json['steps'] as int? ?? 0,
        stepsTarget: json['steps_target'] as int? ?? 8000,
        waterMl: json['water_ml'] as int? ?? 0,
        trainingCompleted: json['training_completed'] as bool? ?? false,
        morningWeightCompleted: json['morning_weight_completed'] as bool? ?? false,
        aiNextAction: json['ai_next_action'] as String,
      );

  final DateTime date;
  final double? todayWeightKg;
  final double? average7dKg;
  final double? weekChangeKg;
  final int caloriesConsumed;
  final int? caloriesTarget;
  final double proteinG;
  final double? proteinTargetG;
  final int steps;
  final int stepsTarget;
  final int waterMl;
  final bool trainingCompleted;
  final bool morningWeightCompleted;
  final String aiNextAction;
}

