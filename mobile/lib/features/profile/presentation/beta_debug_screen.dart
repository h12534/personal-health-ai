import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/database/local_database.dart';
import '../../../core/diagnostics/local_diagnostics.dart';
import '../../../core/network/api_client.dart';
import '../../supervision/presentation/supervision_controller.dart';
import 'health_sync_screen.dart';

final betaDebugSnapshotProvider =
    FutureProvider<BetaDebugSnapshot>((ref) async {
  final api = ref.watch(apiClientProvider);
  final database = ref.watch(localDatabaseProvider);
  final notifications = ref.watch(notificationCoordinatorProvider);

  final health = await api.checkServerHealth();
  final outboxCount = await database.pendingOutboxCount();
  String notificationStatus;
  try {
    notificationStatus = await notifications.permissionStatus();
  } on Object {
    notificationStatus = 'unknown';
  }

  var healthKitState = 'unavailable';
  var providerStatus = <String, String>{};
  DateTime? lastSync;
  try {
    final nativeAvailable =
        await ref.read(healthDataProviderProvider).isAvailable();
    final permissions = await api.fetchHealthPermissions();
    final enabled = permissions.where((item) => item.enabled).length;
    healthKitState = '${nativeAvailable ? 'available' : 'unavailable'}; '
        '$enabled/${permissions.length} sync switches enabled; '
        'Apple read authorization is not disclosed';
    final sync = await api.fetchHealthSyncStatus();
    final values = sync
        .map(
            (item) => DateTime.tryParse(item['last_sync_at']?.toString() ?? ''))
        .whereType<DateTime>()
        .toList()
      ..sort();
    if (values.isNotEmpty) lastSync = values.last.toUtc();
  } on Object {
    healthKitState = 'server state unavailable';
  }
  try {
    providerStatus = await api.fetchBetaProviderStatus();
  } on Object {
    // Offline / older servers are explicit unknown, never reported as healthy.
  }

  return BetaDebugSnapshot(
    health: health,
    pendingOutboxCount: outboxCount,
    notificationStatus: notificationStatus,
    healthKitState: healthKitState,
    lastSync: lastSync,
    apiHost: api.apiHost,
    providerStatus: providerStatus,
    requestId: api.lastRequestId,
  );
});

class BetaDebugSnapshot {
  const BetaDebugSnapshot({
    required this.health,
    required this.pendingOutboxCount,
    required this.notificationStatus,
    required this.healthKitState,
    this.lastSync,
    this.apiHost = '',
    this.providerStatus = const {},
    this.requestId,
  });

  final ServerHealthResult health;
  final int pendingOutboxCount;
  final String notificationStatus;
  final String healthKitState;
  final DateTime? lastSync;
  final String apiHost;
  final Map<String, String> providerStatus;
  final String? requestId;

  Map<String, Object?> toSafeJson() => {
        'app_version': AppConfig.appVersion,
        'build_number': AppConfig.buildNumber,
        'api_environment': AppConfig.apiEnvironment,
        'api_url_host': apiHost,
        'provider_status': providerStatus,
        'last_request_id': requestId,
        'last_sync': lastSync?.toIso8601String(),
        'healthkit_state': healthKitState,
        'notification_permission': notificationStatus,
        'pending_outbox_count': pendingOutboxCount,
        'last_server_health_check': health.checkedAt.toIso8601String(),
        'server_healthy': health.healthy,
        'server_latency_ms': health.latencyMs,
        'server_error_code': health.errorCode,
      };
}

class BetaDebugScreen extends ConsumerWidget {
  const BetaDebugScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(betaDebugSnapshotProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Beta 诊断'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: () => ref.invalidate(betaDebugSnapshotProvider),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: snapshot.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('诊断状态加载失败，请重试。')),
        data: (value) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _DiagnosticTile('App 版本', AppConfig.appVersion),
            _DiagnosticTile('Build', AppConfig.buildNumber),
            _DiagnosticTile('API 环境', AppConfig.apiEnvironment),
            _DiagnosticTile('API host', value.apiHost),
            _DiagnosticTile(
                'Provider 配置（非实测结果）',
                value.providerStatus.isEmpty
                    ? 'unknown'
                    : value.providerStatus.entries
                        .map((e) => '${e.key}: ${e.value}')
                        .join('\n')),
            _DiagnosticTile('最近 request_id', value.requestId ?? '尚无记录'),
            _DiagnosticTile('最近同步', _time(value.lastSync)),
            _DiagnosticTile('HealthKit', value.healthKitState),
            _DiagnosticTile('通知权限', value.notificationStatus),
            _DiagnosticTile('待同步 Outbox', '${value.pendingOutboxCount}'),
            _DiagnosticTile(
              '服务健康检查',
              '${value.health.healthy ? '正常' : '失败'} · '
                  '${value.health.latencyMs} ms · ${_time(value.health.checkedAt)}',
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('copy-beta-diagnostics'),
              onPressed: () => _copy(context, ref, value),
              icon: const Icon(Icons.copy_all_outlined),
              label: const Text('复制脱敏诊断'),
            ),
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                '诊断包不包含 Token、API Key、健康数值、聊天正文或私有文件路径。',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copy(
    BuildContext context,
    WidgetRef ref,
    BetaDebugSnapshot snapshot,
  ) async {
    final value =
        await ref.read(localDiagnosticsProvider).export(snapshot.toSafeJson());
    await Clipboard.setData(ClipboardData(text: value));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('脱敏诊断已复制')),
      );
    }
  }
}

class _DiagnosticTile extends StatelessWidget {
  const _DiagnosticTile(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          title: Text(label),
          subtitle: SelectableText(value),
        ),
      );
}

String _time(DateTime? value) => value == null
    ? '尚无记录'
    : value.toLocal().toIso8601String().replaceFirst('T', ' ').split('.').first;
