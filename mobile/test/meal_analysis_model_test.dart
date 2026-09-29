import 'package:flutter_test/flutter_test.dart';
import 'package:personal_health_os/features/nutrition/data/meal_analysis_models.dart';

void main() {
  test('meal analysis parses nutrition ranges and confidence', () {
    final model = MealAnalysisModel.fromJson({
      'id': 'analysis-1',
      'status': 'completed',
      'meal_type': 'lunch',
      'provider': 'mock',
      'model': 'mock-meal-v1',
      'prompt_version': 'meal_v1',
      'overall_confidence': '0.82',
      'confidence_label': 'high',
      'warnings': ['请确认份量'],
      'error_code': null,
      'error_message': null,
      'reanalysis_count': 0,
      'confirmed_meal_id': null,
      'totals': {
        'calories': '403.0',
        'min_calories': '330.0',
        'max_calories': '500.0',
        'protein': '18.0',
        'carbs': '57.1',
        'fat': '10.1',
        'fiber': '3.0',
      },
      'items': [
        {
          'id': 'item-1',
          'detected_name': '米饭',
          'matched_food_id': 'rice',
          'matched_food_name': '米饭',
          'match_type': 'exact',
          'confidence_label': 'medium',
          'estimated_weight_g': '180',
          'min_weight_g': '140',
          'max_weight_g': '220',
          'calories': '234',
          'min_calories': '182',
          'max_calories': '286',
          'recognition_confidence': '0.95',
          'portion_confidence': '0.7',
          'match_confidence': '1',
          'portion_description': '一碗',
          'cooking_method': '蒸',
          'is_hidden_ingredient': false,
          'user_modified': false,
          'possible_hidden_ingredients': [],
        },
      ],
    });

    expect(model.editable, isTrue);
    expect(model.totals.center.calories, 403);
    expect(model.totals.maxCalories, 500);
    expect(model.items.single.weightG, 180);
    expect(model.items.single.confidenceLabel, 'medium');
  });
}
