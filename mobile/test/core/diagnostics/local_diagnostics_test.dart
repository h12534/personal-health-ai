import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_health_os/core/diagnostics/local_diagnostics.dart';

void main() {
  test('local diagnostics export contains only controlled fields', () async {
    final directory =
        await Directory.systemTemp.createTemp('health-os-diagnostics-');
    final log = LocalDiagnosticsLog(directoryResolver: () async => directory);
    try {
      await log.record(
        event: 'app error',
        source: 'platform callback',
        code: 'StateError',
      );
      final exported = await log.export({
        'app_version': '0.1.0-beta.1',
        'api_environment': 'staging',
      });
      final decoded = jsonDecode(exported) as Map<String, dynamic>;
      final events = decoded['events'] as List<dynamic>;
      expect(events, hasLength(1));
      expect((events.first as Map<String, dynamic>)['event'], 'app_error');
      expect(exported, isNot(contains('Bearer ')));
      expect(exported, isNot(contains('PRIVATE KEY')));
      expect(exported, isNot(contains(directory.path)));
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
