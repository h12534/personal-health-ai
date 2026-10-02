import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../features/supervision/data/supervision_models.dart';

typedef NotificationActionHandler = Future<void> Function(
  String actionId,
  String? payload,
);

abstract interface class NotificationCoordinator {
  Future<void> initialize();
  Future<bool> requestPermission();
  Future<String> permissionStatus();
  Future<void> applyPreferences(ReminderPreferencesModel preferences);
}

class LocalNotificationService implements NotificationCoordinator {
  LocalNotificationService({
    FlutterLocalNotificationsPlugin? plugin,
    NotificationActionHandler? onAction,
  })  : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
        _onAction = onAction;

  final FlutterLocalNotificationsPlugin _plugin;
  final NotificationActionHandler? _onAction;
  bool _initialized = false;

  static const _ids = <int>{701, 702, 703};

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    try {
      final current = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(current.identifier));
    } on Object {
      tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
    }
    final category = DarwinNotificationCategory(
      'HEALTH_TASK',
      actions: [
        DarwinNotificationAction.plain('complete', '已完成'),
        DarwinNotificationAction.plain(
          'open',
          '打开 App',
          options: {DarwinNotificationActionOption.foreground},
        ),
      ],
    );
    await _plugin.initialize(
      settings: InitializationSettings(
        android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: IOSInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
          notificationCategories: [category],
        ),
      ),
      onDidReceiveNotificationResponse: (response) async {
        await _onAction?.call(response.actionId ?? '', response.payload);
      },
    );
    _initialized = true;
  }

  @override
  Future<bool> requestPermission() async {
    await initialize();
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                  IOSFlutterLocalNotificationsPlugin>()
              ?.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin>()
              ?.requestNotificationsPermission() ??
          true;
    }
    return true;
  }

  @override
  Future<String> permissionStatus() async {
    if (defaultTargetPlatform != TargetPlatform.iOS &&
        defaultTargetPlatform != TargetPlatform.android) {
      return 'not_applicable';
    }
    await initialize();
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final value = await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.checkPermissions();
      if (value == null) return 'unknown';
      if (value.isProvisionalEnabled) return 'provisional';
      return value.isEnabled ? 'granted' : 'denied_or_not_requested';
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      final value = await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.areNotificationsEnabled();
      return value == true ? 'granted' : 'denied_or_not_requested';
    }
    return 'unknown';
  }

  @override
  Future<void> applyPreferences(ReminderPreferencesModel preferences) async {
    await initialize();
    for (final id in _ids) {
      await _plugin.cancel(id: id);
    }
    if (!preferences.enabled || !preferences.localNotificationsEnabled) return;
    if (!_insideDnd(
      preferences.weighTime,
      preferences.doNotDisturbStart,
      preferences.doNotDisturbEnd,
    )) {
      await _scheduleDaily(
        id: 701,
        time: preferences.weighTime,
        title: '晨重提醒',
        body: '今天晨重还没有记录；如果已经完成，可以忽略这条固定提醒。',
        payload: 'task:weigh_in',
      );
    }
    if (!_insideDnd(
      preferences.trainingReminderTime,
      preferences.doNotDisturbStart,
      preferences.doNotDisturbEnd,
    )) {
      await _scheduleDaily(
        id: 702,
        time: preferences.trainingReminderTime,
        title: '训练计划',
        body: '如果今天有训练计划，方便时打开 App 查看；恢复差时可以降低强度。',
        payload: 'task:workout',
      );
    }
    if (!_insideDnd(
      preferences.sleepReminderTime,
      preferences.doNotDisturbStart,
      preferences.doNotDisturbEnd,
    )) {
      await _scheduleDaily(
        id: 703,
        time: preferences.sleepReminderTime,
        title: '睡眠准备',
        body: '现在差不多可以开始放松，为明天留出足够睡眠。',
        payload: 'task:sleep',
      );
    }
  }

  Future<void> _scheduleDaily({
    required int id,
    required String time,
    required String title,
    required String body,
    required String payload,
  }) async {
    final pieces = time.split(':').map(int.parse).toList();
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      pieces[0],
      pieces[1],
    );
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: scheduled,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'health_tasks',
          '健康任务',
          channelDescription: '晨重、训练与睡眠等由你开启的固定健康提醒',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(
          categoryIdentifier: 'HEALTH_TASK',
          threadIdentifier: 'health_tasks',
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: payload,
    );
  }

  static bool _insideDnd(String value, String start, String end) {
    int minutes(String input) {
      final parts = input.split(':');
      return int.parse(parts[0]) * 60 + int.parse(parts[1]);
    }

    final current = minutes(value);
    final from = minutes(start);
    final until = minutes(end);
    if (from == until) return false;
    if (from < until) return current >= from && current < until;
    return current >= from || current < until;
  }
}

class MockNotificationCoordinator implements NotificationCoordinator {
  bool permissionGranted;
  int requestCount = 0;
  ReminderPreferencesModel? appliedPreferences;

  MockNotificationCoordinator({this.permissionGranted = true});

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> requestPermission() async {
    requestCount += 1;
    return permissionGranted;
  }

  @override
  Future<String> permissionStatus() async =>
      permissionGranted ? 'granted' : 'denied_or_not_requested';

  @override
  Future<void> applyPreferences(ReminderPreferencesModel preferences) async {
    appliedPreferences = preferences;
  }
}
