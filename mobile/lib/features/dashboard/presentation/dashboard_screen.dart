import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_navigation_bar.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_components.dart';
import '../../coach/data/coach_models.dart';
import '../../coach/presentation/coach_controller.dart';
import '../../profile/presentation/profile_screen.dart';
import '../../nutrition/presentation/nutrition_screen.dart';
import '../../health/presentation/health_screen.dart';
import '../../training/presentation/training_screen.dart';
import '../../supervision/presentation/supervision_screens.dart';
import '../data/dashboard_model.dart';
import 'dashboard_controller.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});
  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  int _index = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
            child: IndexedStack(index: _index, children: [
          _DashboardTab(
              onAddWeight: _showWeightDialog,
              onOpenHealth: () => setState(() => _index = 3),
              onOpenTasks: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                      builder: (_) => const TodayTasksScreen()))),
          const NutritionScreen(),
          const TrainingScreen(),
          const HealthScreen(),
          const ProfileScreen(),
        ])),
        bottomNavigationBar: AppNavigationBar(
            index: _index,
            onSelect: (value) {
              if (value != _index) {
                HapticFeedback.selectionClick();
                setState(() => _index = value);
              }
            }),
      );

  Future<void> _showWeightDialog() async {
    final saved = await showDialog<bool>(
        context: context,
        builder: (_) => WeightEntryDialog(
            onSave: (value) => WeightController(ref).add(value)));
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('晨重已记录')));
    }
  }
}

/// Focused native dialog: retain input on failure, never submit twice.
class WeightEntryDialog extends StatefulWidget {
  const WeightEntryDialog({super.key, required this.onSave});
  final Future<void> Function(double) onSave;
  @override
  State<WeightEntryDialog> createState() => _WeightEntryDialogState();
}

class _WeightEntryDialogState extends State<WeightEntryDialog> {
  final _controller = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _saving = false;
  Object? _error;
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(double.parse(_controller.text.trim()));
      if (mounted) Navigator.pop(context, true);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_saving,
        child: AlertDialog(
          scrollable: true,
          title: const Text('记录今日晨重'),
          content: Form(
              key: _form,
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                        controller: _controller,
                        autofocus: true,
                        enabled: !_saving,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                            labelText: '体重',
                            suffixText: 'kg',
                            helperText: '建议在起床后、进食前记录'),
                        validator: (text) {
                          final value = double.tryParse(text?.trim() ?? '');
                          return value == null ||
                                  !value.isFinite ||
                                  value < 20 ||
                                  value > 500
                              ? '请输入 20–500 kg 之间的有效数值'
                              : null;
                        },
                        onFieldSubmitted: (_) => _save()),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Semantics(
                          liveRegion: true,
                          child: Text('${UiFailure.title(_error!)}。输入已保留，请重试。',
                              style: AppTypography.secondary.copyWith(
                                  color: AppColors.of(context).danger)))
                    ],
                  ])),
          actions: [
            TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context),
                child: const Text('取消')),
            FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving
                    ? '正在保存…'
                    : _error == null
                        ? '保存'
                        : '重试保存')),
          ],
        ),
      );
}

class _DashboardTab extends ConsumerWidget {
  const _DashboardTab(
      {required this.onAddWeight,
      required this.onOpenHealth,
      required this.onOpenTasks});
  final VoidCallback onAddWeight, onOpenHealth, onOpenTasks;
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(dashboardProvider).when(
            loading: () => const LoadingState(label: '正在读取今日记录'),
            error: (error, stack) => ErrorState(
                error: error, onRetry: () => ref.invalidate(dashboardProvider)),
            data: (data) => DashboardContent(
                data: data,
                onAddWeight: onAddWeight,
                onOpenHealth: onOpenHealth,
                onOpenTasks: onOpenTasks,
                trend: ref.watch(weightTrendProvider).valueOrNull,
                onRefresh: () async {
                  ref.invalidate(weightTrendProvider);
                  try {
                    await ref
                        .refresh(dashboardProvider.future)
                        .then<void>((_) {});
                  } on Object {/* Provider renders safe retry state. */}
                }),
          );
}

class DashboardContent extends StatelessWidget {
  const DashboardContent(
      {super.key,
      required this.data,
      required this.onAddWeight,
      this.onOpenHealth,
      this.onOpenTasks,
      this.trend,
      this.onRefresh});
  final DashboardModel data;
  final VoidCallback onAddWeight;
  final VoidCallback? onOpenHealth, onOpenTasks;
  final WeightTrendModel? trend;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final pending =
        data.keyTasks.where((task) => task.status == 'pending').firstOrNull;
    final finished = data.keyTasks.isNotEmpty &&
        data.keyTasks.every((task) => task.isCompleted);
    // Bounded summary (at most six tasks), not an unbounded activity feed.
    final content = SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: AppSpacing.pageInsets,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          RootPageHeader(
              title: '今天',
              subtitle: '${AppFormat.date(data.date)} · 按自己的节奏，做好下一件事。'),
          InsightBlock(
              title: '今日重点',
              prominent: true,
              message: pending != null
                  ? '下一项：${pending.title}'
                  : finished
                      ? '今天的任务已完成，留一点时间恢复。'
                      : '先看看今天的记录，再安排下一件事。',
              action: pending != null && onOpenTasks != null
                  ? FilledButton(
                      onPressed: onOpenTasks, child: const Text('查看今日任务'))
                  : null),
          AppSection(
              title: '关键数据',
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MetricHero(
                        label: '今日体重',
                        value: data.todayWeightKg == null
                            ? '尚未记录'
                            : AppFormat.number(data.todayWeightKg!,
                                decimals: 1),
                        unit: data.todayWeightKg == null ? '' : 'kg'),
                    const SizedBox(height: 8),
                    Text(
                        '7 日均值 ${_kg(data.average7dKg)} · 周变化 ${_signedKg(data.weekChangeKg)}',
                        style: AppTypography.caption
                            .copyWith(color: colors.secondaryText)),
                    const SizedBox(height: 8),
                    TextButton.icon(
                        onPressed: onAddWeight,
                        icon: const Icon(Icons.add, size: 20),
                        label: const Text('晨重')),
                    LayoutBuilder(builder: (context, bounds) {
                      final metrics = [
                        ProgressMetric(
                            label: '热量',
                            value: '${data.caloriesConsumed}',
                            amount: data.caloriesConsumed.toDouble(),
                            target: data.caloriesTarget?.toDouble(),
                            unit: 'kcal'),
                        ProgressMetric(
                            label: '蛋白质',
                            unit: 'g',
                            value: '${data.proteinG.toStringAsFixed(0)} g',
                            amount: data.proteinG,
                            target: data.proteinTargetG),
                      ];
                      return MediaQuery.textScalerOf(context).scale(17) > 25 ||
                              bounds.maxWidth < 300
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: metrics)
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                  Expanded(child: metrics[0]),
                                  const SizedBox(width: 24),
                                  Expanded(child: metrics[1])
                                ]);
                    }),
                    MetricRow(
                        label: '步数',
                        value: data.steps == null
                            ? '暂无数据'
                            : '${AppFormat.number(data.steps!, grouped: true)} 步',
                        detail: data.stepsTarget > 0
                            ? '目标 ${AppFormat.number(data.stepsTarget, grouped: true)} 步'
                            : '目标待设置'),
                    ListRow(
                        title: '训练',
                        subtitle:
                            data.trainingCompleted ? '今日训练已完成' : '今日尚未标记完成',
                        icon: Icons.fitness_center_outlined),
                    if (trend case final value?)
                      TrendIndicator(
                          label: value.direction == 'insufficient_data'
                              ? '体重趋势 · 数据不足'
                              : value.plateau
                                  ? '体重趋势 · 暂时停滞'
                                  : '体重趋势 · ${_trendLabel(value.direction)}',
                          note: value.note),
                    ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: EdgeInsets.zero,
                        title: const Text('其他今日记录'),
                        children: [
                          MetricRow(
                              label: '碳水',
                              value: '${AppFormat.number(data.carbsG)} g',
                              detail: _target(data.carbsTargetG)),
                          MetricRow(
                              label: '脂肪',
                              value: '${AppFormat.number(data.fatG)} g',
                              detail: _target(data.fatTargetG)),
                          MetricRow(
                              label: '膳食纤维',
                              value: '${AppFormat.number(data.fiberG)} g',
                              detail: _target(data.fiberTargetG)),
                          MetricRow(
                              label: '饮水',
                              value: '${data.waterMl} ml',
                              detail: '今日累计'),
                        ]),
                  ])),
          if (data.keyTasks.isNotEmpty)
            AppSection(
                title: '今日任务',
                action: TextButton(
                    key: const Key('open-all-tasks'),
                    onPressed: onOpenTasks,
                    child: const Text('全部任务')),
                child: Column(children: [
                  for (final task in data.keyTasks.take(6))
                    TaskRow(title: task.title, status: task.status)
                ])),
          const SizedBox(height: 24),
          InsightBlock(title: '下一步', message: data.aiNextAction),
          AppSection(
              title: '长期健康',
              child: ListRow(
                  title: '健康档案与体检',
                  subtitle: '查看上次体检、指标趋势与证据问答',
                  icon: Icons.biotech_outlined,
                  onTap: onOpenHealth)),
        ]));
    return onRefresh == null
        ? content
        : RefreshIndicator(onRefresh: onRefresh!, child: content);
  }

  static String _target(double? value) =>
      value == null || value <= 0 ? '目标待设置' : '目标 ${AppFormat.number(value)} g';
  static String _kg(double? value) =>
      value == null ? '暂无数据' : '${value.toStringAsFixed(1)} kg';
  static String _signedKg(double? value) => value == null
      ? '暂无数据'
      : '${value > 0 ? '+' : ''}${value.toStringAsFixed(1)} kg';
  static String _trendLabel(String value) =>
      switch (value) { 'down' => '下降中', 'up' => '上升中', _ => '相对稳定' };
}
