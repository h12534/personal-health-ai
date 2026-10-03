import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

typedef DiagnosticsDirectoryResolver = Future<Directory> Function();

final localDiagnostics = LocalDiagnosticsLog();
final localCrashReporter = LocalCrashReporter(localDiagnostics);
final localDiagnosticsProvider = Provider<LocalDiagnosticsLog>(
  (ref) => localDiagnostics,
);

abstract interface class CrashReporter {
  Future<void> recordFatal(Object error, StackTrace stack, String source);
}

class LocalCrashReporter implements CrashReporter {
  const LocalCrashReporter(this._log);

  final LocalDiagnosticsLog _log;

  @override
  Future<void> recordFatal(
    Object error,
    StackTrace stack,
    String source,
  ) =>
      _log.record(
        event: 'app_error',
        source: source,
        code: error.runtimeType.toString(),
      );
}

class LocalDiagnosticsLog {
  LocalDiagnosticsLog({DiagnosticsDirectoryResolver? directoryResolver})
      : _directoryResolver =
            directoryResolver ?? getApplicationSupportDirectory;

  final DiagnosticsDirectoryResolver _directoryResolver;
  static const _maximumBytes = 256 * 1024;

  Future<void> record({
    required String event,
    required String source,
    required String code,
    String? requestId,
    int? statusCode,
    int? durationMs,
  }) async {
    try {
      final file = await _file();
      if (await file.exists() && await file.length() > _maximumBytes) {
        await file.writeAsString('', flush: true);
      }
      final entry = {
        'at': DateTime.now().toUtc().toIso8601String(),
        'event': _safeToken(event),
        'source': _safeToken(source),
        'code': _safeToken(code),
        if (requestId != null &&
            RegExp(r'^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$')
                .hasMatch(requestId))
          'request_id': requestId,
        if (statusCode != null && statusCode >= 100 && statusCode <= 599)
          'status_code': statusCode,
        if (durationMs != null && durationMs >= 0) 'duration_ms': durationMs,
      };
      await file.writeAsString(
        '${jsonEncode(entry)}\n',
        mode: FileMode.append,
        flush: true,
      );
    } on Object {
      // Diagnostics must never cause another application failure.
    }
  }

  Future<List<Map<String, dynamic>>> read({int limit = 50}) async {
    try {
      final file = await _file();
      if (!await file.exists()) return const [];
      final lines = await file.readAsLines();
      return lines.reversed.take(limit).map((line) {
        final value = jsonDecode(line);
        return value is Map<String, dynamic>
            ? value
            : <String, dynamic>{'event': 'invalid_entry'};
      }).toList();
    } on Object {
      return const [];
    }
  }

  Future<String> export(Map<String, Object?> context) async =>
      const JsonEncoder.withIndent('  ').convert({
        'generated_at': DateTime.now().toUtc().toIso8601String(),
        'privacy':
            'No tokens, provider keys, health values, chats, or file paths are included.',
        'context': context,
        'events': await read(),
      });

  Future<File> _file() async {
    final root = await _directoryResolver();
    final directory = Directory(path.join(root.path, 'diagnostics'));
    await directory.create(recursive: true);
    return File(path.join(directory.path, 'beta-events.jsonl'));
  }

  static String _safeToken(String value) => value
      .replaceAll(RegExp(r'[^A-Za-z0-9_.:-]'), '_')
      .substring(0, value.length > 120 ? 120 : value.length);
}
