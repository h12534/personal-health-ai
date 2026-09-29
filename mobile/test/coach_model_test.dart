import 'package:flutter_test/flutter_test.dart';
import 'package:personal_health_os/features/coach/data/coach_models.dart';

void main() {
  test('coach reply and next meal parse Decimal strings and actions', () {
    final plan = NextMealPlanModel.fromJson({
      'meal_type': 'lunch',
      'target': {
        'calories_min': 450,
        'calories_max': 650,
        'protein_min_g': '30.0',
        'protein_max_g': '45.0',
      },
      'remaining_calories': 1200,
      'remaining_protein_g': '80.5',
      'strategy': ['优先蛋白质'],
      'over_target': false,
      'message': '按范围选择',
    });
    final reply = CoachReplyModel.fromJson({
      'conversation_id': 'conversation-1',
      'intent': 'canteen_choice',
      'message': '可以这样选',
      'suggested_actions': [
        {'type': 'open_canteen', 'label': '查看食堂', 'target_id': null},
      ],
      'safety_notice': null,
      'provider': 'mock',
    });

    expect(plan.mealLabel, '午餐');
    expect(plan.target.proteinMin, 30);
    expect(reply.actions.single.type, 'open_canteen');
  });

  test('canteen tree and saved meal totals parse nested API payloads', () {
    final canteen = CanteenModel.fromJson({
      'id': 'canteen-1',
      'name': '第一食堂',
      'stalls': [
        {
          'id': 'stall-1',
          'canteen_id': 'canteen-1',
          'name': '家常菜',
          'dishes': [
            {
              'id': 'dish-1',
              'stall_id': 'stall-1',
              'name': '鸡腿饭',
              'calories': '560.0',
              'protein_g': '38.0',
              'carbs_g': '65.0',
              'fat_g': '16.0',
              'fiber_g': '6.0',
              'confidence': '0.8',
              'favorite': true,
              'source': 'confirmed_meal',
            },
          ],
        },
      ],
    });
    final saved = SavedMealModel.fromJson({
      'id': 'saved-1',
      'name': '早餐 A',
      'meal_type': 'breakfast',
      'items': [
        {'calories': '210.5'},
        {'calories': 120},
      ],
    });

    expect(canteen.stalls.single.dishes.single.favorite, isTrue);
    expect(saved.itemCount, 2);
    expect(saved.totalCalories, 330.5);
  });
}
