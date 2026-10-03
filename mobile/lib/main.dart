import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/diagnostics/local_diagnostics.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    unawaited(
      localCrashReporter.recordFatal(
        details.exception,
        details.stack ?? StackTrace.current,
        'flutter',
      ),
    );
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    unawaited(localCrashReporter.recordFatal(error, stack, 'platform'));
    return true;
  };
  WidgetsBinding.instance.addObserver(_BetaLifecycleObserver());
  runApp(const ProviderScope(child: HealthOsApp()));
}

class _BetaLifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(localDiagnostics.record(
      event: 'app_lifecycle',
      source: 'flutter',
      code: state.name,
    ));
  }
}
