import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_health_os/core/network/api_client.dart';
import 'package:personal_health_os/features/profile/presentation/beta_debug_screen.dart';

void main() {
  testWidgets(
      'Beta screen includes host, permission, sync and safe Provider status',
      (tester) async {
    final snapshot = BetaDebugSnapshot(
      health: ServerHealthResult(
          checkedAt: DateTime.utc(2026, 10, 4), latencyMs: 12, healthy: true),
      pendingOutboxCount: 2,
      notificationStatus: 'denied',
      healthKitState: 'available; read permission unknown',
      apiHost: 'health.owner.test',
      providerStatus: const {'coach': 'configured_not_verified'},
      requestId: '12345678-1234-1234-1234-123456789abc',
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        betaDebugSnapshotProvider.overrideWith((ref) async => snapshot)
      ],
      child: const MaterialApp(home: BetaDebugScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('App 版本'), findsOneWidget);
    expect(find.text('Build'), findsOneWidget);
    expect(find.text('API 环境'), findsOneWidget);
    expect(find.text('health.owner.test'), findsOneWidget);
    final json = snapshot.toSafeJson();
    expect(
        json.keys,
        containsAll([
          'app_version',
          'build_number',
          'api_environment',
          'api_url_host',
          'healthkit_state',
          'notification_permission',
          'last_sync',
          'pending_outbox_count',
          'last_server_health_check',
          'provider_status',
        ]));
    expect(json['provider_status'], {'coach': 'configured_not_verified'});
    expect(json.containsKey('token'), isFalse);
    expect(json.containsKey('api_key'), isFalse);
  });
}
