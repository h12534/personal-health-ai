import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'core/widgets/app_components.dart';
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
  // View continuity only. AuthController remains the authority for sessions.
  bool _loginVisible = false;
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
      home: _home(auth),
    );
  }

  Widget _home(AsyncValue<AuthState> auth) {
    if (auth.isLoading) {
      return _loginVisible ? const LoginScreen() : const _LaunchScreen();
    }
    if (auth.hasError) {
      _loginVisible = true;
      return LoginScreen(initialError: auth.error);
    }
    if (auth.requireValue.isAuthenticated) {
      _loginVisible = false;
      return const PrivacyGate(child: DashboardScreen());
    }
    _loginVisible = true;
    return const LoginScreen();
  }
}

class _LaunchScreen extends StatelessWidget {
  const _LaunchScreen();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: SafeArea(child: LoadingState(label: '正在打开你的健康记录')));
}
