import 'nutrition_models.dart';

double _number(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

class MealAnalysisItemModel {
  const MealAnalysisItemModel({
    required this.id,
    required this.name,
    required this.matchType,
    required this.confidenceLabel,
    required this.weightG,
    required this.minWeightG,
    required this.maxWeightG,
    required this.calories,
    required this.minCalories,
    required this.maxCalories,
    required this.recognitionConfidence,
    required this.portionConfidence,
    required this.matchConfidence,
    required this.hiddenIngredient,
    required this.userModified,
    required this.hiddenIngredients,
    this.foodId,
    this.foodName,
    this.portionDescription,
    this.cookingMethod,
  });

  factory MealAnalysisItemModel.fromJson(Map<String, dynamic> json) =>
      MealAnalysisItemModel(
        id: json['id'] as String,
        name: json['detected_name'] as String,
        foodId: json['matched_food_id'] as String?,
        foodName: json['matched_food_name'] as String?,
        matchType: json['match_type'] as String,
        confidenceLabel: json['confidence_label'] as String,
        weightG: _number(json['estimated_weight_g']),
        minWeightG: _number(json['min_weight_g']),
        maxWeightG: _number(json['max_weight_g']),
        calories: _number(json['calories']),
        minCalories: _number(json['min_calories']),
        maxCalories: _number(json['max_calories']),
        recognitionConfidence: _number(json['recognition_confidence']),
        portionConfidence: _number(json['portion_confidence']),
        matchConfidence: _number(json['match_confidence']),
        portionDescription: json['portion_description'] as String?,
        cookingMethod: json['cooking_method'] as String?,
        hiddenIngredient: json['is_hidden_ingredient'] as bool? ?? false,
        userModified: json['user_modified'] as bool? ?? false,
        hiddenIngredients:
            (json['possible_hidden_ingredients'] as List<dynamic>? ?? const [])
                .map((value) => value.toString())
                .toList(),
      );

  final String id;
  final String name;
  final String? foodId;
  final String? foodName;
  final String matchType;
  final String confidenceLabel;
  final double weightG;
  final double minWeightG;
  final double maxWeightG;
  final double calories;
  final double minCalories;
  final double maxCalories;
  final double recognitionConfidence;
  final double portionConfidence;
  final double matchConfidence;
  final String? portionDescription;
  final String? cookingMethod;
  final bool hiddenIngredient;
  final bool userModified;
  final List<String> hiddenIngredients;
}

class MealAnalysisTotalsModel {
  const MealAnalysisTotalsModel({
    required this.center,
    required this.minCalories,
    required this.maxCalories,
  });

  factory MealAnalysisTotalsModel.fromJson(Map<String, dynamic> json) =>
      MealAnalysisTotalsModel(
        center: NutritionTotals.fromJson(json),
        minCalories: _number(json['min_calories']),
        maxCalories: _number(json['max_calories']),
      );

  final NutritionTotals center;
  final double minCalories;
  final double maxCalories;
}

class MealAnalysisModel {
  const MealAnalysisModel({
    required this.id,
    required this.status,
    required this.provider,
    required this.model,
    required this.promptVersion,
    required this.warnings,
    required this.items,
    required this.totals,
    required this.reanalysisCount,
    this.mealType,
    this.overallConfidence,
    this.confidenceLabel,
    this.errorCode,
    this.errorMessage,
    this.confirmedMealId,
  });

  factory MealAnalysisModel.fromJson(Map<String, dynamic> json) =>
      MealAnalysisModel(
        id: json['id'] as String,
        status: json['status'] as String,
        mealType: json['meal_type'] as String?,
        provider: json['provider'] as String,
        model: json['model'] as String,
        promptVersion: json['prompt_version'] as String,
        overallConfidence: json['overall_confidence'] == null
            ? null
            : _number(json['overall_confidence']),
        confidenceLabel: json['confidence_label'] as String?,
        warnings: (json['warnings'] as List<dynamic>? ?? const [])
            .map((value) => value.toString())
            .toList(),
        errorCode: json['error_code'] as String?,
        errorMessage: json['error_message'] as String?,
        reanalysisCount: json['reanalysis_count'] as int? ?? 0,
        confirmedMealId: json['confirmed_meal_id'] as String?,
        items: (json['items'] as List<dynamic>? ?? const [])
            .map(
              (item) =>
                  MealAnalysisItemModel.fromJson(item as Map<String, dynamic>),
            )
            .toList(),
        totals: MealAnalysisTotalsModel.fromJson(
          json['totals'] as Map<String, dynamic>,
        ),
      );

  bool get processing => status == 'pending' || status == 'processing';
  bool get editable => status == 'completed';

  final String id;
  final String status;
  final String? mealType;
  final String provider;
  final String model;
  final String promptVersion;
  final double? overallConfidence;
  final String? confidenceLabel;
  final List<String> warnings;
  final String? errorCode;
  final String? errorMessage;
  final int reanalysisCount;
  final String? confirmedMealId;
  final List<MealAnalysisItemModel> items;
  final MealAnalysisTotalsModel totals;
}
