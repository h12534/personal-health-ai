import 'package:personal_health_os/features/coach/data/coach_models.dart';
import 'package:personal_health_os/features/nutrition/data/meal_analysis_models.dart';
import 'package:personal_health_os/features/nutrition/data/nutrition_models.dart';
import 'package:personal_health_os/features/nutrition/presentation/nutrition_controller.dart';

final rolloutNutrition = NutritionViewState(
    daily: DailyNutritionModel(
        date: DateTime(2026, 9, 29),
        totals: const NutritionTotals(
            calories: 403, protein: 18, carbs: 57.1, fat: 10.1),
        meals: const {'breakfast': NutritionTotals(calories: 403, protein: 18)},
        mealCounts: const {'breakfast': 1}),
    meals: [
      MealModel(
          id: 'synthetic-meal',
          mealType: 'breakfast',
          eatenAt: DateTime(2026, 9, 29, 8),
          pending: true,
          totals: const NutritionTotals(calories: 403, protein: 18),
          items: const [
            MealItemModel(
                id: 'synthetic-item',
                foodId: 'synthetic-food',
                foodName: '米饭、鸡蛋与清炒时蔬（合成测试餐食）',
                amount: 1,
                unit: 'serving',
                nutrition: NutritionTotals(calories: 403, protein: 18)),
          ])
    ],
    goal: const NutritionGoalModel(calories: 2200, protein: 135, fiber: 25),
    offline: true,
    nextMeal: const NextMealPlanModel(
        mealType: 'lunch',
        target: MealTargetRangeModel(
            caloriesMin: 450, caloriesMax: 650, proteinMin: 30, proteinMax: 45),
        remainingCalories: 1500,
        remainingProtein: 110,
        strategy: [],
        overTarget: false,
        message: '按现有范围选择下一餐。'));
const rolloutDraftItem = MealAnalysisItemModel(
    id: 'synthetic-item',
    name: '米饭与鸡蛋',
    foodId: 'synthetic-food',
    foodName: '米饭与鸡蛋',
    matchType: 'manual',
    confidenceLabel: 'medium',
    weightG: 250,
    minWeightG: 200,
    maxWeightG: 300,
    calories: 403,
    minCalories: 320,
    maxCalories: 490,
    recognitionConfidence: .8,
    portionConfidence: .7,
    matchConfidence: 1,
    hiddenIngredient: false,
    userModified: true,
    hiddenIngredients: ['烹调用油']);
const rolloutDraft = MealAnalysisModel(
    id: 'synthetic-analysis',
    status: 'completed',
    provider: 'synthetic-test-provider',
    model: 'synthetic-test-model',
    promptVersion: 'synthetic',
    warnings: ['照片无法精确判断用油，请核对。'],
    items: [rolloutDraftItem],
    totals: MealAnalysisTotalsModel(
        center:
            NutritionTotals(calories: 403, protein: 18, carbs: 57.1, fat: 10.1),
        minCalories: 320,
        maxCalories: 490),
    reanalysisCount: 0);
