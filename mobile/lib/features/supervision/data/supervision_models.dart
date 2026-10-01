class DailyTaskModel {
  const DailyTaskModel({
    required this.id,
    required this.date,
    required this.taskType,
    required this.title,
    required this.description,
    required this.status,
    required this.priority,
    this.scheduledTime,
    this.completedAt,
    this.sourceEntityId,
  });

  factory DailyTaskModel.fromJson(Map<String, dynamic> json) => DailyTaskModel(
        id: json['id'] as String,
        date: DateTime.parse(json['date'] as String),
        taskType: json['task_type'] as String,
        title: json['title'] as String,
        description: json['description'] as String,
        status: json['status'] as String,
        priority: json['priority'] as int? ?? 0,
        scheduledTime: json['scheduled_time'] as String?,
        completedAt: json['completed_at'] == null
            ? null
            : DateTime.parse(json['completed_at'] as String),
        sourceEntityId: json['source_entity_id'] as String?,
      );

  final String id;
  final DateTime date;
  final String taskType;
  final String title;
  final String description;
  final String status;
  final int priority;
  final String? scheduledTime;
  final DateTime? completedAt;
  final String? sourceEntityId;

  bool get isCompleted => status == 'completed';
}

class ReminderPreferencesModel {
  const ReminderPreferencesModel({
    required this.enabled,
    required this.mode,
    required this.weighTime,
    required this.mealWindows,
    required this.trainingReminderTime,
    required this.sleepReminderTime,
    required this.stepCheckTime,
    required this.doNotDisturbStart,
    required this.doNotDisturbEnd,
    required this.weeklyReportDay,
    required this.monthlyReportDay,
    required this.localNotificationsEnabled,
    required this.serverNotificationsEnabled,
  });

  factory ReminderPreferencesModel.fromJson(Map<String, dynamic> json) =>
      ReminderPreferencesModel(
        enabled: json['enabled'] as bool? ?? true,
        mode: json['mode'] as String? ?? 'standard',
        weighTime: json['weigh_time'] as String? ?? '08:00:00',
        mealWindows: (json['meal_windows'] as Map<String, dynamic>?)?.map(
              (key, value) => MapEntry(
                key,
                (value as List<dynamic>)
                    .map((item) => item.toString())
                    .toList(),
              ),
            ) ??
            const {
              'breakfast': ['07:00', '10:00'],
              'lunch': ['11:00', '14:00'],
              'dinner': ['17:00', '21:00'],
            },
        trainingReminderTime:
            json['training_reminder_time'] as String? ?? '18:00:00',
        sleepReminderTime: json['sleep_reminder_time'] as String? ?? '23:00:00',
        stepCheckTime: json['step_check_time'] as String? ?? '20:00:00',
        doNotDisturbStart:
            json['do_not_disturb_start'] as String? ?? '23:00:00',
        doNotDisturbEnd: json['do_not_disturb_end'] as String? ?? '07:30:00',
        weeklyReportDay: json['weekly_report_day'] as int? ?? 6,
        monthlyReportDay: json['monthly_report_day'] as int? ?? 1,
        localNotificationsEnabled:
            json['local_notifications_enabled'] as bool? ?? false,
        serverNotificationsEnabled:
            json['server_notifications_enabled'] as bool? ?? true,
      );

  final bool enabled;
  final String mode;
  final String weighTime;
  final Map<String, List<String>> mealWindows;
  final String trainingReminderTime;
  final String sleepReminderTime;
  final String stepCheckTime;
  final String doNotDisturbStart;
  final String doNotDisturbEnd;
  final int weeklyReportDay;
  final int monthlyReportDay;
  final bool localNotificationsEnabled;
  final bool serverNotificationsEnabled;

  ReminderPreferencesModel copyWith({
    bool? enabled,
    String? mode,
    String? weighTime,
    Map<String, List<String>>? mealWindows,
    String? trainingReminderTime,
    String? sleepReminderTime,
    String? stepCheckTime,
    String? doNotDisturbStart,
    String? doNotDisturbEnd,
    int? weeklyReportDay,
    int? monthlyReportDay,
    bool? localNotificationsEnabled,
    bool? serverNotificationsEnabled,
  }) =>
      ReminderPreferencesModel(
        enabled: enabled ?? this.enabled,
        mode: mode ?? this.mode,
        weighTime: weighTime ?? this.weighTime,
        mealWindows: mealWindows ?? this.mealWindows,
        trainingReminderTime: trainingReminderTime ?? this.trainingReminderTime,
        sleepReminderTime: sleepReminderTime ?? this.sleepReminderTime,
        stepCheckTime: stepCheckTime ?? this.stepCheckTime,
        doNotDisturbStart: doNotDisturbStart ?? this.doNotDisturbStart,
        doNotDisturbEnd: doNotDisturbEnd ?? this.doNotDisturbEnd,
        weeklyReportDay: weeklyReportDay ?? this.weeklyReportDay,
        monthlyReportDay: monthlyReportDay ?? this.monthlyReportDay,
        localNotificationsEnabled:
            localNotificationsEnabled ?? this.localNotificationsEnabled,
        serverNotificationsEnabled:
            serverNotificationsEnabled ?? this.serverNotificationsEnabled,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'mode': mode,
        'weigh_time': weighTime,
        'meal_windows': mealWindows,
        'training_reminder_time': trainingReminderTime,
        'sleep_reminder_time': sleepReminderTime,
        'step_check_time': stepCheckTime,
        'do_not_disturb_start': doNotDisturbStart,
        'do_not_disturb_end': doNotDisturbEnd,
        'weekly_report_day': weeklyReportDay,
        'monthly_report_day': monthlyReportDay,
        'local_notifications_enabled': localNotificationsEnabled,
        'server_notifications_enabled': serverNotificationsEnabled,
      };
}

class HealthReportModel {
  const HealthReportModel({
    required this.id,
    required this.reportType,
    required this.periodStart,
    required this.periodEnd,
    required this.metrics,
    required this.summary,
    required this.nextActions,
    required this.provider,
  });

  factory HealthReportModel.fromJson(Map<String, dynamic> json) =>
      HealthReportModel(
        id: json['id'] as String,
        reportType: json['report_type'] as String,
        periodStart: DateTime.parse(json['period_start'] as String),
        periodEnd: DateTime.parse(json['period_end'] as String),
        metrics: Map<String, dynamic>.from(
          json['metrics'] as Map<String, dynamic>? ?? const {},
        ),
        summary: json['summary'] as String,
        nextActions: (json['next_actions'] as List<dynamic>? ?? const [])
            .map((item) => item.toString())
            .toList(),
        provider: json['provider'] as String? ?? 'unknown',
      );

  final String id;
  final String reportType;
  final DateTime periodStart;
  final DateTime periodEnd;
  final Map<String, dynamic> metrics;
  final String summary;
  final List<String> nextActions;
  final String provider;
}

class TimelineEventModel {
  const TimelineEventModel({
    required this.id,
    required this.eventType,
    required this.category,
    required this.occurredAt,
    required this.title,
    required this.summary,
  });

  factory TimelineEventModel.fromJson(Map<String, dynamic> json) =>
      TimelineEventModel(
        id: json['id'] as String,
        eventType: json['event_type'] as String,
        category: json['category'] as String,
        occurredAt: DateTime.parse(json['occurred_at'] as String),
        title: json['title'] as String,
        summary: json['summary'] as String,
      );

  final String id;
  final String eventType;
  final String category;
  final DateTime occurredAt;
  final String title;
  final String summary;
}

class HealthFollowupModel {
  const HealthFollowupModel({
    required this.id,
    required this.reason,
    required this.recommendedDate,
    required this.status,
    this.labTestCode,
  });

  factory HealthFollowupModel.fromJson(Map<String, dynamic> json) =>
      HealthFollowupModel(
        id: json['id'] as String,
        labTestCode: json['lab_test_code'] as String?,
        reason: json['reason'] as String,
        recommendedDate: DateTime.parse(json['recommended_date'] as String),
        status: json['status'] as String,
      );

  final String id;
  final String? labTestCode;
  final String reason;
  final DateTime recommendedDate;
  final String status;
}

class CrossDomainModel {
  const CrossDomainModel({
    required this.series,
    required this.observations,
    required this.disclaimer,
  });

  factory CrossDomainModel.fromJson(Map<String, dynamic> json) =>
      CrossDomainModel(
        series: (json['series'] as Map<String, dynamic>).map(
          (key, value) => MapEntry(
            key,
            (value as List<dynamic>)
                .map((item) => Map<String, dynamic>.from(
                      item as Map<String, dynamic>,
                    ))
                .toList(),
          ),
        ),
        observations: (json['observations'] as List<dynamic>? ?? const [])
            .map((item) => item.toString())
            .toList(),
        disclaimer: json['disclaimer'] as String,
      );

  final Map<String, List<Map<String, dynamic>>> series;
  final List<String> observations;
  final String disclaimer;
}
