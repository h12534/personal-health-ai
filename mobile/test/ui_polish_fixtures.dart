import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:personal_health_os/core/database/local_database.dart';
import 'package:personal_health_os/core/network/api_client.dart';
import 'package:personal_health_os/core/network/api_exception.dart';
import 'package:personal_health_os/features/auth/presentation/auth_controller.dart';
import 'package:personal_health_os/features/nutrition/data/nutrition_models.dart';
import 'package:personal_health_os/features/nutrition/data/offline_meal_repository.dart';
import 'package:personal_health_os/features/nutrition/presentation/nutrition_controller.dart';
import 'ui_rollout_fixtures.dart';

// Synthetic, local-only UI evidence. No real credentials or health records.
const polishFood = FoodModel(
    id: 'synthetic-food',
    name: '米饭',
    category: 'grain',
    caloriesPer100g: 137,
    proteinPer100g: 2.6,
    carbsPer100g: 28,
    fatPer100g: 0.8,
    fiberPer100g: 0.3,
    isFavorite: false,
    servingUnit: 'serving',
    servingWeightG: 150,
    servingDescription: '一份约 150 克');

class _NoTokens implements TokenStore {
  @override
  Future<void> clear() async {}
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> write(String key, String value) async {}
}

class PolishApi extends ApiClient {
  PolishApi() : super(Dio(), _NoTokens());
  final pending = Completer<void>();
  int saves = 0;
  Map<String, Object?>? lastSave;
  @override
  Future<void> saveCanteen(
      {String? id,
      required String name,
      String? campus,
      String? location,
      String? note}) async {
    saves++;
    lastSave = {
      'id': id,
      'name': name,
      'campus': campus,
      'location': location,
      'note': note
    };
    await pending.future;
    throw StateError('private raw error');
  }
}

class PolishFoods extends OfflineMealRepository {
  PolishFoods(this.database) : super(database, PolishApi());
  final LocalDatabase database;
  @override
  Future<List<FoodModel>> searchFoods(String query,
          {String mode = 'search'}) async =>
      [polishFood];
  @override
  Future<void> setFavorite(FoodModel food, bool favorite) async {}
}

class PolishAuth extends AuthController {
  PolishAuth({this.startupFailure = false});
  final bool startupFailure;
  final pending = Completer<void>();
  int calls = 0;
  @override
  Future<AuthState> build() async {
    if (startupFailure) throw StateError('private raw startup error');
    return const AuthState(isAuthenticated: false);
  }

  @override
  Future<void> authenticate(
      {required String email,
      required String password,
      required bool register}) async {
    calls++;
    state = const AsyncLoading();
    await pending.future;
    state = AsyncError(
        const ApiException('private raw auth error',
            code: 'invalid_credentials'),
        StackTrace.current);
  }
}

class PolishNutrition extends NutritionController {
  final pending = Completer<void>();
  int calls = 0;
  double? savedAmount;
  String? savedUnit;
  @override
  Future<NutritionViewState> build() async => rolloutNutrition;
  @override
  Future<void> addFood(
      {required String mealType,
      required FoodModel food,
      required double amount,
      required String unit}) async {
    calls++;
    savedAmount = amount;
    savedUnit = unit;
    await pending.future;
    throw StateError('private raw food error');
  }
}
