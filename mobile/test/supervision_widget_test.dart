import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_health_os/core/notifications/local_notification_service.dart';
import 'package:personal_health_os/core/privacy/privacy_lock.dart';
import 'package:personal_health_os/features/dashboard/data/dashboard_model.dart';
import 'package:personal_health_os/features/dashboard/presentation/dashboard_screen.dart';
import 'package:personal_health_os/features/supervision/data/supervision_models.dart';
import 'package:personal_health_os/features/supervision/presentation/supervision_controller.dart';
import 'package:personal_health_os/features/supervision/presentation/supervision_screens.dart';

void main() {
  testWidgets('dashboard shows only key daily tasks', (tester) async {
    final data = DashboardModel(
      date: DateTime(2026, 10, 1),
      todayWeightKg: 98,
      average7dKg: 98.4,
      weekChangeKg: -0.4,
      caloriesConsumed: 1500,
      caloriesTarget: 2100,
      proteinG: 90,
      proteinTargetG: 130,
      steps: 5000,
      stepsTarget: 8000,
      waterMl: 0,
      trainingCompleted: false,
      morningWeightCompleted: true,
      aiNextAction: '继续保持。',
      keyTasks: [
        _task('1', '晨重', completed: true),
        _task('2', '午餐'),
        _task('3', '8000 步'),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DashboardContent(data: data, onAddWeight: () {}),
        ),
      ),
    );
    expect(find.text('今日任务'), findsOneWidget);
    // The dashboard also keeps the existing quick-action button named “晨重”.
    expect(find.text('晨重'), findsNWidgets(2));
    expect(find.text('午餐'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('notification settings explain permission before requesting', (
    tester,
  ) async {
    final notifications = MockNotificationCoordinator();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          reminderPreferencesProvider
              .overrideWith((ref) async => _preferences()),
          notificationCoordinatorProvider.overrideWithValue(notifications),
        ],
        child: const MaterialApp(home: NotificationSettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('在你同意后才请求系统通知权限'), findsOneWidget);
    expect(find.byKey(const Key('enable-notifications')), findsOneWidget);
    expect(notifications.requestCount, 0);
    expect(find.text('轻提醒'), findsOneWidget);
    expect(find.text('标准监督'), findsOneWidget);
    expect(find.text('积极监督'), findsOneWidget);
  });

  testWidgets('reports render summaries without a health score',
      (tester) async {
    final daily = HealthReportModel(
      id: 'daily-1',
      reportType: 'daily',
      periodStart: DateTime(2026, 10, 1),
      periodEnd: DateTime(2026, 10, 1),
      metrics: const {
        'average_steps': 7200,
        'average_sleep_hours': 7.2,
        'workouts_completed': 1,
      },
      summary: '今天整体执行稳定，明天重点是睡眠。',
      nextActions: const ['今晚按计划休息。'],
      provider: 'mock',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          healthReportsProvider('daily').overrideWith((ref) async => [daily]),
          healthReportsProvider('weekly').overrideWith((ref) async => []),
          healthReportsProvider('monthly').overrideWith((ref) async => []),
        ],
        child: const MaterialApp(home: ReportsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('整体执行稳定'), findsOneWidget);
    expect(find.textContaining('健康总分'), findsOneWidget);
    expect(find.textContaining('/100'), findsNothing);
  });

  testWidgets('timeline filters and exposes accessible event text', (
    tester,
  ) async {
    final event = TimelineEventModel(
      id: 'weight:1',
      eventType: 'weight',
      category: 'body',
      occurredAt: DateTime(2026, 10, 1, 8),
      title: '体重记录',
      summary: '98.0 kg',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          healthTimelineProvider('all').overrideWith((ref) async => [event]),
        ],
        child: const MaterialApp(home: HealthTimelineScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('全部'), findsOneWidget);
    expect(find.text('身体'), findsOneWidget);
    expect(find.text('训练'), findsOneWidget);
    expect(find.text('体重记录'), findsOneWidget);
    expect(find.text('98.0 kg'), findsOneWidget);
  });

  testWidgets('export UI and destructive action are clearly separated', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          privacyLockControllerProvider.overrideWith(
            _UnlockedLockController.new,
          ),
        ],
        child: const MaterialApp(home: PrivacyDataScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('导出 JSON'), findsOneWidget);
    expect(find.text('导出 CSV'), findsOneWidget);
    expect(find.byKey(const Key('delete-my-data')), findsOneWidget);
    expect(find.textContaining('二次确认'), findsNothing);
  });
}

class _UnlockedLockController extends PrivacyLockController {
  @override
  Future<PrivacyLockState> build() async => const PrivacyLockState(
        enabled: false,
        unlocked: true,
        available: true,
      );
}

DailyTaskModel _task(String id, String title, {bool completed = false}) =>
    DailyTaskModel(
      id: id,
      date: DateTime(2026, 10, 1),
      taskType: 'custom',
      title: title,
      description: '测试任务',
      status: completed ? 'completed' : 'pending',
      priority: 50,
    );

ReminderPreferencesModel _preferences() => const ReminderPreferencesModel(
      enabled: true,
      mode: 'standard',
      weighTime: '08:00:00',
      mealWindows: {
        'breakfast': ['07:00', '10:00'],
        'lunch': ['11:00', '14:00'],
        'dinner': ['17:00', '21:00'],
      },
      trainingReminderTime: '18:00:00',
      sleepReminderTime: '23:00:00',
      stepCheckTime: '20:00:00',
      doNotDisturbStart: '23:00:00',
      doNotDisturbEnd: '07:30:00',
      weeklyReportDay: 6,
      monthlyReportDay: 1,
      localNotificationsEnabled: false,
      serverNotificationsEnabled: true,
    );
