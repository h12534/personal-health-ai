import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http_parser/http_parser.dart';
import 'package:uuid/uuid.dart';

import '../../features/dashboard/data/dashboard_model.dart';
import '../../features/coach/data/coach_models.dart';
import '../../features/health/data/health_models.dart';
import '../../features/nutrition/data/nutrition_models.dart';
import '../../features/nutrition/data/meal_analysis_models.dart';
import '../../features/training/data/training_models.dart';
import '../../features/supervision/data/supervision_models.dart';
import '../config/app_config.dart';
import '../diagnostics/local_diagnostics.dart';
import 'api_exception.dart';

const _accessTokenKey = 'health_os_access_token';
const _refreshTokenKey = 'health_os_refresh_token';

abstract interface class TokenStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> clear();
}

class SecureTokenStore implements TokenStore {
  const SecureTokenStore(this._storage);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> clear() => _storage.deleteAll();
}

final secureStorageProvider = Provider<FlutterSecureStorage>(
  (ref) => const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  ),
);

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    Dio(BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 20),
    )),
    SecureTokenStore(ref.watch(secureStorageProvider)),
  );
});

class ApiClient {
  ApiClient(this._dio, this._tokens,
      {LocalDiagnosticsLog? diagnostics, bool? remotePushEnabled})
      : _diagnostics = diagnostics ?? localDiagnostics,
        _remotePushEnabled =
            AppConfig.remotePushEnabled && (remotePushEnabled ?? true) {
    _installDiagnostics(_dio);
    _dio.interceptors.add(
      InterceptorsWrapper(onError: _handleUnauthorized),
    );
  }

  final Dio _dio;
  final TokenStore _tokens;
  final LocalDiagnosticsLog _diagnostics;
  final bool _remotePushEnabled;
  String? _lastRequestId;
  Future<String?>? _refreshInFlight;

  String get apiHost => Uri.parse(_dio.options.baseUrl).host;
  String? get lastRequestId => _lastRequestId;

  void _installDiagnostics(Dio client) {
    client.interceptors.add(InterceptorsWrapper(
      onRequest: (request, handler) {
        final id = const Uuid().v4();
        request.headers['X-Request-ID'] = id;
        request.extra['diagnosticRequestId'] = id;
        request.extra['diagnosticTimer'] = Stopwatch()..start();
        handler.next(request);
      },
      onResponse: (response, handler) {
        _recordRequest(response.requestOptions, response.statusCode, 'http');
        handler.next(response);
      },
      onError: (error, handler) {
        _recordRequest(
          error.requestOptions,
          error.response?.statusCode,
          error.type.name,
        );
        handler.next(error);
      },
    ));
  }

  void _recordRequest(RequestOptions request, int? status, String code) {
    final timer = request.extra['diagnosticTimer'];
    if (timer is Stopwatch) timer.stop();
    final id = request.extra['diagnosticRequestId'] as String?;
    _lastRequestId = id;
    unawaited(_diagnostics.record(
      event: 'http_completed',
      source: 'api',
      code: code,
      requestId: id,
      statusCode: status,
      durationMs: timer is Stopwatch ? timer.elapsedMilliseconds : null,
    ));
  }

  Future<Map<String, String>> fetchBetaProviderStatus() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/profile/beta-status',
      options: await _authorizedOptions(),
    );
    final data = response.data?['data'];
    if (data is! Map<String, dynamic>) return const {};
    const names = {
      'coach',
      'vision',
      'embedding',
      'lab_ocr',
      'health_answer',
      'push'
    };
    const statuses = {'mock', 'disabled', 'configured_not_verified', 'unknown'};
    return {
      for (final name in names)
        if (data.containsKey(name))
          name:
              statuses.contains(data[name]) ? data[name] as String : 'unknown',
    };
  }

  Future<bool> hasSession() async =>
      (await _tokens.read(_accessTokenKey)) != null;

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
      await _tokens.write(_accessTokenKey, data['access_token'] as String);
      await _tokens.write(_refreshTokenKey, data['refresh_token'] as String);
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<void> clearSession() => _tokens.clear();

  Future<ServerHealthResult> checkServerHealth() async {
    final stopwatch = Stopwatch()..start();
    final base = Uri.parse(_dio.options.baseUrl);
    final healthUri =
        base.replace(path: '/health/live', query: null, fragment: null);
    try {
      final response = await _dio.getUri<void>(healthUri);
      stopwatch.stop();
      return ServerHealthResult(
        checkedAt: DateTime.now().toUtc(),
        latencyMs: stopwatch.elapsedMilliseconds,
        healthy: response.statusCode == 200,
      );
    } on DioException catch (error) {
      stopwatch.stop();
      return ServerHealthResult(
        checkedAt: DateTime.now().toUtc(),
        latencyMs: stopwatch.elapsedMilliseconds,
        healthy: false,
        errorCode: error.type.name,
      );
    }
  }

  Future<void> registerPushDevice({
    required String deviceId,
    required String platform,
    required String token,
  }) async {
    if (!_remotePushEnabled) return;
    try {
      await _dio.put<void>(
        '/supervision/push-device',
        data: {
          'device_id': deviceId,
          'platform': platform,
          'environment': AppConfig.apiEnvironment,
          'token': token,
        },
        options: await _authorizedOptions(),
      );
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<VisionPrivacySettings> fetchVisionPrivacy() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/profile',
        options: await _authorizedOptions(),
      );
      final data = response.data!['data'] as Map<String, dynamic>;
      return VisionPrivacySettings(
        allowThirdParty: data['allow_third_party_vision'] as bool? ?? false,
        retainImages: data['retain_meal_images'] as bool? ?? false,
      );
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) {
        return const VisionPrivacySettings();
      }
      throw _mapError(error);
    }
  }

  Future<VisionPrivacySettings> updateVisionPrivacy(
    VisionPrivacySettings settings,
  ) async {
    try {
      final response = await _dio.patch<Map<String, dynamic>>(
        '/profile/privacy/meal-vision',
        data: {
          'allow_third_party_vision': settings.allowThirdParty,
          'retain_meal_images': settings.retainImages,
        },
        options: await _authorizedOptions(),
      );
      final data = response.data!['data'] as Map<String, dynamic>;
      return VisionPrivacySettings(
        allowThirdParty: data['allow_third_party_vision'] as bool,
        retainImages: data['retain_meal_images'] as bool,
      );
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

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

  Future<MealAnalysisModel> analyzeMealImage({
    required String imagePath,
    required String mealType,
    required String idempotencyKey,
    String locationContext = 'school_canteen',
    void Function(int sent, int total)? onSendProgress,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/meals/analyze-image',
        data: FormData.fromMap({
          'image': await MultipartFile.fromFile(
            imagePath,
            filename: 'meal.jpg',
            contentType: MediaType('image', 'jpeg'),
          ),
          'meal_type': mealType,
          'location_context': locationContext,
        }),
        options: await _authorizedOptions(idempotencyKey: idempotencyKey),
        onSendProgress: onSendProgress,
      );
      return MealAnalysisModel.fromJson(
        response.data!['data'] as Map<String, dynamic>,
      );
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<MealAnalysisModel> fetchMealAnalysis(String analysisId) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/meals/analyses/$analysisId',
        options: await _authorizedOptions(),
      );
      return MealAnalysisModel.fromJson(
        response.data!['data'] as Map<String, dynamic>,
      );
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<MealAnalysisModel> updateMealAnalysisItem({
    required String analysisId,
    required String itemId,
    double? weightG,
    double? minWeightG,
    double? maxWeightG,
    String? foodId,
  }) async {
    try {
      final response = await _dio.patch<Map<String, dynamic>>(
        '/meals/analyses/$analysisId/items/$itemId',
        data: {
          if (weightG != null) 'estimated_weight_g': weightG,
          if (minWeightG != null) 'min_weight_g': minWeightG,
          if (maxWeightG != null) 'max_weight_g': maxWeightG,
          if (foodId != null) 'matched_food_id': foodId,
        },
        options: await _authorizedOptions(),
      );
      return MealAnalysisModel.fromJson(
        response.data!['data'] as Map<String, dynamic>,
      );
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<MealAnalysisModel> addMealAnalysisItem({
    required String analysisId,
    required String foodId,
    required String name,
    required double weightG,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/meals/analyses/$analysisId/items',
        data: {
          'food_id': foodId,
          'detected_name': name,
          'estimated_weight_g': weightG,
        },
        options: await _authorizedOptions(),
      );
      return MealAnalysisModel.fromJson(
        response.data!['data'] as Map<String, dynamic>,
      );
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<MealAnalysisModel> deleteMealAnalysisItem(
    String analysisId,
    String itemId,
  ) async {
    try {
      final response = await _dio.delete<Map<String, dynamic>>(
        '/meals/analyses/$analysisId/items/$itemId',
        options: await _authorizedOptions(),
      );
      return MealAnalysisModel.fromJson(
        response.data!['data'] as Map<String, dynamic>,
      );
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<MealAnalysisModel> reanalyzeMeal(String analysisId) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/meals/analyses/$analysisId/reanalyze',
        options: await _authorizedOptions(),
      );
      return MealAnalysisModel.fromJson(
        response.data!['data'] as Map<String, dynamic>,
      );
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<MealModel> confirmMealAnalysis({
    required String analysisId,
    required String mealType,
    required DateTime eatenAt,
    required String idempotencyKey,
    String? note,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/meals/analyses/$analysisId/confirm',
        data: {
          'meal_type': mealType,
          'eaten_at': eatenAt.toIso8601String(),
          'note': note,
        },
        options: await _authorizedOptions(idempotencyKey: idempotencyKey),
      );
      return MealModel.fromJson(response.data!['data'] as Map<String, dynamic>);
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<NextMealPlanModel> fetchNextMeal() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/diet/next-meal',
        options: await _authorizedOptions(),
      );
      return NextMealPlanModel.fromJson(
        response.data!['data'] as Map<String, dynamic>,
      );
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<CoachOverviewModel> fetchCoachOverview() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/diet/weekly-review',
        options: await _authorizedOptions(),
      );
      return CoachOverviewModel.fromJson(
        response.data!['data'] as Map<String, dynamic>,
      );
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<CoachReplyModel> sendCoachMessage(
    String message, {
    String? conversationId,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/ai/coach/chat',
        data: {
          'message': message,
          if (conversationId != null) 'conversation_id': conversationId,
        },
        options: await _authorizedOptions(),
      );
      return CoachReplyModel.fromJson(
        response.data!['data'] as Map<String, dynamic>,
      );
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<void> decideDietAdjustment(String id, bool accept) async {
    try {
      await _dio.post<void>(
        '/diet/adjustments/$id/${accept ? 'accept' : 'decline'}',
        data: {'idempotency_key': 'mobile-$id-${accept ? 'yes' : 'no'}'},
        options: await _authorizedOptions(),
      );
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<List<CanteenRecommendationModel>> fetchCanteenRecommendations() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/canteens/recommendations',
        options: await _authorizedOptions(),
      );
      return (response.data!['data'] as List<dynamic>)
          .map(
            (value) => CanteenRecommendationModel.fromJson(
              value as Map<String, dynamic>,
            ),
          )
          .toList();
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<WeightTrendModel> fetchWeightTrend() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/diet/weight-trend',
        options: await _authorizedOptions(),
      );
      return WeightTrendModel.fromJson(
        response.data!['data'] as Map<String, dynamic>,
      );
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<List<CanteenModel>> fetchCanteens() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/canteens',
        options: await _authorizedOptions(),
      );
      return (response.data!['data'] as List<dynamic>)
          .map(
            (value) => CanteenModel.fromJson(value as Map<String, dynamic>),
          )
          .toList();
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<void> saveCanteen({
    String? id,
    required String name,
    String? campus,
    String? location,
    String? note,
  }) async {
    final data = {
      'name': name,
      'campus': campus,
      'location': location,
      'note': note,
    };
    try {
      if (id == null) {
        await _dio.post<void>(
          '/canteens',
          data: data,
          options: await _authorizedOptions(),
        );
      } else {
        await _dio.patch<void>(
          '/canteens/$id',
          data: data,
          options: await _authorizedOptions(),
        );
      }
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<void> saveCanteenStall({
    String? id,
    required String canteenId,
    required String name,
    String? cuisine,
    String? floor,
    String? locationNote,
  }) async {
    final data = {
      'name': name,
      'cuisine': cuisine,
      'floor': floor,
      'location_note': locationNote,
    };
    try {
      if (id == null) {
        await _dio.post<void>(
          '/canteens/$canteenId/stalls',
          data: data,
          options: await _authorizedOptions(),
        );
      } else {
        await _dio.patch<void>(
          '/canteens/stalls/$id',
          data: data,
          options: await _authorizedOptions(),
        );
      }
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<void> saveCanteenDish({
    String? id,
    required String stallId,
    required String name,
    required double calories,
    required double protein,
    required double carbs,
    required double fat,
    required double fiber,
    String? portionDescription,
    double? averageWeight,
    double confidence = 0.5,
    bool favorite = false,
    String source = 'manual',
  }) async {
    final data = {
      'name': name,
      'calories': calories,
      'protein_g': protein,
      'carbs_g': carbs,
      'fat_g': fat,
      'fiber_g': fiber,
      'portion_description': portionDescription,
      'average_weight_g': averageWeight,
      'confidence': confidence,
      'favorite': favorite,
      'source': source,
      'tags': <String>[],
    };
    try {
      if (id == null) {
        await _dio.post<void>(
          '/canteens/stalls/$stallId/dishes',
          data: data,
          options: await _authorizedOptions(),
        );
      } else {
        await _dio.patch<void>(
          '/canteens/dishes/$id',
          data: data,
          options: await _authorizedOptions(),
        );
      }
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<List<SavedMealModel>> fetchSavedMeals() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/saved-meals',
        options: await _authorizedOptions(),
      );
      return (response.data!['data'] as List<dynamic>)
          .map(
            (value) => SavedMealModel.fromJson(value as Map<String, dynamic>),
          )
          .toList();
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<void> logSavedMeal(SavedMealModel value) async {
    try {
      await _dio.post<void>(
        '/saved-meals/${value.id}/log',
        data: {
          'eaten_at': DateTime.now().toIso8601String(),
          'meal_type': value.mealType,
          'idempotency_key':
              'mobile-${value.id}-${DateTime.now().microsecondsSinceEpoch}',
        },
        options: await _authorizedOptions(),
      );
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<void> logHunger({
    required int hungerLevel,
    required int cravingLevel,
    required String context,
    String? note,
  }) async {
    try {
      await _dio.post<void>(
        '/diet/hunger',
        data: {
          'hunger_level': hungerLevel,
          'craving_level': cravingLevel,
          'context': context,
          'note': note,
        },
        options: await _authorizedOptions(),
      );
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<List<ExerciseModel>> fetchExercises([String? query]) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        query == null || query.isEmpty ? '/exercises' : '/exercises/search',
        queryParameters: query == null || query.isEmpty ? null : {'q': query},
        options: await _authorizedOptions(),
      );
      return (response.data!['data'] as List<dynamic>)
          .map(
            (value) => ExerciseModel.fromJson(value as Map<String, dynamic>),
          )
          .toList();
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<List<TrainingPlanModel>> fetchTrainingPlans() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/training/plans',
        options: await _authorizedOptions(),
      );
      return (response.data!['data'] as List<dynamic>)
          .map(
            (value) =>
                TrainingPlanModel.fromJson(value as Map<String, dynamic>),
          )
          .toList();
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<TrainingPlanModel> generateDefaultTrainingPlan() async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/training/plans/generate',
        data: {
          'goal': 'fat_loss_muscle_retention',
          'experience': 'beginner',
          'days_per_week': 3,
          'equipment': ['machine', 'dumbbell', 'cable', 'bodyweight'],
          'session_duration_min': 60,
          'limitations': <String>[],
          'preferences': <String>[],
          'weeks': 8,
        },
        options: await _authorizedOptions(),
      );
      return TrainingPlanModel.fromJson(
        response.data!['data'] as Map<String, dynamic>,
      );
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<List<WorkoutModel>> fetchWorkouts() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/workouts',
        options: await _authorizedOptions(),
      );
      return (response.data!['data'] as List<dynamic>)
          .map(
            (value) => WorkoutModel.fromJson(value as Map<String, dynamic>),
          )
          .toList();
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<WorkoutModel> createWorkout({
    required String id,
    required String? trainingDayId,
    required DateTime startedAt,
    required String idempotencyKey,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/workouts',
        data: {
          'id': id,
          'training_day_id': trainingDayId,
          'started_at': startedAt.toUtc().toIso8601String(),
          'source': 'mobile_offline',
          'idempotency_key': idempotencyKey,
        },
        options: await _authorizedOptions(idempotencyKey: idempotencyKey),
      );
      return WorkoutModel.fromJson(
        response.data!['data'] as Map<String, dynamic>,
      );
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<WorkoutSetModel> createWorkoutSet({
    required String workoutId,
    required String id,
    required String exerciseId,
    required int setNumber,
    required String setType,
    required double weightKg,
    required int reps,
    required double rir,
    required int restSeconds,
    required String idempotencyKey,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/workouts/$workoutId/sets',
        data: {
          'id': id,
          'exercise_id': exerciseId,
          'set_number': setNumber,
          'set_type': setType,
          'weight_kg': weightKg,
          'reps': reps,
          'rir': rir,
          'completed': true,
          'rest_seconds': restSeconds,
          'idempotency_key': idempotencyKey,
        },
        options: await _authorizedOptions(idempotencyKey: idempotencyKey),
      );
      return WorkoutSetModel.fromJson(
        response.data!['data'] as Map<String, dynamic>,
      );
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<void> completeWorkout({
    required String workoutId,
    required DateTime endedAt,
    double? sessionRpe,
  }) async {
    try {
      await _dio.post<void>(
        '/workouts/$workoutId/complete',
        data: {
          'ended_at': endedAt.toUtc().toIso8601String(),
          'session_rpe': sessionRpe,
        },
        options: await _authorizedOptions(),
      );
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<List<PersonalRecordModel>> fetchPersonalRecords() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/training/prs',
        options: await _authorizedOptions(),
      );
      return (response.data!['data'] as List<dynamic>)
          .map(
            (value) => PersonalRecordModel.fromJson(
              value as Map<String, dynamic>,
            ),
          )
          .toList();
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<TrainingCoachReply> sendTrainingCoachMessage(String message) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/ai/training/chat',
        data: {'message': message},
        options: await _authorizedOptions(),
      );
      return TrainingCoachReply.fromJson(
        response.data!['data'] as Map<String, dynamic>,
      );
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<void> applyTrainingProgression({
    required String exerciseId,
    required double suggestedWeightKg,
    required String reason,
    required String idempotencyKey,
    required Map<String, dynamic> evidenceSnapshot,
  }) async {
    try {
      await _dio.post<void>(
        '/training/adjustments/apply',
        data: {
          'exercise_id': exerciseId,
          'suggested_weight_kg': suggestedWeightKg,
          'reason': reason,
          'idempotency_key': idempotencyKey,
          'evidence_snapshot': evidenceSnapshot,
        },
        options: await _authorizedOptions(idempotencyKey: idempotencyKey),
      );
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<List<LabReportModel>> fetchLabReports() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/labs/reports',
        options: await _authorizedOptions(),
      );
      return (response.data!['data'] as List<dynamic>)
          .map((item) => LabReportModel.fromJson(item as Map<String, dynamic>))
          .toList();
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<LabReportModel> uploadLabReport({
    required Uint8List bytes,
    required String filename,
    required String contentType,
    required DateTime reportDate,
    required String sourceType,
    String? hospitalName,
    bool retainOriginal = true,
    bool allowRemoteOcr = false,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/labs/reports',
        data: FormData.fromMap({
          'file': MultipartFile.fromBytes(
            bytes,
            filename: filename,
            contentType: MediaType.parse(contentType),
          ),
          'report_date': _date(reportDate),
          'hospital_name': hospitalName,
          'source_type': sourceType,
          'retain_original': retainOriginal,
          'allow_remote_ocr': allowRemoteOcr,
        }),
        options: await _authorizedOptions(),
      );
      return LabReportModel.fromJson(
        response.data!['data'] as Map<String, dynamic>,
      );
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<LabReportModel> updateLabDraftItem({
    required String reportId,
    required String itemId,
    required String testName,
    required String normalizedName,
    double? value,
    String? valueText,
    String? unit,
    double? referenceMin,
    double? referenceMax,
    String? referenceText,
  }) async {
    try {
      final response = await _dio.patch<Map<String, dynamic>>(
        '/labs/reports/$reportId/draft-items/$itemId',
        data: {
          'test_name': testName,
          'normalized_name': normalizedName,
          'value_numeric': value,
          'value_text': valueText,
          'unit': unit,
          'reference_min': referenceMin,
          'reference_max': referenceMax,
          'reference_text': referenceText,
        },
        options: await _authorizedOptions(),
      );
      return LabReportModel.fromJson(
        response.data!['data'] as Map<String, dynamic>,
      );
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<LabReportModel> confirmLabReport(
    String reportId, {
    List<String>? itemIds,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/labs/reports/$reportId/confirm',
        data: {if (itemIds != null) 'item_ids': itemIds},
        options: await _authorizedOptions(),
      );
      return LabReportModel.fromJson(
        response.data!['data'] as Map<String, dynamic>,
      );
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<void> deleteLabReport(String reportId) async {
    try {
      await _dio.delete<void>(
        '/labs/reports/$reportId',
        options: await _authorizedOptions(),
      );
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<LabTrendModel> fetchLabTrend(String normalizedName) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/labs/trends/$normalizedName',
        options: await _authorizedOptions(),
      );
      return LabTrendModel.fromJson(
        response.data!['data'] as Map<String, dynamic>,
      );
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<List<HealthEvidenceModel>> searchHealthKnowledge(String query) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/knowledge/search',
        data: {'query': query, 'limit': 8},
        options: await _authorizedOptions(),
      );
      final payload = response.data!['data'] as Map<String, dynamic>;
      return (payload['evidence'] as List<dynamic>? ?? const [])
          .map((item) =>
              HealthEvidenceModel.fromJson(item as Map<String, dynamic>))
          .toList();
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<HealthChatReplyModel> sendHealthMessage(
    String message, {
    String? conversationId,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/ai/health/chat',
        data: {
          'message': message,
          if (conversationId != null) 'conversation_id': conversationId,
        },
        options: await _authorizedOptions(),
      );
      return HealthChatReplyModel.fromJson(
        response.data!['data'] as Map<String, dynamic>,
      );
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<List<HealthPermissionModel>> fetchHealthPermissions() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/health/permissions',
        options: await _authorizedOptions(),
      );
      return (response.data!['data'] as List<dynamic>)
          .map(
            (value) => HealthPermissionModel.fromJson(
              value as Map<String, dynamic>,
            ),
          )
          .toList();
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<HealthPermissionModel> setHealthPermission({
    required String dataType,
    required bool enabled,
    required String authorizationStatus,
  }) async {
    try {
      final response = await _dio.put<Map<String, dynamic>>(
        '/health/permissions',
        data: {
          'data_type': dataType,
          'enabled': enabled,
          'authorization_status': authorizationStatus,
        },
        options: await _authorizedOptions(),
      );
      return HealthPermissionModel.fromJson(
        response.data!['data'] as Map<String, dynamic>,
      );
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<void> uploadHealthSummary(Map<String, dynamic> summary) async {
    try {
      await _dio.post<void>(
        '/health/sync/summary',
        data: summary,
        options: await _authorizedOptions(),
      );
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<List<Map<String, dynamic>>> fetchHealthSyncStatus() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/health/sync/status',
        options: await _authorizedOptions(),
      );
      return (response.data!['data'] as List<dynamic>)
          .map(
            (item) => Map<String, dynamic>.from(
              item as Map<String, dynamic>,
            ),
          )
          .toList();
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<List<DailyTaskModel>> fetchDailyTasks([DateTime? date]) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/supervision/tasks',
        queryParameters: date == null ? null : {'date': _date(date)},
        options: await _authorizedOptions(),
      );
      return (response.data!['data'] as List<dynamic>)
          .map(
            (item) => DailyTaskModel.fromJson(
              item as Map<String, dynamic>,
            ),
          )
          .toList();
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<DailyTaskModel> updateDailyTask(
    String taskId,
    String status,
  ) async {
    try {
      final response = await _dio.patch<Map<String, dynamic>>(
        '/supervision/tasks/$taskId',
        data: {'status': status},
        options: await _authorizedOptions(),
      );
      return DailyTaskModel.fromJson(
        response.data!['data'] as Map<String, dynamic>,
      );
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<ReminderPreferencesModel> fetchReminderPreferences() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/supervision/preferences',
        options: await _authorizedOptions(),
      );
      return ReminderPreferencesModel.fromJson(
        response.data!['data'] as Map<String, dynamic>,
      );
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<ReminderPreferencesModel> updateReminderPreferences(
    ReminderPreferencesModel preferences,
  ) async {
    try {
      final response = await _dio.put<Map<String, dynamic>>(
        '/supervision/preferences',
        data: preferences.toJson(),
        options: await _authorizedOptions(),
      );
      return ReminderPreferencesModel.fromJson(
        response.data!['data'] as Map<String, dynamic>,
      );
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<List<HealthReportModel>> fetchHealthReports(String reportType) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/supervision/reports',
        queryParameters: {'report_type': reportType},
        options: await _authorizedOptions(),
      );
      return (response.data!['data'] as List<dynamic>)
          .map(
            (item) => HealthReportModel.fromJson(
              item as Map<String, dynamic>,
            ),
          )
          .toList();
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<HealthReportModel> generateHealthReport(
    String reportType, {
    bool force = false,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/supervision/reports/generate',
        data: {'report_type': reportType, 'force': force},
        options: await _authorizedOptions(),
      );
      return HealthReportModel.fromJson(
        response.data!['data'] as Map<String, dynamic>,
      );
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<List<TimelineEventModel>> fetchHealthTimeline(
    DateTime from,
    DateTime to,
    String category,
  ) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/supervision/timeline',
        queryParameters: {
          'from': _date(from),
          'to': _date(to),
          'category': category,
        },
        options: await _authorizedOptions(),
      );
      return (response.data!['data'] as List<dynamic>)
          .map(
            (item) => TimelineEventModel.fromJson(
              item as Map<String, dynamic>,
            ),
          )
          .toList();
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<CrossDomainModel> fetchCrossDomainTrends(
    DateTime from,
    DateTime to,
    List<String> metrics,
  ) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/supervision/cross-domain',
        queryParameters: {
          'from': _date(from),
          'to': _date(to),
          'metrics': metrics,
        },
        options: await _authorizedOptions(),
      );
      return CrossDomainModel.fromJson(
        response.data!['data'] as Map<String, dynamic>,
      );
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<List<HealthFollowupModel>> fetchHealthFollowups() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/supervision/followups',
        options: await _authorizedOptions(),
      );
      return (response.data!['data'] as List<dynamic>)
          .map(
            (item) => HealthFollowupModel.fromJson(
              item as Map<String, dynamic>,
            ),
          )
          .toList();
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<HealthFollowupModel> confirmHealthFollowup(String id) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/supervision/followups/$id/confirm',
        options: await _authorizedOptions(),
      );
      return HealthFollowupModel.fromJson(
        response.data!['data'] as Map<String, dynamic>,
      );
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<String> exportPersonalData(String format) async {
    try {
      final response = await _dio.get<dynamic>(
        '/supervision/export/$format',
        options: (await _authorizedOptions()).copyWith(
          responseType:
              format == 'csv' ? ResponseType.plain : ResponseType.json,
        ),
      );
      if (response.data is String) return response.data as String;
      return jsonEncode(response.data);
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<void> deleteMyData(String confirmation) async {
    try {
      await _dio.delete<void>(
        '/supervision/data',
        data: {'confirmation': confirmation},
        options: await _authorizedOptions(),
      );
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<Options> _authorizedOptions({String? idempotencyKey}) async {
    final token = await _tokens.read(_accessTokenKey);
    return Options(
      headers: {
        'Authorization': 'Bearer $token',
        if (idempotencyKey != null) 'Idempotency-Key': idempotencyKey,
      },
    );
  }

  Future<void> _handleUnauthorized(
    DioException error,
    ErrorInterceptorHandler handler,
  ) async {
    final request = error.requestOptions;
    final canRefresh = error.response?.statusCode == 401 &&
        request.headers.containsKey('Authorization') &&
        request.extra['authRetry'] != true &&
        !request.path.contains('/auth/');
    if (!canRefresh) {
      if (error.response?.statusCode == 401 &&
          request.extra['authRetry'] == true) {
        await _tokens.clear();
      }
      handler.next(error);
      return;
    }
    final accessToken = await _refreshAccessToken();
    if (accessToken == null) {
      await _tokens.clear();
      handler.next(error);
      return;
    }
    request.extra['authRetry'] = true;
    request.headers['Authorization'] = 'Bearer $accessToken';
    try {
      handler.resolve(await _dio.fetch<dynamic>(request));
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }

  Future<String?> _refreshAccessToken() {
    final current = _refreshInFlight;
    if (current != null) return current;
    final created = _performRefresh();
    _refreshInFlight = created;
    return created.whenComplete(() => _refreshInFlight = null);
  }

  Future<String?> _performRefresh() async {
    final refreshToken = await _tokens.read(_refreshTokenKey);
    if (refreshToken == null || refreshToken.isEmpty) return null;
    final refreshClient = Dio(
      BaseOptions(
        baseUrl: _dio.options.baseUrl,
        connectTimeout: _dio.options.connectTimeout,
        receiveTimeout: _dio.options.receiveTimeout,
        sendTimeout: _dio.options.sendTimeout,
      ),
    );
    _installDiagnostics(refreshClient);
    try {
      final response = await refreshClient.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refresh_token': refreshToken},
      );
      final body = response.data?['data'];
      if (body is! Map<String, dynamic>) return null;
      final accessToken = body['access_token'];
      final rotatedRefreshToken = body['refresh_token'];
      if (accessToken is! String || rotatedRefreshToken is! String) return null;
      await _tokens.write(_accessTokenKey, accessToken);
      await _tokens.write(_refreshTokenKey, rotatedRefreshToken);
      return accessToken;
    } on DioException {
      return null;
    }
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

class ServerHealthResult {
  const ServerHealthResult({
    required this.checkedAt,
    required this.latencyMs,
    required this.healthy,
    this.errorCode,
  });

  final DateTime checkedAt;
  final int latencyMs;
  final bool healthy;
  final String? errorCode;
}

class VisionPrivacySettings {
  const VisionPrivacySettings({
    this.allowThirdParty = false,
    this.retainImages = false,
  });

  final bool allowThirdParty;
  final bool retainImages;
}
