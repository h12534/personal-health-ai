import 'package:flutter_test/flutter_test.dart';
import 'package:personal_health_os/features/nutrition/data/nutrition_models.dart';

void main() {
  test('portion calculator converts grams exactly', () {
    const rice = FoodModel(
      id: 'rice',
      name: '米饭',
      category: 'grain',
      caloriesPer100g: 130,
      proteinPer100g: 2.7,
      carbsPer100g: 28.2,
      fatPer100g: 0.3,
      fiberPer100g: 0.4,
      isFavorite: false,
    );

    final totals = rice.calculate(200, 'g');
    expect(totals.calories, 260);
    expect(totals.protein, 5.4);
    expect(totals.carbs, 56.4);
  });

  test('portion calculator converts configured piece weight', () {
    const egg = FoodModel(
      id: 'egg',
      name: '鸡蛋',
      category: 'egg',
      servingUnit: 'piece',
      servingWeightG: 50,
      caloriesPer100g: 143,
      proteinPer100g: 12.6,
      carbsPer100g: 0.7,
      fatPer100g: 9.5,
      fiberPer100g: 0,
      isFavorite: false,
    );

    final totals = egg.calculate(2, 'piece');
    expect(totals.calories, 143);
    expect(totals.protein, 12.6);
  });
}
