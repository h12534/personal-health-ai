double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

class NutritionTotals {
  const NutritionTotals({
    this.calories = 0,
    this.protein = 0,
    this.carbs = 0,
    this.fat = 0,
    this.fiber = 0,
  });

  factory NutritionTotals.fromJson(Map<String, dynamic> json) =>
      NutritionTotals(
        calories: _asDouble(json['calories']),
        protein: _asDouble(json['protein']),
        carbs: _asDouble(json['carbs']),
        fat: _asDouble(json['fat']),
        fiber: _asDouble(json['fiber']),
      );

  final double calories;
  final double protein;
  final double carbs;
  final double fat;
  final double fiber;
}

class DailyNutritionModel {
  const DailyNutritionModel({
    required this.date,
    required this.totals,
    required this.meals,
    required this.mealCounts,
  });

  factory DailyNutritionModel.fromJson(Map<String, dynamic> json) {
    final mealsJson = json['meals'] as Map<String, dynamic>? ?? const {};
    final countJson = json['meal_counts'] as Map<String, dynamic>? ?? const {};
    return DailyNutritionModel(
      date: DateTime.parse(json['date'] as String),
      totals: NutritionTotals.fromJson(json['totals'] as Map<String, dynamic>),
      meals: mealsJson.map(
        (key, value) => MapEntry(
          key,
          NutritionTotals.fromJson(value as Map<String, dynamic>),
        ),
      ),
      mealCounts: countJson.map((key, value) => MapEntry(key, value as int)),
    );
  }

  final DateTime date;
  final NutritionTotals totals;
  final Map<String, NutritionTotals> meals;
  final Map<String, int> mealCounts;
}

class NutritionGoalModel {
  const NutritionGoalModel({
    required this.calories,
    required this.protein,
    this.carbs,
    this.fat,
    required this.fiber,
  });

  factory NutritionGoalModel.fromJson(Map<String, dynamic> json) =>
      NutritionGoalModel(
        calories: json['calorie_target'] as int,
        protein: _asDouble(json['protein_target_g']),
        carbs: json['carbs_target_g'] == null
            ? null
            : _asDouble(json['carbs_target_g']),
        fat: json['fat_target_g'] == null
            ? null
            : _asDouble(json['fat_target_g']),
        fiber: _asDouble(json['fiber_target_g']),
      );

  final int calories;
  final double protein;
  final double? carbs;
  final double? fat;
  final double fiber;
}

class FoodModel {
  const FoodModel({
    required this.id,
    required this.name,
    required this.category,
    required this.caloriesPer100g,
    required this.proteinPer100g,
    required this.carbsPer100g,
    required this.fatPer100g,
    required this.fiberPer100g,
    required this.isFavorite,
    this.brand,
    this.servingDescription,
    this.servingUnit,
    this.servingWeightG,
  });

  factory FoodModel.fromJson(Map<String, dynamic> json) => FoodModel(
        id: json['id'] as String,
        name: json['name'] as String,
        brand: json['brand'] as String?,
        category: json['category'] as String? ?? 'other',
        servingDescription: json['serving_description'] as String?,
        servingUnit: json['serving_unit'] as String?,
        servingWeightG: json['serving_weight_g'] == null
            ? null
            : _asDouble(json['serving_weight_g']),
        caloriesPer100g: _asDouble(json['calories_per_100g']),
        proteinPer100g: _asDouble(json['protein_per_100g']),
        carbsPer100g: _asDouble(json['carbs_per_100g']),
        fatPer100g: _asDouble(json['fat_per_100g']),
        fiberPer100g: _asDouble(json['fiber_per_100g']),
        isFavorite: json['is_favorite'] as bool? ?? false,
      );

  Map<String, Object?> toCacheJson() => {
        'id': id,
        'name': name,
        'brand': brand,
        'category': category,
        'serving_description': servingDescription,
        'serving_unit': servingUnit,
        'serving_weight_g': servingWeightG,
        'calories_per_100g': caloriesPer100g,
        'protein_per_100g': proteinPer100g,
        'carbs_per_100g': carbsPer100g,
        'fat_per_100g': fatPer100g,
        'fiber_per_100g': fiberPer100g,
        'is_favorite': isFavorite,
      };

  double weightFor(double amount, String unit) {
    if (unit == 'g') return amount;
    if (servingUnit == unit && servingWeightG != null) {
      return amount * servingWeightG!;
    }
    throw ArgumentError('该食物不支持 $unit 份量换算');
  }

  NutritionTotals calculate(double amount, String unit) {
    final factor = weightFor(amount, unit) / 100;
    return NutritionTotals(
      calories: caloriesPer100g * factor,
      protein: proteinPer100g * factor,
      carbs: carbsPer100g * factor,
      fat: fatPer100g * factor,
      fiber: fiberPer100g * factor,
    );
  }

  final String id;
  final String name;
  final String? brand;
  final String category;
  final String? servingDescription;
  final String? servingUnit;
  final double? servingWeightG;
  final double caloriesPer100g;
  final double proteinPer100g;
  final double carbsPer100g;
  final double fatPer100g;
  final double fiberPer100g;
  final bool isFavorite;
}

class MealItemModel {
  const MealItemModel({
    required this.id,
    required this.foodId,
    required this.foodName,
    required this.amount,
    required this.unit,
    required this.nutrition,
  });

  factory MealItemModel.fromJson(Map<String, dynamic> json) => MealItemModel(
        id: json['id'] as String,
        foodId: json['food_id'] as String?,
        foodName: json['food_name_snapshot'] as String,
        amount: _asDouble(json['amount']),
        unit: json['amount_unit'] as String,
        nutrition: NutritionTotals.fromJson(json),
      );

  final String id;
  final String? foodId;
  final String foodName;
  final double amount;
  final String unit;
  final NutritionTotals nutrition;
}

class MealModel {
  const MealModel({
    required this.id,
    required this.mealType,
    required this.eatenAt,
    required this.totals,
    required this.items,
    this.pending = false,
  });

  factory MealModel.fromJson(Map<String, dynamic> json) => MealModel(
        id: json['id'] as String,
        mealType: json['meal_type'] as String,
        eatenAt: DateTime.parse(json['eaten_at'] as String).toLocal(),
        totals: NutritionTotals(
          calories: _asDouble(json['total_calories']),
          protein: _asDouble(json['total_protein']),
          carbs: _asDouble(json['total_carbs']),
          fat: _asDouble(json['total_fat']),
          fiber: _asDouble(json['total_fiber']),
        ),
        items: (json['items'] as List<dynamic>? ?? const [])
            .map((item) => MealItemModel.fromJson(item as Map<String, dynamic>))
            .toList(),
      );

  final String id;
  final String mealType;
  final DateTime eatenAt;
  final NutritionTotals totals;
  final List<MealItemModel> items;
  final bool pending;
}
