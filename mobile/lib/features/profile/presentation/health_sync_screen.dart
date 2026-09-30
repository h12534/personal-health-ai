import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/health/health_data_provider.dart';
import '../../../core/network/api_client.dart';
import '../../training/data/training_models.dart';

final healthDataProviderProvider = Provider<HealthDataProvider>((ref) {
  if (Platform.isIOS) return AppleHealthProvider();
  return const MockHealthDataProvider();
});

final healthPermissionsProvider =
    FutureProvider<List<HealthPermissionModel>>((ref) {
  return ref.watch(apiClientProvider).fetchHealthPermissions();
});

class HealthSyncController {
  const HealthSyncController(this.ref);

  final WidgetRef ref;

  Future<void> setEnabled(
    String dataType,
    HealthMetric metric,
    bool enabled,
  ) async {
    final api = ref.read(apiClientProvider);
    if (!enabled) {
      await api.setHealthPermission(
        dataType: dataType,
        enabled: false,
        authorizationStatus: 'not_requested',
      );
      ref.invalidate(healthPermissionsProvider);
      return;
    }
    final provider = ref.read(healthDataProviderProvider);
    final result = await provider.requestAuthorization(metric);
    final status = switch (result) {
      HealthAuthorization.requested => 'unknown',
      HealthAuthorization.denied => 'denied',
      HealthAuthorization.unavailable => 'unavailable',
      HealthAuthorization.notRequested => 'not_requested',
    };
    await api.setHealthPermission(
      dataType: dataType,
      enabled: result == HealthAuthorization.requested,
      authorizationStatus: status,
    );
    if (result == HealthAuthorization.requested) {
      await _sync(metric);
    }
    ref.invalidate(healthPermissionsProvider);
  }

  Future<void> _sync(HealthMetric metric) async {
    final now = DateTime.now();
    final from = metric == HealthMetric.sleep
        ? now.subtract(const Duration(days: 2))
        : DateTime(now.year, now.month, now.day);
    final snapshot = await ref.read(healthDataProviderProvider).read(
      from: from,
      to: now,
      metrics: {metric},
    );
    if (snapshot == null) return;
    final api = ref.read(apiClientProvider);
    final day = _date(now);
    if (metric == HealthMetric.steps && snapshot.steps != null) {
      await api.uploadHealthSummary({
        'provider': snapshot.source,
        'data_type': 'steps',
        'source_record_id': '${snapshot.source}-steps-$day',
        'recorded_date': day,
        'steps': snapshot.steps,
      });
    }
    if (metric == HealthMetric.restingHeartRate &&
        snapshot.restingHeartRate != null) {
      await api.uploadHealthSummary({
        'provider': snapshot.source,
        'data_type': 'resting_heart_rate',
        'source_record_id': '${snapshot.source}-rhr-$day',
        'recorded_date': day,
        'resting_heart_rate': snapshot.restingHeartRate,
      });
    }
    if (metric == HealthMetric.sleep) {
      for (final segment in snapshot.sleep) {
        await api.uploadHealthSummary({
          'provider': snapshot.source,
          'data_type': 'sleep',
          'source_record_id': segment.id,
          'sleep_start': segment.start.toUtc().toIso8601String(),
          'sleep_end': segment.end.toUtc().toIso8601String(),
          'sleep_stages': [
            {
              'stage': segment.stage,
              'start': segment.start.toUtc().toIso8601String(),
              'end': segment.end.toUtc().toIso8601String(),
            },
          ],
        });
      }
    }
    if (metric == HealthMetric.workouts) {
      for (final workout in snapshot.workouts) {
        await api.uploadHealthSummary({
          'provider': snapshot.source,
          'data_type': 'workouts',
          'source_record_id': workout.id,
          'workout_start': workout.start.toUtc().toIso8601String(),
          'workout_end': workout.end.toUtc().toIso8601String(),
          'workout_type': workout.activity,
        });
      }
    }
  }

  static String _date(DateTime value) =>
      value.toIso8601String().substring(0, 10);
}

class HealthSyncScreen extends ConsumerWidget {
  const HealthSyncScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissions = ref.watch(healthPermissionsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('健康同步')),
      body: permissions.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: FilledButton.tonal(
            onPressed: () => ref.invalidate(healthPermissionsProvider),
            child: const Text('重新加载'),
          ),
        ),
        data: (values) {
          final byType = {for (final value in values) value.dataType: value};
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.favorite, color: Colors.red),
                          const SizedBox(width: 10),
                          Text(
                            Platform.isIOS ? 'Apple Health' : '健康数据模拟器',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '每项数据只在你开启时单独申请。服务器只接收每日摘要或睡眠/训练段，'
                        '不会上传全部原始 HealthKit 样本。',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _HealthSwitch(
                title: '步数',
                subtitle: '优先使用 HealthKit 聚合结果，避免多设备重复累加。',
                value: byType['steps']?.enabled ?? false,
                onChanged: (value) => _change(
                  context,
                  ref,
                  'steps',
                  HealthMetric.steps,
                  value,
                ),
              ),
              _HealthSwitch(
                title: '睡眠',
                subtitle: '用于恢复提示；不对单晚睡眠阶段作医学解读。',
                value: byType['sleep']?.enabled ?? false,
                onChanged: (value) => _change(
                  context,
                  ref,
                  'sleep',
                  HealthMetric.sleep,
                  value,
                ),
              ),
              _HealthSwitch(
                title: '静息心率',
                subtitle: '只与 14–28 天个人基线比较，不用于诊断。',
                value: byType['resting_heart_rate']?.enabled ?? false,
                onChanged: (value) => _change(
                  context,
                  ref,
                  'resting_heart_rate',
                  HealthMetric.restingHeartRate,
                  value,
                ),
              ),
              _HealthSwitch(
                title: '训练',
                subtitle: '读取 Apple Health 中的训练摘要，不写回健康数据。',
                value: byType['workouts']?.enabled ?? false,
                onChanged: (value) => _change(
                  context,
                  ref,
                  'workouts',
                  HealthMetric.workouts,
                  value,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'iOS 不会向 App 透露读取权限的精确状态。开关表示你已在本 App 开启同步；'
                '实际权限可在“设置 → 健康 → 数据访问与设备”中管理。',
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _change(
    BuildContext context,
    WidgetRef ref,
    String dataType,
    HealthMetric metric,
    bool enabled,
  ) async {
    if (enabled) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('开启这项健康同步？'),
          content: const Text(
            '下一步只会请求当前这一项 Apple Health 读取权限。你可以随时关闭同步，'
            '关闭后 App 不再读取或上传该项新数据。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('暂不开启'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('继续'),
            ),
          ],
        ),
      );
      if (accepted != true) return;
    }
    try {
      await HealthSyncController(ref).setEnabled(
        dataType,
        metric,
        enabled,
      );
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('健康同步设置失败，请稍后重试。')),
        );
      }
    }
  }
}

class _HealthSwitch extends StatelessWidget {
  const _HealthSwitch({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Card(
        child: SwitchListTile.adaptive(
          value: value,
          title: Text(title),
          subtitle: Text(subtitle),
          onChanged: onChanged,
        ),
      );
}
