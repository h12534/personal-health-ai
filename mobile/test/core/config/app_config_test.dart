import 'package:flutter_test/flutter_test.dart';
import 'package:personal_health_os/core/config/app_config.dart';

void main() {
  group('AppConfig.resolveApiBaseUrl', () {
    test('uses distinct HTTPS defaults', () {
      expect(
        AppConfig.resolveApiBaseUrl(environment: 'dev'),
        'https://dev-api.personal-health.invalid/api/v1',
      );
      expect(
        AppConfig.resolveApiBaseUrl(environment: 'staging'),
        'https://staging-api.personal-health.invalid/api/v1',
      );
      expect(
        AppConfig.resolveApiBaseUrl(environment: 'prod'),
        'https://api.personal-health.invalid/api/v1',
      );
    });

    test('allows scoped HTTP only in development', () {
      expect(
        AppConfig.resolveApiBaseUrl(
          environment: 'dev',
          override: 'http://192.168.1.20:8080/api/v1/',
        ),
        'http://192.168.1.20:8080/api/v1',
      );
      expect(
        () => AppConfig.resolveApiBaseUrl(
          environment: 'staging',
          override: 'http://192.168.1.20:8080/api/v1',
        ),
        throwsStateError,
      );
    });

    test('rejects loopback hosts that cannot address a development Mac', () {
      expect(
        () => AppConfig.resolveApiBaseUrl(
          environment: 'dev',
          override: 'http://localhost:8080/api/v1',
        ),
        throwsStateError,
      );
    });
  });
}
