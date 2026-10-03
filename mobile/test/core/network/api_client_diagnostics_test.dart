import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_health_os/core/diagnostics/local_diagnostics.dart';
import 'package:personal_health_os/core/network/api_client.dart';

class _Tokens implements TokenStore {
  @override
  Future<void> clear() async {}
  @override
  Future<String?> read(String key) async => 'private-test-token';
  @override
  Future<void> write(String key, String value) async {}
}

void main() {
  test('request UUID correlates logs without URL, body or token leakage',
      () async {
    final directory = await Directory.systemTemp.createTemp('beta-http-test-');
    final log = LocalDiagnosticsLog(directoryResolver: () async => directory);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    String? requestId;
    server.listen((request) async {
      requestId = request.headers.value('X-Request-ID');
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'status': 'live'}));
      await request.response.close();
    });
    final api = ApiClient(
      Dio(BaseOptions(baseUrl: 'http://127.0.0.1:${server.port}/api/v1')),
      _Tokens(),
      diagnostics: log,
    );
    try {
      expect((await api.checkServerHealth()).healthy, isTrue);
      expect(requestId, matches(RegExp(r'^[0-9a-f-]{36}$')));
      expect(api.lastRequestId, requestId);
      expect(api.apiHost, '127.0.0.1');
      List<Map<String, dynamic>> events = [];
      for (var i = 0; i < 100 && events.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        events = await log.read();
      }
      expect(events.single['request_id'], requestId);
      expect(events.single['status_code'], 200);
      final exported = jsonEncode(events);
      expect(exported, isNot(contains('private-test-token')));
      expect(exported, isNot(contains('/health/live')));
      expect(exported, isNot(contains('127.0.0.1')));
    } finally {
      await server.close(force: true);
      await directory.delete(recursive: true);
    }
  });

  test('Provider status response cannot leak unexpected fields or values',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'data': {
          'coach': 'configured_not_verified',
          'vision': 'private-test-secret',
          'api_key': 'never-display',
        }
      }));
      await request.response.close();
    });
    final api = ApiClient(
      Dio(BaseOptions(baseUrl: 'http://127.0.0.1:${server.port}/api/v1')),
      _Tokens(),
    );
    try {
      expect(await api.fetchBetaProviderStatus(), {
        'coach': 'configured_not_verified',
        'vision': 'unknown',
      });
    } finally {
      await server.close(force: true);
    }
  });
}
