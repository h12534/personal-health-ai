import 'package:flutter_test/flutter_test.dart';
import 'package:personal_health_os/core/health/health_data_provider.dart';

void main() {
  test('uses Apple data before the manual fallback when available', () async {
    final apple = _StubProvider(
      source: 'apple_health',
      snapshot: const HealthDataSnapshot(
        source: 'apple_health',
        steps: 6400,
      ),
    );
    final manual = _StubProvider(
      source: 'manual',
      snapshot: const HealthDataSnapshot(source: 'manual', steps: 1000),
    );
    final provider = PrioritizedHealthDataProvider([apple, manual]);

    final result = await provider.read(
      from: DateTime(2026, 1, 1),
      to: DateTime(2026, 1, 2),
      metrics: {HealthMetric.steps},
    );

    expect(result?.source, 'apple_health');
    expect(apple.readCount, 1);
    expect(manual.readCount, 0);
  });

  test('falls back to manual data when Apple Health is unavailable', () async {
    final apple = _StubProvider(source: 'apple_health', available: false);
    final manual = _StubProvider(
      source: 'manual',
      snapshot: const HealthDataSnapshot(source: 'manual', weightKg: 72.4),
    );
    final provider = PrioritizedHealthDataProvider([apple, manual]);

    final result = await provider.read(
      from: DateTime(2026, 1, 1),
      to: DateTime(2026, 1, 2),
      metrics: {HealthMetric.steps},
    );

    expect(result?.source, 'manual');
    expect(apple.readCount, 0);
    expect(manual.readCount, 1);
  });
}

class _StubProvider implements HealthDataProvider {
  _StubProvider({
    required this.source,
    this.available = true,
    this.snapshot,
  });

  @override
  final String source;
  final bool available;
  final HealthDataSnapshot? snapshot;
  int readCount = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  bool supports(HealthMetric metric) => true;

  @override
  Future<HealthAuthorization> requestAuthorization(HealthMetric metric) async =>
      HealthAuthorization.requested;

  @override
  Future<HealthDataSnapshot?> read({
    required DateTime from,
    required DateTime to,
    required Set<HealthMetric> metrics,
  }) async {
    readCount += 1;
    return snapshot;
  }
}
