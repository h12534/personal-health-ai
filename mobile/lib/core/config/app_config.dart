class AppConfig {
  const AppConfig._();

  static const appVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '0.1.0-beta.1',
  );
  static const buildNumber = String.fromEnvironment(
    'BUILD_NUMBER',
    defaultValue: '2',
  );

  static const distribution = String.fromEnvironment(
    'APP_DISTRIBUTION',
    defaultValue: 'standard',
  );
  static const personalSideloadFree =
      bool.fromEnvironment('PERSONAL_SIDELOAD_FREE');
  static bool get isPersonalSideload => distribution == 'personal_sideload';
  static bool get appleHealthDisabled =>
      isPersonalSideload && personalSideloadFree;
  static bool get remotePushEnabled => !isPersonalSideload;
  static String get buildFlavor => appleHealthDisabled
      ? 'PERSONAL_SIDELOAD_FREE'
      : isPersonalSideload
          ? 'PERSONAL_SIDELOAD_HEALTHKIT'
          : 'STANDARD';
  static const manualHealthNotice = '当前私人免费签名版本未启用 Apple Health 自动同步，可以手动记录数据。';

  static const environment = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'development',
  );

  static const _apiBaseUrlOverride = String.fromEnvironment('API_BASE_URL');

  static String get apiBaseUrl => resolveApiBaseUrl(
        environment: environment,
        override: _apiBaseUrlOverride,
      );

  static String get apiEnvironment =>
      switch (environment.trim().toLowerCase()) {
        'dev' || 'development' => 'dev',
        'staging' => 'staging',
        'prod' || 'production' => 'prod',
        _ => 'dev',
      };

  static String resolveApiBaseUrl({
    required String environment,
    String override = '',
  }) {
    final normalizedEnvironment = switch (environment.trim().toLowerCase()) {
      'dev' || 'development' => 'development',
      'staging' => 'staging',
      'prod' || 'production' => 'production',
      _ => throw StateError('APP_ENV must be dev, staging, or prod.'),
    };
    final candidate = override.trim().isNotEmpty
        ? override.trim()
        : switch (normalizedEnvironment) {
            'development' => 'https://dev-api.personal-health.invalid/api/v1',
            'staging' => 'https://staging-api.personal-health.invalid/api/v1',
            _ => 'https://api.personal-health.invalid/api/v1',
          };
    final uri = Uri.tryParse(candidate);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw StateError('API_BASE_URL must be an absolute URL.');
    }
    if ({'localhost', '127.0.0.1', '::1'}.contains(uri.host)) {
      throw StateError(
        'API_BASE_URL cannot use localhost; an iPhone resolves it to itself.',
      );
    }
    if (normalizedEnvironment != 'development' && uri.scheme != 'https') {
      throw StateError('Staging and production API_BASE_URL must use HTTPS.');
    }
    if (uri.scheme != 'https' && uri.scheme != 'http') {
      throw StateError('API_BASE_URL must use HTTP or HTTPS.');
    }
    return candidate.replaceFirst(RegExp(r'/+$'), '');
  }
}
