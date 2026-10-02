import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_health_os/core/network/api_client.dart';

class MemoryTokenStore implements TokenStore {
  final values = <String, String>{};
  int clearCount = 0;

  @override
  Future<void> clear() async {
    clearCount += 1;
    values.clear();
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

void main() {
  test('401 refresh rotates tokens and retries the request once', () async {
    final store = MemoryTokenStore()
      ..values['health_os_access_token'] = 'expired-access'
      ..values['health_os_refresh_token'] = 'refresh-1';
    var protectedCalls = 0;
    var refreshCalls = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      await utf8.decoder.bind(request).join();
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path == '/api/v1/auth/refresh') {
        refreshCalls += 1;
        request.response.write(jsonEncode({
          'data': {
            'access_token': 'access-2',
            'refresh_token': 'refresh-2',
          },
        }));
      } else if (request.uri.path == '/api/v1/supervision/push-device') {
        protectedCalls += 1;
        if (request.headers.value('authorization') != 'Bearer access-2') {
          request.response.statusCode = 401;
          request.response.write(jsonEncode({
            'error': {'code': 'invalid_access_token', 'message': 'expired'},
          }));
        } else {
          request.response.write(jsonEncode({
            'data': {'id': 'device-1', 'status': 'active'},
          }));
        }
      } else {
        request.response.statusCode = 404;
      }
      await request.response.close();
    });
    final client = ApiClient(
      Dio(BaseOptions(baseUrl: 'http://127.0.0.1:${server.port}/api/v1')),
      store,
    );
    try {
      await client.registerPushDevice(
        deviceId: 'test-iphone',
        platform: 'ios',
        token: 'test-device-token',
      );
      expect(protectedCalls, 2);
      expect(refreshCalls, 1);
      expect(store.values['health_os_access_token'], 'access-2');
      expect(store.values['health_os_refresh_token'], 'refresh-2');
      expect(store.clearCount, 0);
    } finally {
      await server.close(force: true);
    }
  });

  test('invalid refresh clears tokens without an infinite 401 retry', () async {
    final store = MemoryTokenStore()
      ..values['health_os_access_token'] = 'expired-access'
      ..values['health_os_refresh_token'] = 'invalid-refresh';
    var protectedCalls = 0;
    var refreshCalls = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      await request.drain<void>();
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path == '/api/v1/auth/refresh') {
        refreshCalls += 1;
      } else {
        protectedCalls += 1;
      }
      request.response.statusCode = 401;
      request.response.write(jsonEncode({
        'error': {'code': 'invalid_refresh_token', 'message': 'invalid'},
      }));
      await request.response.close();
    });
    final client = ApiClient(
      Dio(BaseOptions(baseUrl: 'http://127.0.0.1:${server.port}/api/v1')),
      store,
    );
    try {
      await expectLater(
        client.registerPushDevice(
          deviceId: 'test-iphone',
          platform: 'ios',
          token: 'test-device-token',
        ),
        throwsA(isA<Exception>()),
      );
      expect(protectedCalls, 1);
      expect(refreshCalls, 1);
      expect(store.clearCount, 1);
      expect(store.values, isEmpty);
    } finally {
      await server.close(force: true);
    }
  });

  test('a 401 after successful refresh clears the rotated session', () async {
    final store = MemoryTokenStore()
      ..values['health_os_access_token'] = 'expired-access'
      ..values['health_os_refresh_token'] = 'refresh-1';
    var protectedCalls = 0;
    var refreshCalls = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      await request.drain<void>();
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path == '/api/v1/auth/refresh') {
        refreshCalls += 1;
        request.response.write(jsonEncode({
          'data': {
            'access_token': 'still-invalid-access',
            'refresh_token': 'refresh-2',
          },
        }));
      } else {
        protectedCalls += 1;
        request.response.statusCode = 401;
        request.response.write(jsonEncode({
          'error': {'code': 'invalid_access_token', 'message': 'revoked'},
        }));
      }
      await request.response.close();
    });
    final client = ApiClient(
      Dio(BaseOptions(baseUrl: 'http://127.0.0.1:${server.port}/api/v1')),
      store,
    );
    try {
      await expectLater(
        client.registerPushDevice(
          deviceId: 'test-iphone',
          platform: 'ios',
          token: 'test-device-token',
        ),
        throwsA(isA<Exception>()),
      );
      expect(protectedCalls, 2);
      expect(refreshCalls, 1);
      expect(store.clearCount, 1);
      expect(store.values, isEmpty);
    } finally {
      await server.close(force: true);
    }
  });
}
