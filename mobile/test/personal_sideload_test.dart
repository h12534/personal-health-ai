import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_health_os/core/config/app_config.dart';
import 'package:personal_health_os/core/health/health_data_provider.dart';
import 'package:personal_health_os/core/network/api_client.dart';
import 'package:personal_health_os/features/profile/presentation/health_sync_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('distribution flags agree with remote push and manual flavor', () {
    expect(AppConfig.remotePushEnabled, !AppConfig.isPersonalSideload);
    expect(AppConfig.appleHealthDisabled,
        AppConfig.isPersonalSideload && AppConfig.personalSideloadFree);
    if (AppConfig.appleHealthDisabled) {
      expect(AppConfig.buildFlavor, 'PERSONAL_SIDELOAD_FREE');
    }
  });

  test('free flavor selects manual provider without invoking Apple', () async {
    final manual = _manual();
    final provider = personalSideloadHealthProvider(
        free: true, apple: _BrokenApple(), manual: manual);
    expect(identical(provider, manual), isTrue);
    expect((await _read(provider))?.weightKg, 72.4);
    expect((await _read(provider))?.steps, isNull);
  });

  test('native capability failure falls back without a crash or fake zero',
      () async {
    final provider = personalSideloadHealthProvider(
        free: false, apple: _BrokenApple(), manual: _manual());
    expect(await provider.isAvailable(), isTrue);
    expect(provider.supports(HealthMetric.steps), isTrue);
    expect(await provider.requestAuthorization(HealthMetric.steps),
        HealthAuthorization.requested);
    expect((await _read(provider))?.source, 'manual');
  });

  test('missing HealthKit profile prevents health plugin configuration',
      () async {
    final provider =
        AppleHealthProvider(isIOS: true, capabilityProbe: () async => false);
    expect(await provider.isAvailable(), isFalse);
    expect(await provider.requestAuthorization(HealthMetric.steps),
        HealthAuthorization.unavailable);
    expect(await _read(provider), isNull);
  });

  test('missing native channel is a recoverable capability failure', () async {
    expect(await personalHealthKitCapability(), isFalse);
    const channel = MethodChannel('personal_health_os/capabilities');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => false);
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    expect(await personalHealthKitCapability(), isFalse);
  });

  test('personal remote push registration does not contact server or tokens',
      () async {
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (_, __) {
      fail('Remote push must not send a request in personal mode');
    }));
    final api = ApiClient(dio, _NoTokens(), remotePushEnabled: false);
    await api.registerPushDevice(
        deviceId: 'device', platform: 'ios', token: 'test-token');
  });

  testWidgets('manual capability notice is visible independently of API access',
      (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: PersonalManualHealthNotice())));
    expect(
        find.byKey(const Key('personal-manual-health-notice')), findsOneWidget);
    expect(find.text(AppConfig.manualHealthNotice), findsOneWidget);
  });
}

ManualHealthProvider _manual() => ManualHealthProvider(
      ({required from, required to, required metrics}) async =>
          const HealthDataSnapshot(source: 'manual', weightKg: 72.4),
    );

Future<HealthDataSnapshot?> _read(HealthDataProvider provider) => provider.read(
      from: DateTime(2026, 1, 1),
      to: DateTime(2026, 1, 2),
      metrics: {HealthMetric.steps},
    );

class _BrokenApple implements HealthDataProvider {
  @override
  String get source => 'healthkit';
  @override
  Future<bool> isAvailable() async =>
      throw PlatformException(code: 'missing_entitlement');
  @override
  bool supports(HealthMetric metric) =>
      throw PlatformException(code: 'missing_entitlement');
  @override
  Future<HealthAuthorization> requestAuthorization(HealthMetric metric) async =>
      throw PlatformException(code: 'missing_entitlement');
  @override
  Future<HealthDataSnapshot?> read(
          {required DateTime from,
          required DateTime to,
          required Set<HealthMetric> metrics}) async =>
      throw PlatformException(code: 'missing_entitlement');
}

class _NoTokens implements TokenStore {
  @override
  Future<String?> read(String key) async =>
      throw StateError('Must not access tokens');
  @override
  Future<void> write(String key, String value) async =>
      throw StateError('Must not access tokens');
  @override
  Future<void> clear() async => throw StateError('Must not access tokens');
}
