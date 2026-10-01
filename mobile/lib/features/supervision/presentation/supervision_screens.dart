import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_client.dart';
import '../../../core/privacy/privacy_lock.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/supervision_models.dart';
import 'supervision_controller.dart';

class TodayTasksScreen extends ConsumerWidget {
  const TodayTasksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(dailyTasksProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('今日任务')),
      body: tasks.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _Retry(
          label: '今日任务加载失败',
          onRetry: () => ref.invalidate(dailyTasksProvider),
        ),
        data: (values) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(dailyTasksProvider),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('多数任务会在记录完成后自动勾选；也可以手动跳过。'),
              const SizedBox(height: 12),
              for (final task in values)
                Card(
                  child: Semantics(
                    label: '${task.title}，${_taskStatus(task.status)}',
                    child: ListTile(
                      leading: Icon(
                        task.isCompleted
                            ? Icons.check_circle
                            : task.status == 'skipped'
                                ? Icons.remove_circle_outline
                                : Icons.radio_button_unchecked,
                        color: task.isCompleted
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      title: Text(task.title),
                      subtitle: Text(task.description),
                      trailing: task.status == 'pending'
                          ? PopupMenuButton<String>(
                              tooltip: '更新任务状态',
                              onSelected: (status) => SupervisionController(ref)
                                  .setTaskStatus(task.id, status),
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'completed',
                                  child: Text('标记完成'),
                                ),
                                PopupMenuItem(
                                  value: 'skipped',
                                  child: Text('今天跳过'),
                                ),
                              ],
                            )
                          : null,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(reminderPreferencesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('通知设置')),
      body: settings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _Retry(
          label: '通知设置加载失败',
          onRetry: () => ref.invalidate(reminderPreferencesProvider),
        ),
        data: (value) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('在你同意后才请求系统通知权限'),
                    SizedBox(height: 8),
                    Text('开启后，可提醒晨重、训练和睡眠；完成后不再发送服务器智能提醒。'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (!value.localNotificationsEnabled)
              FilledButton.icon(
                key: const Key('enable-notifications'),
                onPressed: () => _enable(context, ref, value),
                icon: const Icon(Icons.notifications_active_outlined),
                label: const Text('开启通知'),
              ),
            if (value.localNotificationsEnabled)
              SwitchListTile.adaptive(
                value: true,
                title: const Text('iPhone 本地通知'),
                subtitle: const Text('用于晨重、训练和睡眠等固定提醒。'),
                onChanged: (enabled) =>
                    SupervisionController(ref).savePreferences(
                  value.copyWith(localNotificationsEnabled: enabled),
                ),
              ),
            SwitchListTile.adaptive(
              value: value.serverNotificationsEnabled,
              title: const Text('服务器智能提醒'),
              subtitle: const Text('用于营养、步数、同步、报告和复查等复杂判断。'),
              onChanged: (enabled) =>
                  SupervisionController(ref).savePreferences(
                value.copyWith(serverNotificationsEnabled: enabled),
              ),
            ),
            SwitchListTile.adaptive(
              value: value.enabled,
              title: const Text('监督提醒'),
              subtitle: const Text('可随时关闭；已完成任务不会提醒。'),
              onChanged: (enabled) => SupervisionController(ref)
                  .savePreferences(value.copyWith(enabled: enabled)),
            ),
            const SizedBox(height: 8),
            Text('提醒强度', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'gentle', label: Text('温和')),
                ButtonSegment(value: 'standard', label: Text('标准')),
                ButtonSegment(value: 'strict', label: Text('积极')),
              ],
              selected: {value.mode},
              onSelectionChanged: (selection) => SupervisionController(ref)
                  .savePreferences(value.copyWith(mode: selection.first)),
            ),
            const SizedBox(height: 12),
            _TimeTile(
              title: '晨重提醒',
              value: value.weighTime,
              onChanged: (time) => SupervisionController(ref)
                  .savePreferences(value.copyWith(weighTime: time)),
            ),
            Text('餐次记录窗口', style: Theme.of(context).textTheme.titleMedium),
            for (final entry in const {
              'breakfast': '早餐',
              'lunch': '午餐',
              'dinner': '晚餐',
            }.entries)
              _MealWindowTile(
                title: entry.value,
                value: value.mealWindows[entry.key] ?? const ['00:00', '23:59'],
                onChanged: (window) =>
                    SupervisionController(ref).savePreferences(
                  value.copyWith(
                    mealWindows: {...value.mealWindows, entry.key: window},
                  ),
                ),
              ),
            _TimeTile(
              title: '训练提醒',
              value: value.trainingReminderTime,
              onChanged: (time) => SupervisionController(ref).savePreferences(
                value.copyWith(trainingReminderTime: time),
              ),
            ),
            _TimeTile(
              title: '步数检查',
              value: value.stepCheckTime,
              onChanged: (time) => SupervisionController(ref)
                  .savePreferences(value.copyWith(stepCheckTime: time)),
            ),
            _TimeTile(
              title: '睡眠准备',
              value: value.sleepReminderTime,
              onChanged: (time) => SupervisionController(ref)
                  .savePreferences(value.copyWith(sleepReminderTime: time)),
            ),
            _TimeTile(
              title: '勿扰开始',
              value: value.doNotDisturbStart,
              onChanged: (time) => SupervisionController(ref).savePreferences(
                value.copyWith(doNotDisturbStart: time),
              ),
            ),
            _TimeTile(
              title: '勿扰结束',
              value: value.doNotDisturbEnd,
              onChanged: (time) => SupervisionController(ref).savePreferences(
                value.copyWith(doNotDisturbEnd: time),
              ),
            ),
            DropdownButtonFormField<int>(
              initialValue: value.weeklyReportDay,
              decoration: const InputDecoration(labelText: '周报生成日'),
              items: const [
                DropdownMenuItem(value: 0, child: Text('周一')),
                DropdownMenuItem(value: 1, child: Text('周二')),
                DropdownMenuItem(value: 2, child: Text('周三')),
                DropdownMenuItem(value: 3, child: Text('周四')),
                DropdownMenuItem(value: 4, child: Text('周五')),
                DropdownMenuItem(value: 5, child: Text('周六')),
                DropdownMenuItem(value: 6, child: Text('周日')),
              ],
              onChanged: (day) {
                if (day != null) {
                  SupervisionController(ref).savePreferences(
                    value.copyWith(weeklyReportDay: day),
                  );
                }
              },
            ),
            DropdownButtonFormField<int>(
              initialValue: value.monthlyReportDay,
              decoration: const InputDecoration(labelText: '月报生成日'),
              items: [
                for (var day = 1; day <= 28; day += 1)
                  DropdownMenuItem(value: day, child: Text('每月 $day 日')),
              ],
              onChanged: (day) {
                if (day != null) {
                  SupervisionController(ref).savePreferences(
                    value.copyWith(monthlyReportDay: day),
                  );
                }
              },
            ),
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('严格模式仍受勿扰、冷却和每日上限约束，不会连续轰炸。'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _enable(
    BuildContext context,
    WidgetRef ref,
    ReminderPreferencesModel value,
  ) async {
    final granted = await SupervisionController(ref).enableNotifications(value);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(granted ? '通知已开启' : '系统未授予通知权限')),
    );
  }
}

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('健康报告'),
            bottom: const TabBar(
              tabs: [Tab(text: '日报'), Tab(text: '周报'), Tab(text: '月报')],
            ),
          ),
          body: const TabBarView(
            children: [
              _ReportTab(type: 'daily'),
              _ReportTab(type: 'weekly'),
              _ReportTab(type: 'monthly'),
            ],
          ),
        ),
      );
}

class _ReportTab extends ConsumerWidget {
  const _ReportTab({required this.type});

  final String type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reports = ref.watch(healthReportsProvider(type));
    return reports.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => _Retry(
        label: '报告加载失败',
        onRetry: () => ref.invalidate(healthReportsProvider(type)),
      ),
      data: (values) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton.tonalIcon(
            key: Key('generate-$type-report'),
            onPressed: () => SupervisionController(ref).generateReport(type),
            icon: const Icon(Icons.auto_awesome_outlined),
            label: Text(values.isEmpty ? '生成本期报告' : '刷新本期数据'),
          ),
          const SizedBox(height: 12),
          if (values.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('即使数据不完整，也可以生成简短报告。'),
            ),
          for (final report in values) _ReportCard(report: report),
        ],
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.report});

  final HealthReportModel report;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${DateFormat('M月d日').format(report.periodStart)}–${DateFormat('M月d日').format(report.periodEnd)}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(report.summary),
              const Divider(height: 24),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MetricChip('平均步数', report.metrics['average_steps']),
                  _MetricChip('平均睡眠', report.metrics['average_sleep_hours']),
                  _MetricChip('完成训练', report.metrics['workouts_completed']),
                ],
              ),
              for (final action in report.nextActions)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.arrow_forward, size: 18),
                  title: Text(action),
                ),
              const Text('不使用健康总分；AI 仅总结程序已计算的结构数据。'),
            ],
          ),
        ),
      );
}

class HealthTimelineScreen extends ConsumerStatefulWidget {
  const HealthTimelineScreen({super.key});

  @override
  ConsumerState<HealthTimelineScreen> createState() =>
      _HealthTimelineScreenState();
}

class _HealthTimelineScreenState extends ConsumerState<HealthTimelineScreen> {
  String category = 'all';

  @override
  Widget build(BuildContext context) {
    final timeline = ref.watch(healthTimelineProvider(category));
    return Scaffold(
      appBar: AppBar(
        title: const Text('健康时间线'),
        actions: [
          IconButton(
            tooltip: '同期趋势对照',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const CrossDomainScreen(),
              ),
            ),
            icon: const Icon(Icons.multiline_chart),
          ),
        ],
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                for (final entry in const {
                  'all': '全部',
                  'body': '身体',
                  'nutrition': '饮食',
                  'training': '训练',
                  'lab': '体检',
                }.entries)
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: ChoiceChip(
                      label: Text(entry.value),
                      selected: category == entry.key,
                      onSelected: (_) => setState(() => category = entry.key),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: timeline.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => _Retry(
                label: '时间线加载失败',
                onRetry: () => ref.invalidate(healthTimelineProvider(category)),
              ),
              data: (events) => ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: events.length,
                itemBuilder: (context, index) {
                  final event = events[index];
                  return Semantics(
                    label:
                        '${DateFormat('yyyy年M月d日').format(event.occurredAt.toLocal())}，${event.title}，${event.summary}',
                    child: Card(
                      child: ListTile(
                        leading: Icon(_eventIcon(event.eventType)),
                        title: Text(event.title),
                        subtitle: Text(event.summary),
                        trailing: Text(
                          DateFormat('M/d').format(event.occurredAt.toLocal()),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CrossDomainScreen extends ConsumerWidget {
  const CrossDomainScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(crossDomainProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('同期趋势对照')),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _Retry(
          label: '趋势对照加载失败',
          onRetry: () => ref.invalidate(crossDomainProvider),
        ),
        data: (value) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: Theme.of(context).colorScheme.tertiaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(value.disclaimer),
              ),
            ),
            for (final entry in value.series.entries)
              Semantics(
                label: '${_metricLabel(entry.key)}共有${entry.value.length}个数据点',
                child: Card(
                  child: ListTile(
                    leading: const Icon(Icons.show_chart),
                    title: Text(_metricLabel(entry.key)),
                    subtitle: Text('${entry.value.length} 个数据点'),
                  ),
                ),
              ),
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('图表和文字只描述同期变化，不自动推断 A 导致 B。'),
            ),
          ],
        ),
      ),
    );
  }
}

class FollowupsScreen extends ConsumerWidget {
  const FollowupsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final followups = ref.watch(healthFollowupsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('健康复查')),
      body: followups.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _Retry(
          label: '复查提醒加载失败',
          onRetry: () => ref.invalidate(healthFollowupsProvider),
        ),
        data: (values) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('AI 或规则只能提出建议；你确认后才会创建复查任务。'),
            const SizedBox(height: 12),
            for (final item in values)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.event_repeat_outlined),
                  title: Text(item.labTestCode ?? '健康复查'),
                  subtitle: Text(
                    '${DateFormat('yyyy-MM-dd').format(item.recommendedDate)}\n${item.reason}',
                  ),
                  isThreeLine: true,
                  trailing: item.status == 'suggested'
                      ? TextButton(
                          onPressed: () => SupervisionController(ref)
                              .confirmFollowup(item.id),
                          child: const Text('确认'),
                        )
                      : Text(_taskStatus(item.status)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class PrivacyDataScreen extends ConsumerWidget {
  const PrivacyDataScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lock = ref.watch(privacyLockControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('隐私锁与数据')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: lock.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(20),
                child: LinearProgressIndicator(),
              ),
              error: (_, __) => const ListTile(title: Text('无法加载生物识别状态')),
              data: (value) => SwitchListTile.adaptive(
                key: const Key('biometric-lock-switch'),
                value: value.enabled,
                title: const Text('Face ID / Touch ID 隐私锁'),
                subtitle: Text(
                  value.available
                      ? '离开 App 超过 2 分钟后再次要求验证。'
                      : '此设备暂不可用；默认保持关闭。',
                ),
                onChanged: value.available
                    ? (enabled) async {
                        final changed = await ref
                            .read(privacyLockControllerProvider.notifier)
                            .setEnabled(enabled);
                        if (!changed && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('身份验证未完成')),
                          );
                        }
                      }
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.download_outlined),
                  title: const Text('导出 JSON'),
                  subtitle: const Text('体重、饮食、训练、睡眠、体检和设置'),
                  onTap: () => _export(context, ref, 'json'),
                ),
                ListTile(
                  leading: const Icon(Icons.table_view_outlined),
                  title: const Text('导出 CSV'),
                  subtitle: const Text('复制为通用表格文本'),
                  onTap: () => _export(context, ref, 'csv'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            key: const Key('delete-my-data'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => _delete(context, ref),
            icon: const Icon(Icons.delete_forever_outlined),
            label: const Text('删除我的全部数据'),
          ),
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('删除会清除主数据库和私有原文件；备份保留策略见隐私文档。'),
          ),
        ],
      ),
    );
  }

  Future<void> _export(
      BuildContext context, WidgetRef ref, String format) async {
    try {
      final value =
          await ref.read(apiClientProvider).exportPersonalData(format);
      await Clipboard.setData(ClipboardData(text: value));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${format.toUpperCase()} 已复制到剪贴板')),
        );
      }
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('导出失败，请稍后重试')),
        );
      }
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('永久删除全部数据？'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('此操作不可撤销。请输入 DELETE MY DATA 进行二次确认。'),
            const SizedBox(height: 12),
            TextField(
              key: const Key('delete-confirmation'),
              controller: controller,
              decoration: const InputDecoration(labelText: '确认文字'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              controller.text.trim() == 'DELETE MY DATA',
            ),
            child: const Text('永久删除'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (confirmed != true) return;
    await ref.read(apiClientProvider).deleteMyData('DELETE MY DATA');
    await ref.read(authControllerProvider.notifier).logout();
  }
}

class _TimeTile extends StatelessWidget {
  const _TimeTile({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: const Icon(Icons.schedule),
        title: Text(title),
        trailing: Text(_shortTime(value)),
        onTap: () async {
          final initial = _parseTime(value);
          final selected = await showTimePicker(
            context: context,
            initialTime: initial,
          );
          if (selected != null) {
            onChanged(
              '${selected.hour.toString().padLeft(2, '0')}:${selected.minute.toString().padLeft(2, '0')}:00',
            );
          }
        },
      );
}

class _MealWindowTile extends StatelessWidget {
  const _MealWindowTile({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final List<String> value;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: const Icon(Icons.restaurant_outlined),
        title: Text(title),
        subtitle: const Text('超过窗口后仍未记录时才考虑提醒'),
        trailing: Text('${_shortTime(value[0])}–${_shortTime(value[1])}'),
        onTap: () async {
          final start = await showTimePicker(
            context: context,
            initialTime: _parseTime(value[0]),
            helpText: '选择$title开始时间',
          );
          if (start == null || !context.mounted) return;
          final end = await showTimePicker(
            context: context,
            initialTime: _parseTime(value[1]),
            helpText: '选择$title结束时间',
          );
          if (end == null) return;
          onChanged([
            '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}',
            '${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}',
          ]);
        },
      );
}

class _MetricChip extends StatelessWidget {
  const _MetricChip(this.label, this.value);

  final String label;
  final Object? value;

  @override
  Widget build(BuildContext context) => Chip(
        label: Text('$label ${value ?? '--'}'),
      );
}

class _Retry extends StatelessWidget {
  const _Retry({required this.label, required this.onRetry});

  final String label;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: FilledButton.tonalIcon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: Text(label),
        ),
      );
}

String _taskStatus(String status) => switch (status) {
      'completed' => '已完成',
      'skipped' => '已跳过',
      'expired' => '已过期',
      'confirmed' => '已确认',
      'cancelled' => '已取消',
      _ => '待完成',
    };

String _shortTime(String value) =>
    value.length > 5 ? value.substring(0, 5) : value;

TimeOfDay _parseTime(String value) {
  final pieces = value.split(':');
  return TimeOfDay(
    hour: int.tryParse(pieces.first) ?? 8,
    minute: pieces.length > 1 ? int.tryParse(pieces[1]) ?? 0 : 0,
  );
}

IconData _eventIcon(String type) => switch (type) {
      'weight' => Icons.monitor_weight_outlined,
      'meal' => Icons.restaurant_outlined,
      'workout' || 'pr' => Icons.fitness_center_outlined,
      'lab' => Icons.biotech_outlined,
      'sleep' => Icons.bedtime_outlined,
      'steps' => Icons.directions_walk_outlined,
      'health_report' => Icons.summarize_outlined,
      _ => Icons.circle_outlined,
    };

String _metricLabel(String value) => switch (value) {
      'weight' => '体重',
      'steps' => '步数',
      'sleep' => '睡眠',
      'hba1c' => 'HbA1c',
      _ => value,
    };
