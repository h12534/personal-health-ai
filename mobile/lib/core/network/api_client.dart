import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../features/dashboard/data/dashboard_model.dart';
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

  Future<Options> _authorizedOptions() async {
    final token = await _storage.read(key: _accessTokenKey);
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

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

