double _number(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

class MealTargetRangeModel {
  const MealTargetRangeModel({
    required this.caloriesMin,
    required this.caloriesMax,
    required this.proteinMin,
    required this.proteinMax,
  });

  factory MealTargetRangeModel.fromJson(Map<String, dynamic> json) =>
      MealTargetRangeModel(
        caloriesMin: json['calories_min'] as int,
        caloriesMax: json['calories_max'] as int,
        proteinMin: _number(json['protein_min_g']),
        proteinMax: _number(json['protein_max_g']),
      );

  final int caloriesMin;
  final int caloriesMax;
  final double proteinMin;
  final double proteinMax;
}

class NextMealPlanModel {
  const NextMealPlanModel({
    required this.mealType,
    required this.target,
    required this.remainingCalories,
    required this.remainingProtein,
    required this.strategy,
    required this.overTarget,
    required this.message,
  });

  factory NextMealPlanModel.fromJson(Map<String, dynamic> json) =>
      NextMealPlanModel(
        mealType: json['meal_type'] as String,
        target: MealTargetRangeModel.fromJson(
          json['target'] as Map<String, dynamic>,
        ),
        remainingCalories: json['remaining_calories'] as int,
        remainingProtein: _number(json['remaining_protein_g']),
        strategy: (json['strategy'] as List<dynamic>)
            .map((value) => value.toString())
            .toList(),
        overTarget: json['over_target'] as bool,
        message: json['message'] as String,
      );

  final String mealType;
  final MealTargetRangeModel target;
  final int remainingCalories;
  final double remainingProtein;
  final List<String> strategy;
  final bool overTarget;
  final String message;

  String get mealLabel =>
      const {
        'breakfast': '早餐',
        'lunch': '午餐',
        'dinner': '晚餐',
        'snack': '加餐',
      }[mealType] ??
      '下一餐';
}

class WeightTrendModel {
  const WeightTrendModel({
    required this.direction,
    required this.plateau,
    required this.plateauEligible,
    required this.note,
    this.average7d,
    this.change14d,
  });

  factory WeightTrendModel.fromJson(Map<String, dynamic> json) =>
      WeightTrendModel(
        direction: json['direction'] as String,
        plateau: json['plateau'] as bool,
        plateauEligible: json['plateau_eligible'] as bool,
        note: json['note'] as String,
        average7d: json['average_7d_kg'] == null
            ? null
            : _number(json['average_7d_kg']),
        change14d: json['change_14d_kg'] == null
            ? null
            : _number(json['change_14d_kg']),
      );

  final String direction;
  final bool plateau;
  final bool plateauEligible;
  final String note;
  final double? average7d;
  final double? change14d;
}

class DietAdjustmentModel {
  const DietAdjustmentModel({
    required this.id,
    required this.status,
    required this.previousCalories,
    required this.proposedCalories,
    required this.reason,
  });

  factory DietAdjustmentModel.fromJson(Map<String, dynamic> json) =>
      DietAdjustmentModel(
        id: json['id'] as String,
        status: json['status'] as String,
        previousCalories: json['previous_calorie_target'] as int,
        proposedCalories: json['proposed_calorie_target'] as int,
        reason: json['reason'] as String,
      );

  final String id;
  final String status;
  final int previousCalories;
  final int proposedCalories;
  final String reason;
}

class CoachOverviewModel {
  const CoachOverviewModel({
    required this.headline,
    required this.observations,
    required this.nextActions,
    required this.trend,
    this.adjustment,
  });

  factory CoachOverviewModel.fromJson(Map<String, dynamic> json) =>
      CoachOverviewModel(
        headline: json['headline'] as String,
        observations: (json['observations'] as List<dynamic>)
            .map((value) => value.toString())
            .toList(),
        nextActions: (json['next_actions'] as List<dynamic>)
            .map((value) => value.toString())
            .toList(),
        trend: WeightTrendModel.fromJson(
          json['trend'] as Map<String, dynamic>,
        ),
        adjustment: json['adjustment'] == null
            ? null
            : DietAdjustmentModel.fromJson(
                json['adjustment'] as Map<String, dynamic>,
              ),
      );

  final String headline;
  final List<String> observations;
  final List<String> nextActions;
  final WeightTrendModel trend;
  final DietAdjustmentModel? adjustment;
}

class CoachActionModel {
  const CoachActionModel({
    required this.type,
    required this.label,
    this.targetId,
  });

  factory CoachActionModel.fromJson(Map<String, dynamic> json) =>
      CoachActionModel(
        type: json['type'] as String,
        label: json['label'] as String,
        targetId: json['target_id'] as String?,
      );

  final String type;
  final String label;
  final String? targetId;
}

class CoachReplyModel {
  const CoachReplyModel({
    required this.conversationId,
    required this.intent,
    required this.message,
    required this.actions,
    required this.provider,
    this.safetyNotice,
  });

  factory CoachReplyModel.fromJson(Map<String, dynamic> json) =>
      CoachReplyModel(
        conversationId: json['conversation_id'] as String,
        intent: json['intent'] as String,
        message: json['message'] as String,
        actions: (json['suggested_actions'] as List<dynamic>)
            .map(
              (value) =>
                  CoachActionModel.fromJson(value as Map<String, dynamic>),
            )
            .toList(),
        safetyNotice: json['safety_notice'] as String?,
        provider: json['provider'] as String,
      );

  final String conversationId;
  final String intent;
  final String message;
  final List<CoachActionModel> actions;
  final String? safetyNotice;
  final String provider;
}

class CoachBubble {
  const CoachBubble({
    required this.text,
    required this.fromUser,
    this.actions = const [],
    this.safetyNotice,
  });

  final String text;
  final bool fromUser;
  final List<CoachActionModel> actions;
  final String? safetyNotice;
}

class CanteenRecommendationModel {
  const CanteenRecommendationModel({
    required this.dishName,
    required this.calories,
    required this.protein,
    required this.score,
    required this.reasons,
  });

  factory CanteenRecommendationModel.fromJson(Map<String, dynamic> json) {
    final dish = json['dish'] as Map<String, dynamic>;
    return CanteenRecommendationModel(
      dishName: dish['name'] as String,
      calories: _number(dish['calories']),
      protein: _number(dish['protein_g']),
      score: _number(json['match_score']),
      reasons: (json['reasons'] as List<dynamic>)
          .map((value) => value.toString())
          .toList(),
    );
  }

  final String dishName;
  final double calories;
  final double protein;
  final double score;
  final List<String> reasons;
}

class CanteenModel {
  const CanteenModel({
    required this.id,
    required this.name,
    this.campus,
    this.location,
    this.note,
    this.stalls = const [],
  });

  factory CanteenModel.fromJson(Map<String, dynamic> json) => CanteenModel(
        id: json['id'] as String,
        name: json['name'] as String,
        campus: json['campus'] as String?,
        location: json['location'] as String?,
        note: json['note'] as String?,
        stalls: (json['stalls'] as List<dynamic>? ?? const [])
            .map(
              (value) =>
                  CanteenStallModel.fromJson(value as Map<String, dynamic>),
            )
            .toList(),
      );

  final String id;
  final String name;
  final String? campus;
  final String? location;
  final String? note;
  final List<CanteenStallModel> stalls;
}

class CanteenStallModel {
  const CanteenStallModel({
    required this.id,
    required this.canteenId,
    required this.name,
    required this.dishes,
    this.cuisine,
    this.floor,
    this.locationNote,
  });

  factory CanteenStallModel.fromJson(Map<String, dynamic> json) =>
      CanteenStallModel(
        id: json['id'] as String,
        canteenId: json['canteen_id'] as String,
        name: json['name'] as String,
        cuisine: json['cuisine'] as String?,
        floor: json['floor'] as String?,
        locationNote: json['location_note'] as String?,
        dishes: (json['dishes'] as List<dynamic>? ?? const [])
            .map(
              (value) =>
                  CanteenDishModel.fromJson(value as Map<String, dynamic>),
            )
            .toList(),
      );

  final String id;
  final String canteenId;
  final String name;
  final String? cuisine;
  final String? floor;
  final String? locationNote;
  final List<CanteenDishModel> dishes;
}

class CanteenDishModel {
  const CanteenDishModel({
    required this.id,
    required this.stallId,
    required this.name,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.fiber,
    required this.confidence,
    required this.favorite,
    required this.source,
    this.portionDescription,
    this.averageWeight,
  });

  factory CanteenDishModel.fromJson(Map<String, dynamic> json) =>
      CanteenDishModel(
        id: json['id'] as String,
        stallId: json['stall_id'] as String,
        name: json['name'] as String,
        calories: _number(json['calories']),
        protein: _number(json['protein_g']),
        carbs: _number(json['carbs_g']),
        fat: _number(json['fat_g']),
        fiber: _number(json['fiber_g']),
        portionDescription: json['portion_description'] as String?,
        averageWeight: json['average_weight_g'] == null
            ? null
            : _number(json['average_weight_g']),
        confidence: _number(json['confidence']),
        favorite: json['favorite'] as bool? ?? false,
        source: json['source'] as String? ?? 'manual',
      );

  final String id;
  final String stallId;
  final String name;
  final double calories;
  final double protein;
  final double carbs;
  final double fat;
  final double fiber;
  final String? portionDescription;
  final double? averageWeight;
  final double confidence;
  final bool favorite;
  final String source;

  Map<String, Object?> toWriteJson({bool? favoriteOverride}) => {
        'name': name,
        'calories': calories,
        'protein_g': protein,
        'carbs_g': carbs,
        'fat_g': fat,
        'fiber_g': fiber,
        'portion_description': portionDescription,
        'average_weight_g': averageWeight,
        'confidence': confidence,
        'favorite': favoriteOverride ?? favorite,
        'source': source,
        'tags': <String>[],
      };
}

class SavedMealModel {
  const SavedMealModel({
    required this.id,
    required this.name,
    required this.mealType,
    required this.itemCount,
    required this.totalCalories,
    this.note,
  });

  factory SavedMealModel.fromJson(Map<String, dynamic> json) {
    final items = json['items'] as List<dynamic>? ?? const [];
    return SavedMealModel(
      id: json['id'] as String,
      name: json['name'] as String,
      mealType: json['meal_type'] as String,
      note: json['note'] as String?,
      itemCount: items.length,
      totalCalories: items.fold<double>(
        0,
        (total, value) =>
            total + _number((value as Map<String, dynamic>)['calories']),
      ),
    );
  }

  final String id;
  final String name;
  final String mealType;
  final String? note;
  final int itemCount;
  final double totalCalories;
}
