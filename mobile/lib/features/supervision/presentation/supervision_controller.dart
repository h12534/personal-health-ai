import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/notifications/local_notification_service.dart';
import '../data/supervision_models.dart';

final dailyTasksProvider = FutureProvider<List<DailyTaskModel>>((ref) {
  return ref.watch(apiClientProvider).fetchDailyTasks();
});

final reminderPreferencesProvider =
    FutureProvider<ReminderPreferencesModel>((ref) {
  return ref.watch(apiClientProvider).fetchReminderPreferences();
});

final healthReportsProvider =
    FutureProvider.family<List<HealthReportModel>, String>((ref, type) {
  return ref.watch(apiClientProvider).fetchHealthReports(type);
});

final healthTimelineProvider =
    FutureProvider.family<List<TimelineEventModel>, String>((ref, category) {
  final now = DateTime.now();
  return ref.watch(apiClientProvider).fetchHealthTimeline(
        DateTime(now.year - 1, now.month, now.day),
        now,
        category,
      );
});

final healthFollowupsProvider =
    FutureProvider<List<HealthFollowupModel>>((ref) {
  return ref.watch(apiClientProvider).fetchHealthFollowups();
});

final crossDomainProvider = FutureProvider<CrossDomainModel>((ref) {
  final now = DateTime.now();
  return ref.watch(apiClientProvider).fetchCrossDomainTrends(
    DateTime(now.year - 1, now.month, now.day),
    now,
    const ['weight', 'steps', 'sleep', 'hba1c'],
  );
});

final notificationCoordinatorProvider =
    Provider<NotificationCoordinator>((ref) {
  return LocalNotificationService(
    onAction: (actionId, payload) async {
      if (actionId == 'complete' && payload?.startsWith('task:') == true) {
        final taskType = payload!.substring(5);
        final tasks = await ref.read(apiClientProvider).fetchDailyTasks();
        final matches = tasks.where(
          (task) => task.taskType == taskType && task.status == 'pending',
        );
        if (matches.isNotEmpty) {
          await ref
              .read(apiClientProvider)
              .updateDailyTask(matches.first.id, 'completed');
          ref.invalidate(dailyTasksProvider);
        }
      }
    },
  );
});

class SupervisionController {
  const SupervisionController(this.ref);

  final WidgetRef ref;

  Future<void> setTaskStatus(String id, String status) async {
    await ref.read(apiClientProvider).updateDailyTask(id, status);
    ref.invalidate(dailyTasksProvider);
    ref.invalidate(healthReportsProvider);
  }

  Future<ReminderPreferencesModel> savePreferences(
    ReminderPreferencesModel preferences,
  ) async {
    final saved = await ref
        .read(apiClientProvider)
        .updateReminderPreferences(preferences);
    await ref.read(notificationCoordinatorProvider).applyPreferences(saved);
    ref.invalidate(reminderPreferencesProvider);
    return saved;
  }

  Future<bool> enableNotifications(ReminderPreferencesModel current) async {
    final notifications = ref.read(notificationCoordinatorProvider);
    await notifications.initialize();
    final granted = await notifications.requestPermission();
    if (!granted) return false;
    await savePreferences(
      current.copyWith(localNotificationsEnabled: true),
    );
    return true;
  }

  Future<void> generateReport(String type, {bool force = false}) async {
    await ref.read(apiClientProvider).generateHealthReport(type, force: force);
    ref.invalidate(healthReportsProvider(type));
  }

  Future<void> confirmFollowup(String id) async {
    await ref.read(apiClientProvider).confirmHealthFollowup(id);
    ref.invalidate(healthFollowupsProvider);
    ref.invalidate(dailyTasksProvider);
  }
}
