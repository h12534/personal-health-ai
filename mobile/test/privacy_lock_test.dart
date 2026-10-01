import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_health_os/core/network/api_client.dart';
import 'package:personal_health_os/core/privacy/privacy_lock.dart';

void main() {
  test('Face ID flow uses mock authenticator and unlocks the app', () async {
    final storage = _MemorySecureStorage({
      'health_os_privacy_lock_enabled': 'true',
    });
    final biometrics = MockBiometricAuthenticator();
    final container = ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(storage),
        biometricAuthenticatorProvider.overrideWithValue(biometrics),
      ],
    );
    addTearDown(container.dispose);

    final initial = await container.read(privacyLockControllerProvider.future);
    expect(initial.enabled, isTrue);
    expect(initial.unlocked, isFalse);
    final unlocked =
        await container.read(privacyLockControllerProvider.notifier).unlock();
    expect(unlocked, isTrue);
    expect(biometrics.authenticateCount, 1);
    expect(
      container.read(privacyLockControllerProvider).valueOrNull?.unlocked,
      isTrue,
    );
  });

  test('privacy lock remains disabled when biometrics fail', () async {
    final storage = _MemorySecureStorage();
    final biometrics = MockBiometricAuthenticator(result: false);
    final container = ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(storage),
        biometricAuthenticatorProvider.overrideWithValue(biometrics),
      ],
    );
    addTearDown(container.dispose);
    await container.read(privacyLockControllerProvider.future);
    final enabled = await container
        .read(privacyLockControllerProvider.notifier)
        .setEnabled(true);
    expect(enabled, isFalse);
    expect(storage.values['health_os_privacy_lock_enabled'], isNull);
  });
}

class _MemorySecureStorage extends FlutterSecureStorage {
  _MemorySecureStorage([Map<String, String>? initial]) : values = {...?initial};

  final Map<String, String> values;

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      values[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }
}
