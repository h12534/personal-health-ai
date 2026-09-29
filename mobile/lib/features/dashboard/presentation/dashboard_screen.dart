import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/presentation/profile_screen.dart';
import '../../nutrition/presentation/nutrition_screen.dart';
import '../../coach/presentation/coach_screen.dart';
import '../../coach/presentation/coach_controller.dart';
import '../../coach/data/coach_models.dart';
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
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _index,
          children: [
            _DashboardTab(onAddWeight: _showWeightDialog),
            const NutritionScreen(),
            const _ComingSoon(title: '训练', icon: Icons.fitness_center_outlined),
            const CoachScreen(),
            const ProfileScreen(),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: '首页'),
          NavigationDestination(
            icon: Icon(Icons.restaurant_outlined),
            label: '饮食',
          ),
          NavigationDestination(
            icon: Icon(Icons.fitness_center_outlined),
            label: '训练',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            label: 'AI',
          ),
          NavigationDestination(icon: Icon(Icons.person_outline), label: '我的'),
        ],
      ),
    );
  }

  Future<void> _showWeightDialog() async {
    final controller = TextEditingController();
    final value = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('记录今日晨重'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: '体重', suffixText: 'kg'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final parsed = double.tryParse(controller.text.trim());
              if (parsed != null && parsed >= 20 && parsed <= 500) {
                Navigator.pop(context, parsed);
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || !mounted) return;
    try {
      await WeightController(ref).add(value);
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }
}

class _DashboardTab extends ConsumerWidget {
  const _DashboardTab({required this.onAddWeight});

  final VoidCallback onAddWeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(dashboardProvider);
    return dashboard.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(error.toString(), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: () => ref.invalidate(dashboardProvider),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
      data: (data) => DashboardContent(
        data: data,
        onAddWeight: onAddWeight,
        trend: ref.watch(weightTrendProvider).valueOrNull,
      ),
    );
  }
}

class DashboardContent extends StatelessWidget {
  const DashboardContent({
    super.key,
    required this.data,
    required this.onAddWeight,
    this.trend,
  });

  final DashboardModel data;
  final VoidCallback onAddWeight;
  final WeightTrendModel? trend;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return RefreshIndicator(
      onRefresh: () async {},
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
        children: [
          Text('今天', style: textTheme.headlineMedium),
          const SizedBox(height: 4),
          const Text('先做好下一件事，不追逐单日波动。'),
          const SizedBox(height: 20),
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('今日体重'),
                        const SizedBox(height: 4),
                        Text(
                          data.todayWeightKg == null
                              ? '尚未记录'
                              : '${data.todayWeightKg!.toStringAsFixed(1)} kg',
                          style: textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '7 日均值  ${_kg(data.average7dKg)}  ·  周变化 ${_signedKg(data.weekChangeKg)}',
                        ),
                      ],
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: onAddWeight,
                    icon: const Icon(Icons.add),
                    label: const Text('晨重'),
                  ),
                ],
              ),
            ),
          ),
          if (trend case final value?) ...[
            const SizedBox(height: 10),
            Card(
              child: ListTile(
                leading: Icon(
                  value.plateau
                      ? Icons.pause_circle_outline
                      : Icons.show_chart_outlined,
                ),
                title: Text(
                  value.direction == 'insufficient_data'
                      ? '体重趋势 · 数据不足'
                      : value.plateau
                          ? '体重趋势 · 暂时停滞'
                          : '体重趋势 · ${_trendLabel(value.direction)}',
                ),
                subtitle: Text(value.note),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.auto_awesome,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text('下一步', style: textTheme.titleMedium),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(data.aiNextAction),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.5,
            children: [
              _MetricCard(
                label: '热量',
                value: '${data.caloriesConsumed}',
                target: data.caloriesTarget == null
                    ? '目标待设置'
                    : '/ ${data.caloriesTarget} kcal',
                icon: Icons.local_fire_department_outlined,
              ),
              _MetricCard(
                label: '蛋白质',
                value: '${data.proteinG.toStringAsFixed(0)} g',
                target: data.proteinTargetG == null
                    ? '目标待设置'
                    : '/ ${data.proteinTargetG!.toStringAsFixed(0)} g',
                icon: Icons.egg_outlined,
              ),
              _MetricCard(
                label: '碳水',
                value: '${data.carbsG.toStringAsFixed(0)} g',
                target: data.carbsTargetG == null
                    ? '今日累计'
                    : '/ ${data.carbsTargetG!.toStringAsFixed(0)} g',
                icon: Icons.rice_bowl_outlined,
              ),
              _MetricCard(
                label: '脂肪',
                value: '${data.fatG.toStringAsFixed(0)} g',
                target: data.fatTargetG == null
                    ? '今日累计'
                    : '/ ${data.fatTargetG!.toStringAsFixed(0)} g',
                icon: Icons.opacity_outlined,
              ),
              _MetricCard(
                label: '膳食纤维',
                value: '${data.fiberG.toStringAsFixed(0)} g',
                target: data.fiberTargetG == null
                    ? '目标待设置'
                    : '/ ${data.fiberTargetG!.toStringAsFixed(0)} g',
                icon: Icons.eco_outlined,
              ),
              _MetricCard(
                label: '步数',
                value: '${data.steps}',
                target: '/ ${data.stepsTarget}',
                icon: Icons.directions_walk_outlined,
              ),
              _MetricCard(
                label: '饮水',
                value: '${data.waterMl} ml',
                target: '今天',
                icon: Icons.water_drop_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _kg(double? value) =>
      value == null ? '--' : '${value.toStringAsFixed(1)} kg';

  static String _signedKg(double? value) {
    if (value == null) return '--';
    final prefix = value > 0 ? '+' : '';
    return '$prefix${value.toStringAsFixed(1)} kg';
  }

  static String _trendLabel(String value) => switch (value) {
        'down' => '下降中',
        'up' => '上升中',
        _ => '相对稳定',
      };
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.target,
    required this.icon,
  });

  final String label;
  final String value;
  final String target;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(icon, size: 20),
                  const SizedBox(width: 6),
                  Text(label),
                ],
              ),
              Text(value, style: Theme.of(context).textTheme.titleLarge),
              Text(target, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      );
}

class _ComingSoon extends StatelessWidget {
  const _ComingSoon({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              '$title模块将在下一阶段接入',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      );
}
