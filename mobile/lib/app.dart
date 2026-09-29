import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'features/auth/presentation/auth_controller.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/dashboard/presentation/dashboard_screen.dart';

class HealthOsApp extends ConsumerWidget {
  const HealthOsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    return MaterialApp(
      title: '健康 OS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: auth.when(
        loading: () => const _LaunchScreen(),
        error: (error, stack) => LoginScreen(initialError: error.toString()),
        data: (state) => state.isAuthenticated
            ? const DashboardScreen()
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
