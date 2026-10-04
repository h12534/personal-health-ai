import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_client.dart';
import '../../../core/privacy/privacy_lock.dart';
import '../../../core/widgets/app_components.dart';
import '../../../core/theme/app_tokens.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/supervision_models.dart';
import 'supervision_controller.dart';

class TodayTasksScreen extends ConsumerStatefulWidget {
  const TodayTasksScreen({super.key});
  @override
  ConsumerState<TodayTasksScreen> createState() => _TodayTasksScreenState();
}

class _TodayTasksScreenState extends ConsumerState<TodayTasksScreen> {
  bool _updating = false;
  Object? _error;

  Future<void> _update(String id, String status) async {
    if (_updating) return;
    setState(() {
      _updating = true;
      _error = null;
    });
    try {
      await SupervisionController(ref).setTaskStatus(id, status);
      await ref.read(dailyTasksProvider.future);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(dailyTasksProvider);
    return Scaffold(
      appBar: DetailPageHeader(label: '今日任务'),
      body: tasks.when(
        loading: () => const LoadingState(label: '正在读取今日任务'),
        error: (error, _) => _Retry(
          error: error,
          label: '今日任务加载失败',
          onRetry: () => ref.invalidate(dailyTasksProvider),
        ),
        data: (values) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(dailyTasksProvider),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (values.isEmpty)
                EmptyState(
                    title: '今天还没有任务',
                    message: '任务依据已有记录生成。重新读取可检查最新任务，不会添加虚构完成状态。',
                    actionLabel: '重新读取今日任务',
                    onAction: () => ref.invalidate(dailyTasksProvider)),
              const Text('多数任务会在记录完成后自动勾选；也可以手动跳过。'),
              const SizedBox(height: 12),
              if (_updating) const Text('正在更新并重新读取任务…'),
              if (_error != null)
                Text(UiFailure.message(_error!),
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              for (final task in values)
                Semantics(
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
                            enabled: !_updating,
                            onSelected: (status) => _update(task.id, status),
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
            ],
          ),
        ),
      ),
    );
  }
}

class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends ConsumerState<NotificationSettingsScreen> {
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(reminderPreferencesProvider);
    return Scaffold(
      appBar: DetailPageHeader(label: '通知设置'),
      body: settings.when(
        loading: () => const LoadingState(label: '正在读取通知设置'),
        error: (error, _) => ErrorState(
          error: error,
          title: '通知设置暂时无法读取',
          onRetry: () => ref.invalidate(reminderPreferencesProvider),
        ),
        data: (value) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const InsightBlock(
                title: '在你同意后才请求系统通知权限',
                message: '开启后，可提醒晨重、训练和睡眠；完成后不再发送服务器智能提醒。'),
            const SizedBox(height: 12),
            if (!value.localNotificationsEnabled)
              FilledButton.icon(
                key: const Key('enable-notifications'),
                onPressed: _saving ? null : () => _enable(value),
                icon: const Icon(Icons.notifications_active_outlined),
                label: const Text('开启通知'),
              ),
            if (value.localNotificationsEnabled)
              SwitchListTile.adaptive(
                value: true,
                title: const Text('iPhone 本地通知'),
                subtitle: const Text('用于晨重、训练和睡眠等固定提醒。'),
                onChanged: _saving
                    ? null
                    : (enabled) => _save(
                          value.copyWith(localNotificationsEnabled: enabled),
                        ),
              ),
            SwitchListTile.adaptive(
              value: value.serverNotificationsEnabled,
              title: const Text('服务器智能提醒'),
              subtitle: const Text('用于营养、步数、同步、报告和复查等复杂判断。'),
              onChanged: _saving
                  ? null
                  : (enabled) => _save(
                        value.copyWith(serverNotificationsEnabled: enabled),
                      ),
            ),
            SwitchListTile.adaptive(
              value: value.enabled,
              title: const Text('监督提醒'),
              subtitle: const Text('可随时关闭；已完成任务不会提醒。'),
              onChanged: _saving
                  ? null
                  : (enabled) => _save(value.copyWith(enabled: enabled)),
            ),
            const SizedBox(height: 8),
            Text('提醒强度', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final mode in const [
              ('gentle', '轻提醒', '服务器智能提醒每天最多 2 条'),
              ('standard', '标准监督', '服务器智能提醒每天最多 4 条'),
              ('strict', '积极监督', '服务器智能提醒每天最多 6 条')
            ])
              Semantics(
                  selected: value.mode == mode.$1,
                  child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(mode.$2),
                      subtitle: Text(mode.$3),
                      trailing: value.mode == mode.$1
                          ? const Icon(Icons.check)
                          : null,
                      onTap: _saving
                          ? null
                          : () => _save(value.copyWith(mode: mode.$1)))),
            if (_saving) const Text('正在保存并重新读取设置…'),
            const SizedBox(height: 12),
            _TimeTile(
              title: '晨重提醒',
              enabled: !_saving,
              value: value.weighTime,
              onChanged: (time) => _save(value.copyWith(weighTime: time)),
            ),
            Text('餐次记录窗口', style: Theme.of(context).textTheme.titleMedium),
            for (final entry in const {
              'breakfast': '早餐',
              'lunch': '午餐',
              'dinner': '晚餐',
            }.entries)
              _MealWindowTile(
                title: entry.value,
                enabled: !_saving,
                value: value.mealWindows[entry.key] ?? const ['00:00', '23:59'],
                onChanged: (window) => _save(
                  value.copyWith(
                    mealWindows: {...value.mealWindows, entry.key: window},
                  ),
                ),
              ),
            _TimeTile(
              title: '训练提醒',
              enabled: !_saving,
              value: value.trainingReminderTime,
              onChanged: (time) => _save(
                value.copyWith(trainingReminderTime: time),
              ),
            ),
            _TimeTile(
              title: '步数检查',
              enabled: !_saving,
              value: value.stepCheckTime,
              onChanged: (time) => _save(value.copyWith(stepCheckTime: time)),
            ),
            _TimeTile(
              title: '睡眠准备',
              enabled: !_saving,
              value: value.sleepReminderTime,
              onChanged: (time) =>
                  _save(value.copyWith(sleepReminderTime: time)),
            ),
            _TimeTile(
              title: '勿扰开始',
              enabled: !_saving,
              value: value.doNotDisturbStart,
              onChanged: (time) => _save(
                value.copyWith(doNotDisturbStart: time),
              ),
            ),
            _TimeTile(
              title: '勿扰结束',
              enabled: !_saving,
              value: value.doNotDisturbEnd,
              onChanged: (time) => _save(
                value.copyWith(doNotDisturbEnd: time),
              ),
            ),
            DropdownButtonFormField<int>(
              isExpanded: true,
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
              onChanged: _saving
                  ? null
                  : (day) {
                      if (day != null) {
                        _save(
                          value.copyWith(weeklyReportDay: day),
                        );
                      }
                    },
            ),
            DropdownButtonFormField<int>(
              isExpanded: true,
              initialValue: value.monthlyReportDay,
              decoration: const InputDecoration(labelText: '月报生成日'),
              items: [
                for (var day = 1; day <= 28; day += 1)
                  DropdownMenuItem(value: day, child: Text('每月 $day 日')),
              ],
              onChanged: _saving
                  ? null
                  : (day) {
                      if (day != null) {
                        _save(
                          value.copyWith(monthlyReportDay: day),
                        );
                      }
                    },
            ),
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('积极监督仍受勿扰、冷却和每日上限约束。上述每日条数仅针对服务器智能提醒，不是全部本地通知的总上限。'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save(ReminderPreferencesModel value) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await SupervisionController(ref).savePreferences(value);
      if (!mounted) return;
      await ref.read(reminderPreferencesProvider.future);
    } on Object {
      ref.invalidate(reminderPreferencesProvider);
      try {
        await ref.read(reminderPreferencesProvider.future);
      } on Object {
        /* The provider shows a read error instead of stale values. */
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('设置结果暂时无法确认，请重新读取后再试。')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _enable(ReminderPreferencesModel value) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final granted =
          await SupervisionController(ref).enableNotifications(value);
      if (!mounted) return;
      await ref.read(reminderPreferencesProvider.future);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(granted ? '通知已开启' : '系统未授予通知权限')));
    } on Object {
      ref.invalidate(reminderPreferencesProvider);
      try {
        await ref.read(reminderPreferencesProvider.future);
      } on Object {
        /* The provider shows a read error instead of stale values. */
      }
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('通知设置暂时无法完成，请稍后重试。')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: DetailPageHeader(
            label: '健康报告',
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
      loading: () => const LoadingState(label: '正在读取健康报告'),
      error: (error, _) => _Retry(
        error: error,
        label: '报告加载失败',
        onRetry: () => ref.invalidate(healthReportsProvider(type)),
      ),
      data: (values) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (values.isNotEmpty)
            AsyncActionButton(
              key: Key('generate-$type-report'),
              onPressed: () async {
                await SupervisionController(ref).generateReport(type);
                await ref.read(healthReportsProvider(type).future);
              },
              icon: Icons.auto_awesome_outlined,
              label: values.isEmpty ? '生成本期报告' : '刷新本期数据',
            ),
          const SizedBox(height: 12),
          if (values.isEmpty)
            EmptyState(
                title: '还没有本期报告',
                message: '即使数据不完整，也可以生成简短报告。',
                actionWidget: AsyncActionButton(
                    key: Key('generate-$type-report'),
                    label: '生成本期报告',
                    icon: Icons.auto_awesome_outlined,
                    onPressed: () async {
                      await SupervisionController(ref).generateReport(type);
                      await ref.read(healthReportsProvider(type).future);
                    })),
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
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Padding(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${AppFormat.fullDate(report.periodStart)}–${AppFormat.fullDate(report.periodEnd)}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(report.summary),
              const Divider(height: 24),
              Column(
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
      appBar: DetailPageHeader(
        label: '健康时间线',
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
              loading: () => const LoadingState(label: '正在读取健康时间线'),
              error: (error, _) => _Retry(
                error: error,
                label: '时间线加载失败',
                onRetry: () => ref.invalidate(healthTimelineProvider(category)),
              ),
              data: (events) => events.isEmpty
                  ? ListView(padding: AppSpacing.pageInsets, children: [
                      EmptyState(
                          title: '还没有这类记录',
                          message: '日常记录会逐步汇集到这里。可查看全部记录，或重新读取。',
                          actionLabel: category == 'all' ? '重新读取时间线' : '查看全部记录',
                          onAction: () {
                            if (category == 'all') {
                              ref.invalidate(healthTimelineProvider(category));
                            } else {
                              setState(() => category = 'all');
                            }
                          })
                    ])
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: events.length,
                      itemBuilder: (context, index) {
                        final event = events[index];
                        return Semantics(
                          label:
                              '${DateFormat('yyyy年M月d日').format(event.occurredAt.toLocal())}，${event.title}，${event.summary}',
                          child: ListTile(
                            leading: Icon(_eventIcon(event.eventType)),
                            title: Text(event.title),
                            subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      AppFormat.fullDate(
                                          event.occurredAt.toLocal()),
                                      style: AppTypography.caption),
                                  Text(event.summary)
                                ]),
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
      appBar: DetailPageHeader(label: '同期趋势对照'),
      body: data.when(
        loading: () => const LoadingState(label: '正在读取同期趋势'),
        error: (error, _) => _Retry(
          error: error,
          label: '趋势对照加载失败',
          onRetry: () => ref.invalidate(crossDomainProvider),
        ),
        data: (value) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            InsightBlock(title: '观察同期变化，不推断因果', message: value.disclaimer),
            for (final entry in value.series.entries)
              Semantics(
                label: '${_metricLabel(entry.key)}共有${entry.value.length}个数据点',
                child: ListTile(
                  leading: const Icon(Icons.show_chart),
                  title: Text(_metricLabel(entry.key)),
                  subtitle: Text('${entry.value.length} 个数据点'),
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
      appBar: DetailPageHeader(label: '健康复查'),
      body: followups.when(
        loading: () => const LoadingState(label: '正在读取复查建议'),
        error: (error, _) => _Retry(
          error: error,
          label: '复查提醒加载失败',
          onRetry: () => ref.invalidate(healthFollowupsProvider),
        ),
        data: (values) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('AI 或规则只能提出建议；你确认后才会创建复查任务。'),
            const SizedBox(height: 12),
            if (values.isEmpty)
              EmptyState(
                  title: '还没有复查建议',
                  message: '这里只展示已有建议，不会自动创建任务。',
                  actionLabel: '重新读取建议',
                  onAction: () => ref.invalidate(healthFollowupsProvider)),
            for (final item in values)
              AppSection(
                  title: item.labTestCode ?? '健康复查',
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(AppFormat.fullDate(item.recommendedDate),
                            style: AppTypography.caption),
                        Text(item.reason),
                        if (item.status == 'suggested')
                          AsyncActionButton(
                              label: '确认',
                              icon: Icons.check,
                              onPressed: () async {
                                await SupervisionController(ref)
                                    .confirmFollowup(item.id);
                                await ref.read(healthFollowupsProvider.future);
                              })
                        else
                          Text(_taskStatus(item.status))
                      ])),
          ],
        ),
      ),
    );
  }
}

class PrivacyDataScreen extends ConsumerStatefulWidget {
  const PrivacyDataScreen({super.key});

  @override
  ConsumerState<PrivacyDataScreen> createState() => _PrivacyDataScreenState();
}

class _PrivacyDataScreenState extends ConsumerState<PrivacyDataScreen> {
  bool _working = false;

  @override
  Widget build(BuildContext context) {
    final lock = ref.watch(privacyLockControllerProvider);
    return Scaffold(
      appBar: DetailPageHeader(label: 'App 锁与数据'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppSection(
            title: 'App 锁',
            child: lock.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(20),
                child: Text('正在读取设备验证状态…'),
              ),
              error: (_, __) => ListRow(
                  title: '无法读取设备验证状态',
                  subtitle: '重新读取后再设置 App 锁',
                  onTap: () => ref.invalidate(privacyLockControllerProvider)),
              data: (value) => SwitchListTile.adaptive(
                key: const Key('biometric-lock-switch'),
                value: value.enabled,
                title: const Text('Face ID / Touch ID'),
                subtitle: Text(
                  value.available
                      ? '离开 App 超过 2 分钟后再次要求验证。'
                      : '此设备暂不可用；默认保持关闭。',
                ),
                onChanged: value.available && !_working
                    ? (enabled) => _run(() async {
                          final changed = await ref
                              .read(privacyLockControllerProvider.notifier)
                              .setEnabled(enabled);
                          if (!changed && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('身份验证未完成')),
                            );
                          }
                        })
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 12),
          AppSection(
            title: '你的数据',
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.download_outlined),
                  title: const Text('导出 JSON'),
                  subtitle: const Text('体重、饮食、训练、睡眠、体检和设置'),
                  onTap: _working ? null : () => _run(() => _export('json')),
                ),
                ListTile(
                  leading: const Icon(Icons.table_view_outlined),
                  title: const Text('导出 CSV'),
                  subtitle: const Text('复制为通用表格文本'),
                  onTap: _working ? null : () => _run(() => _export('csv')),
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
            onPressed: _working ? null : () => _run(_delete),
            icon: const Icon(Icons.delete_forever_outlined),
            label: const Text('删除我的全部数据'),
          ),
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('删除会清除主数据库和私有原文件；备份保留策略见隐私文档。'),
          ),
          if (_working) const Text('正在处理，请稍候…'),
        ],
      ),
    );
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await operation();
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('操作暂时无法完成，请稍后重试。')));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _export(String format) async {
    try {
      final value =
          await ref.read(apiClientProvider).exportPersonalData(format);
      await Clipboard.setData(ClipboardData(text: value));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${format.toUpperCase()} 已复制到剪贴板')),
        );
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('导出失败，请稍后重试')),
        );
      }
    }
  }

  Future<void> _delete() async {
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DeletePersonalDataDialog(onDelete: () async {
        await ref.read(apiClientProvider).deleteMyData('DELETE MY DATA');
        await ref.read(authControllerProvider.notifier).logout();
      }),
    );
  }
}

/// Presentation-only confirmation; the caller owns the existing delete/logout.
class DeletePersonalDataDialog extends StatefulWidget {
  const DeletePersonalDataDialog({super.key, required this.onDelete});
  final Future<void> Function() onDelete;
  @override
  State<DeletePersonalDataDialog> createState() =>
      _DeletePersonalDataDialogState();
}

class _DeletePersonalDataDialogState extends State<DeletePersonalDataDialog> {
  final _controller = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _deleting = false;
  String? _error;
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_deleting,
      child: AlertDialog(
        scrollable: true,
        title: const Text('永久删除全部数据？'),
        content: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('此操作不可撤销。请输入 DELETE MY DATA 进行二次确认。'),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('delete-confirmation'),
                  controller: _controller,
                  enabled: !_deleting,
                  autocorrect: false,
                  validator: (value) => value?.trim() == 'DELETE MY DATA'
                      ? null
                      : '请输入完整的 DELETE MY DATA',
                  decoration: const InputDecoration(labelText: '确认文字'),
                ),
                if (_error != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(_error!)),
              ],
            )),
        actions: [
          TextButton(
            onPressed: _deleting ? null : () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: _deleting ? null : _submit,
            child: Text(_deleting ? '正在删除…' : '永久删除'),
          ),
        ],
      ));

  Future<void> _submit() async {
    if (_deleting || !_form.currentState!.validate()) return;
    setState(() {
      _deleting = true;
      _error = null;
    });
    try {
      await widget.onDelete();
      if (mounted) Navigator.pop(context, true);
    } on Object {
      if (mounted) setState(() => _error = '删除结果暂时无法确认。请重新读取数据后再决定是否重试。');
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }
}

class _TimeTile extends StatelessWidget {
  const _TimeTile({
    required this.title,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String title;
  final String value;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: const Icon(Icons.schedule),
        title: Text(title),
        subtitle: Text(_shortTime(value)),
        onTap: !enabled
            ? null
            : () async {
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
    this.enabled = true,
  });

  final String title;
  final List<String> value;
  final ValueChanged<List<String>> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: const Icon(Icons.restaurant_outlined),
        title: Text(title),
        subtitle: Text(
            '${_shortTime(value[0])}–${_shortTime(value[1])}\n超过窗口后仍未记录时才考虑提醒'),
        onTap: !enabled
            ? null
            : () async {
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
  Widget build(BuildContext context) => MetricRow(
      label: label,
      value: value is num && (value as num).isFinite
          ? AppFormat.number(value as num,
              decimals: label == '平均睡眠' ? 1 : 0, grouped: label == '平均步数')
          : '—',
      unit: switch (label) {
        '平均步数' => '步',
        '平均睡眠' => '小时',
        '完成训练' => '次',
        _ => ''
      });
}

class _Retry extends StatelessWidget {
  const _Retry(
      {required this.label, required this.onRetry, required this.error});

  final String label;
  final VoidCallback onRetry;
  final Object error;

  @override
  Widget build(BuildContext context) =>
      ErrorState(error: error, title: label, onRetry: onRetry);
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
