import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_health_os/features/nutrition/data/nutrition_models.dart';
import 'package:personal_health_os/features/nutrition/presentation/nutrition_controller.dart';
import 'package:personal_health_os/features/nutrition/presentation/nutrition_screen.dart';

void main() {
  testWidgets('nutrition screen shows totals, meals, and pending state', (
    tester,
  ) async {
    final state = NutritionViewState(
      daily: DailyNutritionModel(
        date: DateTime(2026, 9, 29),
        totals: const NutritionTotals(
          calories: 403,
          protein: 18,
          carbs: 57.1,
          fat: 10.1,
        ),
        meals: const {'breakfast': NutritionTotals(calories: 403, protein: 18)},
        mealCounts: const {'breakfast': 1},
      ),
      meals: [
        MealModel(
          id: 'local-meal',
          mealType: 'breakfast',
          eatenAt: DateTime(2026, 9, 29, 8),
          totals: const NutritionTotals(calories: 403, protein: 18),
          pending: true,
          items: const [
            MealItemModel(
              id: 'local-item',
              foodId: 'rice',
              foodName: '米饭和鸡蛋',
              amount: 1,
              unit: 'serving',
              nutrition: NutritionTotals(calories: 403, protein: 18),
            ),
          ],
        ),
      ],
      goal: const NutritionGoalModel(calories: 2200, protein: 135, fiber: 25),
      offline: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NutritionContent(
            data: state,
            onRefresh: () async {},
            onAddFood: (_) {},
            onEditItem: (_, __) {},
          ),
        ),
      ),
    );

    expect(find.text('今日营养'), findsOneWidget);
    expect(find.text('拍照识别一餐'), findsOneWidget);
    expect(find.textContaining('403 / 2200 kcal'), findsOneWidget);
    expect(find.textContaining('早餐 · 403 kcal'), findsOneWidget);
    expect(find.text('米饭和鸡蛋'), findsOneWidget);
    expect(find.text('离线模式'), findsOneWidget);
  });
}
