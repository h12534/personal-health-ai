import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../network/api_client.dart';

abstract interface class BiometricAuthenticator {
  Future<bool> isAvailable();
  Future<bool> authenticate(String reason);
}

class DeviceBiometricAuthenticator implements BiometricAuthenticator {
  DeviceBiometricAuthenticator({LocalAuthentication? authentication})
      : _authentication = authentication ?? LocalAuthentication();

  final LocalAuthentication _authentication;

  @override
  Future<bool> isAvailable() async {
    try {
      return await _authentication.isDeviceSupported() &&
          await _authentication.canCheckBiometrics;
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      return await _authentication.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } on LocalAuthException {
      return false;
    }
  }
}

class MockBiometricAuthenticator implements BiometricAuthenticator {
  MockBiometricAuthenticator({this.available = true, this.result = true});

  bool available;
  bool result;
  int authenticateCount = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> authenticate(String reason) async {
    authenticateCount += 1;
    return result;
  }
}

final biometricAuthenticatorProvider = Provider<BiometricAuthenticator>(
  (ref) => DeviceBiometricAuthenticator(),
);

class PrivacyLockState {
  const PrivacyLockState({
    required this.enabled,
    required this.unlocked,
    required this.available,
  });

  final bool enabled;
  final bool unlocked;
  final bool available;

  PrivacyLockState copyWith({bool? enabled, bool? unlocked, bool? available}) =>
      PrivacyLockState(
        enabled: enabled ?? this.enabled,
        unlocked: unlocked ?? this.unlocked,
        available: available ?? this.available,
      );
}

final privacyLockControllerProvider =
    AsyncNotifierProvider<PrivacyLockController, PrivacyLockState>(
  PrivacyLockController.new,
);

class PrivacyLockController extends AsyncNotifier<PrivacyLockState> {
  static const _key = 'health_os_privacy_lock_enabled';
  static const _gracePeriod = Duration(minutes: 2);
  DateTime? _backgroundedAt;

  @override
  Future<PrivacyLockState> build() async {
    final storage = ref.read(secureStorageProvider);
    final enabled = await storage.read(key: _key) == 'true';
    final available =
        await ref.read(biometricAuthenticatorProvider).isAvailable();
    return PrivacyLockState(
      enabled: enabled,
      unlocked: !enabled,
      available: available,
    );
  }

  Future<bool> setEnabled(bool enabled) async {
    final current = state.valueOrNull;
    if (current == null) return false;
    if (enabled && !current.available) return false;
    final authenticated = await ref
        .read(biometricAuthenticatorProvider)
        .authenticate(enabled ? '验证后开启健康数据隐私锁' : '验证后关闭健康数据隐私锁');
    if (!authenticated) return false;
    await ref
        .read(secureStorageProvider)
        .write(key: _key, value: enabled.toString());
    state = AsyncData(
      current.copyWith(enabled: enabled, unlocked: true),
    );
    return true;
  }

  Future<bool> unlock() async {
    final current = state.valueOrNull;
    if (current == null || !current.enabled) return true;
    final authenticated = await ref
        .read(biometricAuthenticatorProvider)
        .authenticate('验证身份以查看你的健康数据');
    if (authenticated) {
      state = AsyncData(current.copyWith(unlocked: true));
    }
    return authenticated;
  }

  void onPaused() {
    _backgroundedAt = DateTime.now();
  }

  void onResumed() {
    final current = state.valueOrNull;
    final backgroundedAt = _backgroundedAt;
    _backgroundedAt = null;
    if (current == null || !current.enabled || backgroundedAt == null) return;
    if (DateTime.now().difference(backgroundedAt) >= _gracePeriod) {
      state = AsyncData(current.copyWith(unlocked: false));
    }
  }
}

class PrivacyGate extends ConsumerWidget {
  const PrivacyGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lock = ref.watch(privacyLockControllerProvider);
    return lock.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => child,
      data: (value) {
        if (!value.enabled || value.unlocked) return child;
        return Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_outline, size: 52),
                    const SizedBox(height: 18),
                    Text(
                      '健康数据已锁定',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '使用 Face ID 或 Touch ID 解锁。登录 Token 仍保存在系统 Keychain。',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      key: const Key('privacy-unlock'),
                      onPressed: () => ref
                          .read(privacyLockControllerProvider.notifier)
                          .unlock(),
                      icon: const Icon(Icons.fingerprint),
                      label: const Text('解锁'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
