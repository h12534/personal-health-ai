import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/local_database.dart';
import '../../../core/network/api_client.dart';
import 'nutrition_models.dart';

final offlineMealRepositoryProvider = Provider<OfflineMealRepository>((ref) {
  return OfflineMealRepository(
    ref.watch(localDatabaseProvider),
    ref.watch(apiClientProvider),
  );
});

class OfflineMealRepository {
  OfflineMealRepository(this._database, this._api);

  final LocalDatabase _database;
  final ApiClient _api;
  final Uuid _uuid = const Uuid();

  Future<void> queueFood({
    required String mealType,
    required FoodModel food,
    required double amount,
    required String unit,
    DateTime? eatenAt,
  }) async {
    final timestamp = eatenAt ?? DateTime.now();
    final localDate = _date(timestamp);
    await _database.transaction(() async {
      var meal = await _database.pendingMeal(localDate, mealType);
      if (meal == null) {
        final mealId = _uuid.v4();
        meal = LocalMealRecord(
          localId: mealId,
          mealType: mealType,
          eatenAt: timestamp,
          localDate: localDate,
          syncStatus: 'pending',
          updatedAt: timestamp,
        );
        await _database.insertMeal(meal);
        await _database.enqueue(
          OutboxRecord(
            id: _uuid.v4(),
            aggregateType: 'meal',
            aggregateLocalId: mealId,
            operation: 'meal_create',
            payload: {
              'meal_type': mealType,
              'eaten_at': timestamp.toUtc().toIso8601String(),
            },
            idempotencyKey: 'mobile-meal-$mealId',
            createdAt: timestamp,
          ),
        );
      }

      final activeMeal = meal;
      if (activeMeal == null) throw StateError('Unable to create a local meal');
      final itemId = _uuid.v4();
      final nutrition = food.calculate(amount, unit);
      await _database.insertItem(
        LocalMealItemRecord(
          localId: itemId,
          mealLocalId: activeMeal.localId,
          foodId: food.id,
          foodName: food.name,
          amount: amount,
          unit: unit,
          nutrition: nutrition,
          syncStatus: 'pending',
          updatedAt: timestamp,
        ),
      );
      await _database.enqueue(
        OutboxRecord(
          id: _uuid.v4(),
          aggregateType: 'meal_item',
          aggregateLocalId: itemId,
          operation: 'meal_item_create',
          payload: {
            'meal_local_id': activeMeal.localId,
            'food_id': food.id,
            'amount': amount,
            'amount_unit': unit,
          },
          idempotencyKey: 'mobile-item-$itemId',
          createdAt: timestamp.add(const Duration(milliseconds: 1)),
        ),
      );
    });
  }

  Future<List<FoodModel>> searchFoods(
    String query, {
    String mode = 'search',
  }) async {
    try {
      final foods = await _api.searchFoods(query, mode: mode);
      await _database.cacheFoods(foods);
      return foods;
    } on Object {
      return _database.searchCachedFoods(query);
    }
  }

  Future<void> setFavorite(FoodModel food, bool favorite) async {
    await _api.setFavorite(food.id, favorite);
  }

  Future<List<MealModel>> pendingMeals(DateTime date) {
    return _database.pendingMealsForDate(_date(date));
  }

  Future<void> updatePendingItem(String localId, double amount) {
    return _database.updatePendingItem(localId, amount);
  }

  Future<void> deletePendingItem(String localId) {
    return _database.deletePendingItem(localId);
  }

  static String _date(DateTime value) =>
      value.toIso8601String().substring(0, 10);
}
