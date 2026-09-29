import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../dashboard/presentation/dashboard_controller.dart';
import '../data/nutrition_models.dart';
import '../data/offline_meal_repository.dart';
import '../data/sync_service.dart';

final nutritionControllerProvider =
    AsyncNotifierProvider<NutritionController, NutritionViewState>(
  NutritionController.new,
);

class NutritionViewState {
  const NutritionViewState({
    required this.daily,
    required this.meals,
    required this.goal,
    required this.offline,
  });

  final DailyNutritionModel daily;
  final List<MealModel> meals;
  final NutritionGoalModel? goal;
  final bool offline;
}

class NutritionController extends AsyncNotifier<NutritionViewState> {
  @override
  Future<NutritionViewState> build() => _load();

  Future<NutritionViewState> _load() async {
    final date = DateTime.now();
    final repository = ref.read(offlineMealRepositoryProvider);
    await ref.read(syncServiceProvider).syncPending();
    final pending = await repository.pendingMeals(date);
    try {
      final api = ref.read(apiClientProvider);
      final daily = await api.fetchDailyNutrition(date);
      final meals = await api.fetchMeals(date);
      final goal = await api.fetchNutritionGoal(date);
      return NutritionViewState(
        daily: _mergePending(daily, pending),
        meals: [...meals, ...pending],
        goal: goal,
        offline: false,
      );
    } on Object {
      return NutritionViewState(
        daily: _fromPending(date, pending),
        meals: pending,
        goal: null,
        offline: true,
      );
    }
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_load);
  }

  Future<void> addFood({
    required String mealType,
    required FoodModel food,
    required double amount,
    required String unit,
  }) async {
    await ref
        .read(offlineMealRepositoryProvider)
        .queueFood(mealType: mealType, food: food, amount: amount, unit: unit);
    await ref.read(syncServiceProvider).syncPending();
    ref.invalidate(dashboardProvider);
    await refresh();
  }

  Future<void> updateItem(
    MealModel meal,
    MealItemModel item,
    double amount,
  ) async {
    if (meal.pending) {
      await ref
          .read(offlineMealRepositoryProvider)
          .updatePendingItem(item.id, amount);
    } else {
      await ref.read(apiClientProvider).updateMealItem(
            mealId: meal.id,
            itemId: item.id,
            amount: amount,
            unit: item.unit,
          );
    }
    ref.invalidate(dashboardProvider);
    await refresh();
  }

  Future<void> deleteItem(MealModel meal, MealItemModel item) async {
    if (meal.pending) {
      await ref.read(offlineMealRepositoryProvider).deletePendingItem(item.id);
    } else {
      await ref.read(apiClientProvider).deleteMealItem(meal.id, item.id);
    }
    ref.invalidate(dashboardProvider);
    await refresh();
  }

  static DailyNutritionModel _mergePending(
    DailyNutritionModel remote,
    List<MealModel> pending,
  ) {
    if (pending.isEmpty) return remote;
    final local = _fromPending(remote.date, pending);
    final meals = <String, NutritionTotals>{...remote.meals};
    final counts = <String, int>{...remote.mealCounts};
    for (final entry in local.meals.entries) {
      meals[entry.key] = _add(
        meals[entry.key] ?? const NutritionTotals(),
        entry.value,
      );
      counts[entry.key] =
          (counts[entry.key] ?? 0) + (local.mealCounts[entry.key] ?? 0);
    }
    return DailyNutritionModel(
      date: remote.date,
      totals: _add(remote.totals, local.totals),
      meals: meals,
      mealCounts: counts,
    );
  }

  static DailyNutritionModel _fromPending(
    DateTime date,
    List<MealModel> meals,
  ) {
    final breakdown = <String, NutritionTotals>{
      'breakfast': const NutritionTotals(),
      'lunch': const NutritionTotals(),
      'dinner': const NutritionTotals(),
      'snack': const NutritionTotals(),
    };
    final counts = <String, int>{
      'breakfast': 0,
      'lunch': 0,
      'dinner': 0,
      'snack': 0,
    };
    var totals = const NutritionTotals();
    for (final meal in meals) {
      breakdown[meal.mealType] = _add(
        breakdown[meal.mealType] ?? const NutritionTotals(),
        meal.totals,
      );
      counts[meal.mealType] = (counts[meal.mealType] ?? 0) + 1;
      totals = _add(totals, meal.totals);
    }
    return DailyNutritionModel(
      date: date,
      totals: totals,
      meals: breakdown,
      mealCounts: counts,
    );
  }

  static NutritionTotals _add(NutritionTotals left, NutritionTotals right) =>
      NutritionTotals(
        calories: left.calories + right.calories,
        protein: left.protein + right.protein,
        carbs: left.carbs + right.carbs,
        fat: left.fat + right.fat,
        fiber: left.fiber + right.fiber,
      );
}
