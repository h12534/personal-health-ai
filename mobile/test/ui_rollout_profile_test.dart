import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_health_os/core/network/api_client.dart';
import 'package:personal_health_os/core/health/health_data_provider.dart';
import 'package:personal_health_os/core/privacy/privacy_lock.dart';
import 'package:personal_health_os/core/notifications/local_notification_service.dart';
import 'package:personal_health_os/core/theme/app_theme.dart';
import 'package:personal_health_os/features/profile/presentation/profile_screen.dart';
import 'package:personal_health_os/features/profile/presentation/health_sync_screen.dart';
import 'package:personal_health_os/features/supervision/data/supervision_models.dart';
import 'package:personal_health_os/features/supervision/presentation/supervision_controller.dart';
import 'package:personal_health_os/features/supervision/presentation/supervision_screens.dart';
import 'package:personal_health_os/features/training/data/training_models.dart';

const rolloutPreferences = ReminderPreferencesModel(
    enabled: true,
    mode: 'standard',
    weighTime: '08:00:00',
    mealWindows: {
      'breakfast': ['07:00', '10:00'],
      'lunch': ['11:00', '14:00'],
      'dinner': ['17:00', '21:00']
    },
    trainingReminderTime: '18:00:00',
    sleepReminderTime: '23:00:00',
    stepCheckTime: '20:00:00',
    doNotDisturbStart: '23:00:00',
    doNotDisturbEnd: '07:30:00',
    weeklyReportDay: 6,
    monthlyReportDay: 1,
    localNotificationsEnabled: false,
    serverNotificationsEnabled: true);
const rolloutPermissions = [
  HealthPermissionModel(
      dataType: 'steps', enabled: true, authorizationStatus: 'unknown'),
  HealthPermissionModel(
      dataType: 'sleep', enabled: false, authorizationStatus: 'denied'),
  HealthPermissionModel(
      dataType: 'resting_heart_rate',
      enabled: false,
      authorizationStatus: 'not_requested'),
  HealthPermissionModel(
      dataType: 'workouts', enabled: false, authorizationStatus: 'unavailable')
];

class RolloutUnlockedLock extends PrivacyLockController {
  @override
  Future<PrivacyLockState> build() async =>
      const PrivacyLockState(enabled: false, unlocked: true, available: true);
}

class _SlowPreferencesApi implements ApiClient {
  final saved = Completer<ReminderPreferencesModel>();
  final reloaded = Completer<ReminderPreferencesModel>();
  int reads = 0;
  int updates = 0;
  @override
  Future<ReminderPreferencesModel> fetchReminderPreferences() async =>
      ++reads == 1 ? rolloutPreferences : reloaded.future;
  @override
  Future<ReminderPreferencesModel> updateReminderPreferences(
      ReminderPreferencesModel value) {
    updates++;
    return saved.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PartialHealthApi implements ApiClient {
  bool enabled = false;
  int reads = 0;
  @override
  Future<List<HealthPermissionModel>> fetchHealthPermissions() async {
    reads++;
    return [
      HealthPermissionModel(
          dataType: 'steps',
          enabled: enabled,
          authorizationStatus: enabled ? 'unknown' : 'not_requested')
    ];
  }

  @override
  Future<HealthPermissionModel> setHealthPermission(
      {required String dataType,
      required bool enabled,
      required String authorizationStatus}) async {
    this.enabled = enabled;
    return HealthPermissionModel(
        dataType: dataType,
        enabled: enabled,
        authorizationStatus: authorizationStatus);
  }

  @override
  Future<void> uploadHealthSummary(Map<String, dynamic> summary) async =>
      throw StateError('secret sync error');
  @override
  Future<List<Map<String, dynamic>>> fetchHealthSyncStatus() async => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
      'Health partial sync failure re-reads saved toggle without claiming permission',
      (tester) async {
    final api = _PartialHealthApi();
    await tester.pumpWidget(ProviderScope(overrides: [
      apiClientProvider.overrideWithValue(api),
      healthKitCapabilityProvider.overrideWith((ref) async => true),
      healthDataProviderProvider
          .overrideWithValue(const MockHealthDataProvider())
    ], child: const MaterialApp(home: HealthSyncScreen())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('步数'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    expect(api.enabled, isTrue);
    expect(api.reads, 2);
    expect(
        tester
            .widgetList<SwitchListTile>(find.byType(SwitchListTile))
            .first
            .value,
        isTrue);
    expect(find.textContaining('系统读取权限需另行确认'), findsOneWidget);
    expect(find.textContaining('健康同步未全部完成'), findsOneWidget);
    expect(find.textContaining('secret sync error'), findsNothing);
  });
  testWidgets('reminder UI awaits refreshed settings before allowing next save',
      (tester) async {
    final api = _SlowPreferencesApi();
    final notifications = MockNotificationCoordinator();
    await tester.pumpWidget(ProviderScope(overrides: [
      apiClientProvider.overrideWithValue(api),
      notificationCoordinatorProvider.overrideWithValue(notifications)
    ], child: const MaterialApp(home: NotificationSettingsScreen())));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('轻提醒'));
    await tester.tap(find.text('轻提醒'));
    await tester.pump();
    expect(api.updates, 1);
    expect(
        tester
            .widgetList<SwitchListTile>(find.byType(SwitchListTile))
            .every((item) => item.onChanged == null),
        isTrue);
    api.saved.complete(rolloutPreferences.copyWith(mode: 'gentle'));
    await tester.pump();
    await tester.pump();
    expect(api.reads, 2);
    expect(find.text('正在保存并重新读取设置…'), findsOneWidget);
    expect(
        tester
            .widgetList<SwitchListTile>(find.byType(SwitchListTile))
            .every((item) => item.onChanged == null),
        isTrue);
    api.reloaded.complete(rolloutPreferences.copyWith(
        mode: 'gentle', serverNotificationsEnabled: false));
    await tester.pumpAndSettle();
    expect(find.text('正在保存并重新读取设置…'), findsNothing);
    await tester.drag(find.byType(ListView), const Offset(0, 1600));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<SwitchListTile>(
                find.widgetWithText(SwitchListTile, '服务器智能提醒'))
            .value,
        isFalse);
    expect(notifications.requestCount, 0);
  });
  for (final width in [320.0, 393.0, 430.0]) {
    for (final dark in [false, true]) {
      testWidgets('profile and settings $width dark=$dark 200%',
          (tester) async {
        tester.view.physicalSize = Size(width, 852);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        for (final screen in [
          const ProfileScreen(),
          const HealthSyncScreen(),
          const NotificationSettingsScreen(),
          const PrivacyDataScreen()
        ]) {
          await tester.pumpWidget(ProviderScope(
              overrides: [
                visionPrivacyProvider
                    .overrideWith((ref) async => const VisionPrivacySettings()),
                healthKitCapabilityProvider.overrideWith((ref) async => true),
                healthPermissionsProvider
                    .overrideWith((ref) async => rolloutPermissions),
                healthSyncStatusProvider.overrideWith((ref) async => []),
                reminderPreferencesProvider
                    .overrideWith((ref) async => rolloutPreferences),
                privacyLockControllerProvider
                    .overrideWith(RolloutUnlockedLock.new)
              ],
              child: MaterialApp(
                  theme: dark ? AppTheme.dark : AppTheme.light,
                  home: MediaQuery(
                      data: MediaQueryData(
                          size: Size(width, 852),
                          textScaler: TextScaler.linear(2)),
                      child: Scaffold(body: SafeArea(child: screen))))));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull,
              reason: '${screen.runtimeType} initial');
          for (var step = 0; step < 12; step++) {
            await tester.drag(
                find.byType(ListView).first, const Offset(0, -450));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull,
                reason: '${screen.runtimeType} scroll $step');
          }
          await tester.pumpWidget(const SizedBox());
        }
      });
    }
  }
  testWidgets('Health toggles do not claim unknown permission is granted',
      (tester) async {
    await tester.pumpWidget(ProviderScope(overrides: [
      healthKitCapabilityProvider.overrideWith((ref) async => true),
      healthPermissionsProvider.overrideWith((ref) async => rolloutPermissions),
      healthSyncStatusProvider.overrideWith((ref) async => [])
    ], child: const MaterialApp(home: HealthSyncScreen())));
    await tester.pumpAndSettle();
    expect(find.textContaining('系统读取权限需另行确认'), findsOneWidget);
    expect(find.textContaining('请在系统健康设置中检查读取权限'), findsOneWidget);
    expect(find.textContaining('尚未申请读取'), findsOneWidget);
    expect(find.textContaining('当前设备不可用'), findsOneWidget);
    final switches =
        tester.widgetList<SwitchListTile>(find.byType(SwitchListTile)).toList();
    expect(switches.map((item) => item.value), [true, false, false, false]);
    expect(find.textContaining('已授权'), findsNothing);
  });
  testWidgets(
      'delete validates, awaits, blocks duplicates, keeps failed phrase',
      (tester) async {
    final pending = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: DeletePersonalDataDialog(onDelete: () async {
      calls++;
      await pending.future;
      throw StateError('secret raw error');
    }))));
    await tester.tap(find.text('永久删除'));
    await tester.pump();
    expect(calls, 0);
    expect(find.text('请输入完整的 DELETE MY DATA'), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('delete-confirmation')), 'DELETE MY DATA');
    await tester.tap(find.text('永久删除'));
    await tester.pump();
    await tester.tap(find.text('正在删除…'));
    await tester.pump();
    expect(calls, 1);
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '取消'))
            .onPressed,
        isNull);
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining('删除结果暂时无法确认'), findsOneWidget);
    expect(find.textContaining('secret raw error'), findsNothing);
    expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        'DELETE MY DATA');
  });
}
