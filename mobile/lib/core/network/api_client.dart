import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../features/dashboard/data/dashboard_model.dart';
import '../../features/nutrition/data/nutrition_models.dart';
import '../config/app_config.dart';
import 'api_exception.dart';

const _accessTokenKey = 'health_os_access_token';
const _refreshTokenKey = 'health_os_refresh_token';

final secureStorageProvider = Provider<FlutterSecureStorage>(
  (ref) => const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  ),
);

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    Dio(BaseOptions(baseUrl: AppConfig.apiBaseUrl)),
    ref.watch(secureStorageProvider),
  );
});

class ApiClient {
  ApiClient(this._dio, this._storage);

  final Dio _dio;
  final FlutterSecureStorage _storage;

  Future<bool> hasSession() async =>
      (await _storage.read(key: _accessTokenKey)) != null;

  Future<void> authenticate({
    required String email,
    required String password,
    required bool register,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/auth/${register ? 'register' : 'login'}',
        data: {'email': email, 'password': password},
      );
      final data = response.data!['data'] as Map<String, dynamic>;
      await _storage.write(
        key: _accessTokenKey,
        value: data['access_token'] as String,
      );
      await _storage.write(
        key: _refreshTokenKey,
        value: data['refresh_token'] as String,
      );
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<void> clearSession() => _storage.deleteAll();

  Future<DashboardModel> fetchDashboard() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/dashboard/today',
        options: await _authorizedOptions(),
      );
      return DashboardModel.fromJson(
        response.data!['data'] as Map<String, dynamic>,
      );
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<void> addWeight(double weightKg, DateTime measuredOn) async {
    try {
      await _dio.post<void>(
        '/weight',
        data: {
          'measured_on': measuredOn.toIso8601String().substring(0, 10),
          'weight_kg': weightKg,
          'source': 'manual',
        },
        options: await _authorizedOptions(),
      );
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<DailyNutritionModel> fetchDailyNutrition([DateTime? date]) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/nutrition/daily',
        queryParameters: date == null ? null : {'date': _date(date)},
        options: await _authorizedOptions(),
      );
      return DailyNutritionModel.fromJson(
        response.data!['data'] as Map<String, dynamic>,
      );
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<NutritionGoalModel?> fetchNutritionGoal([DateTime? date]) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/nutrition/goals/current',
        queryParameters: date == null ? null : {'date': _date(date)},
        options: await _authorizedOptions(),
      );
      return NutritionGoalModel.fromJson(
        response.data!['data'] as Map<String, dynamic>,
      );
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) return null;
      throw _mapError(error);
    }
  }

  Future<List<MealModel>> fetchMeals(DateTime date) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/meals',
        queryParameters: {'from': _date(date), 'to': _date(date)},
        options: await _authorizedOptions(),
      );
      return (response.data!['data'] as List<dynamic>)
          .map((item) => MealModel.fromJson(item as Map<String, dynamic>))
          .toList();
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<List<FoodModel>> searchFoods(
    String query, {
    String mode = 'search',
  }) async {
    try {
      final path = switch (mode) {
        'favorites' => '/foods/favorites',
        'recent' => '/foods/recent',
        _ => '/foods/search',
      };
      final response = await _dio.get<Map<String, dynamic>>(
        path,
        queryParameters: mode == 'search' ? {'q': query} : null,
        options: await _authorizedOptions(),
      );
      final values = response.data!['data'] as List<dynamic>;
      return values.map((item) {
        final map = item as Map<String, dynamic>;
        final food =
            mode == 'favorites' ? map['food'] as Map<String, dynamic> : map;
        return FoodModel.fromJson(food);
      }).toList();
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<void> setFavorite(String foodId, bool favorite) async {
    try {
      if (favorite) {
        await _dio.post<void>(
          '/foods/$foodId/favorite',
          options: await _authorizedOptions(),
        );
      } else {
        await _dio.delete<void>(
          '/foods/$foodId/favorite',
          options: await _authorizedOptions(),
        );
      }
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<MealModel> createMeal({
    required String mealType,
    required DateTime eatenAt,
    required String idempotencyKey,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/meals',
        data: {
          'meal_type': mealType,
          'eaten_at': eatenAt.toUtc().toIso8601String(),
          'source': 'manual',
        },
        options: await _authorizedOptions(idempotencyKey: idempotencyKey),
      );
      return MealModel.fromJson(response.data!['data'] as Map<String, dynamic>);
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<MealModel> addMealItem({
    required String mealId,
    required String foodId,
    required double amount,
    required String unit,
    required String idempotencyKey,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/meals/$mealId/items',
        data: {'food_id': foodId, 'amount': amount, 'amount_unit': unit},
        options: await _authorizedOptions(idempotencyKey: idempotencyKey),
      );
      return MealModel.fromJson(response.data!['data'] as Map<String, dynamic>);
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<MealModel> updateMealItem({
    required String mealId,
    required String itemId,
    required double amount,
    required String unit,
  }) async {
    try {
      final response = await _dio.patch<Map<String, dynamic>>(
        '/meals/$mealId/items/$itemId',
        data: {'amount': amount, 'amount_unit': unit},
        options: await _authorizedOptions(),
      );
      return MealModel.fromJson(response.data!['data'] as Map<String, dynamic>);
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<MealModel> deleteMealItem(String mealId, String itemId) async {
    try {
      final response = await _dio.delete<Map<String, dynamic>>(
        '/meals/$mealId/items/$itemId',
        options: await _authorizedOptions(),
      );
      return MealModel.fromJson(response.data!['data'] as Map<String, dynamic>);
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<Options> _authorizedOptions({String? idempotencyKey}) async {
    final token = await _storage.read(key: _accessTokenKey);
    return Options(
      headers: {
        'Authorization': 'Bearer $token',
        if (idempotencyKey != null) 'Idempotency-Key': idempotencyKey,
      },
    );
  }

  static String _date(DateTime value) =>
      value.toIso8601String().substring(0, 10);

  ApiException _mapError(DioException error) {
    final body = error.response?.data;
    if (body is Map<String, dynamic> && body['error'] is Map<String, dynamic>) {
      final details = body['error'] as Map<String, dynamic>;
      return ApiException(
        details['message']?.toString() ?? '请求失败',
        code: details['code']?.toString(),
      );
    }
    return const ApiException('无法连接服务器，请检查网络和 API 地址。');
  }
}
