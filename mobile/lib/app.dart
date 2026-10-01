import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'features/auth/presentation/auth_controller.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/dashboard/presentation/dashboard_screen.dart';
import 'core/privacy/privacy_lock.dart';

class HealthOsApp extends ConsumerStatefulWidget {
  const HealthOsApp({super.key});

  @override
  ConsumerState<HealthOsApp> createState() => _HealthOsAppState();
}

class _HealthOsAppState extends ConsumerState<HealthOsApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = ref.read(privacyLockControllerProvider.notifier);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      controller.onPaused();
    } else if (state == AppLifecycleState.resumed) {
      controller.onResumed();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    return MaterialApp(
      title: '健康 OS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      home: auth.when(
        loading: () => const _LaunchScreen(),
        error: (error, stack) => LoginScreen(initialError: error.toString()),
        data: (state) => state.isAuthenticated
            ? const PrivacyGate(child: DashboardScreen())
            : const LoginScreen(),
      ),
    );
  }
}

class _LaunchScreen extends StatelessWidget {
  const _LaunchScreen();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}
