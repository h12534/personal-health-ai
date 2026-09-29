import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/local_database.dart';
import '../../../core/network/api_client.dart';

class AuthState {
  const AuthState({required this.isAuthenticated});

  final bool isAuthenticated;
}

final authControllerProvider = AsyncNotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

class AuthController extends AsyncNotifier<AuthState> {
  @override
  Future<AuthState> build() async {
    final hasSession = await ref.read(apiClientProvider).hasSession();
    return AuthState(isAuthenticated: hasSession);
  }

  Future<void> authenticate({
    required String email,
    required String password,
    required bool register,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref
          .read(apiClientProvider)
          .authenticate(email: email, password: password, register: register);
      return const AuthState(isAuthenticated: true);
    });
  }

  Future<void> logout() async {
    await ref.read(apiClientProvider).clearSession();
    await ref.read(localDatabaseProvider).clearPrivateData();
    state = const AsyncData(AuthState(isAuthenticated: false));
  }
}
