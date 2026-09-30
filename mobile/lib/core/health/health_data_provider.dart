class HealthDataSnapshot {
  const HealthDataSnapshot({
    required this.source,
    this.steps,
    this.activeEnergyKcal,
    this.weightKg,
  });

  final String source;
  final int? steps;
  final double? activeEnergyKcal;
  final double? weightKg;
}

abstract interface class HealthDataProvider {
  String get source;

  Future<bool> isAvailable();

  Future<HealthDataSnapshot?> read({
    required DateTime from,
    required DateTime to,
  });
}

/// Phase 5 seam for Apple's HealthKit. Native authorization and queries remain
/// disabled until the HealthKit capability and product consent flow land.
class AppleHealthProvider implements HealthDataProvider {
  @override
  String get source => 'apple_health';

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<HealthDataSnapshot?> read({
    required DateTime from,
    required DateTime to,
  }) async =>
      null;
}

typedef ManualHealthReader = Future<HealthDataSnapshot?> Function({
  required DateTime from,
  required DateTime to,
});

class ManualHealthProvider implements HealthDataProvider {
  const ManualHealthProvider(this._reader);

  final ManualHealthReader _reader;

  @override
  String get source => 'manual';

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<HealthDataSnapshot?> read({
    required DateTime from,
    required DateTime to,
  }) =>
      _reader(from: from, to: to);
}

/// Providers are queried in order. iPhone composition must pass
/// AppleHealthProvider before ManualHealthProvider.
class PrioritizedHealthDataProvider implements HealthDataProvider {
  const PrioritizedHealthDataProvider(this.providers);

  final List<HealthDataProvider> providers;

  @override
  String get source => 'prioritized';

  @override
  Future<bool> isAvailable() async {
    for (final provider in providers) {
      if (await provider.isAvailable()) return true;
    }
    return false;
  }

  @override
  Future<HealthDataSnapshot?> read({
    required DateTime from,
    required DateTime to,
  }) async {
    for (final provider in providers) {
      if (!await provider.isAvailable()) continue;
      final snapshot = await provider.read(from: from, to: to);
      if (snapshot != null) return snapshot;
    }
    return null;
  }
}
