import 'dart:io';

import 'package:health/health.dart';
import 'package:flutter/services.dart';

import '../config/app_config.dart';

Future<bool> personalHealthKitCapability() async {
  try {
    return await const MethodChannel('personal_health_os/capabilities')
            .invokeMethod<bool>('healthKitAvailable') ??
        false;
  } on Object {
    return false;
  }
}

enum HealthMetric {
  steps,
  walkingRunningDistance,
  activeEnergyBurned,
  restingHeartRate,
  sleep,
  workouts,
}

enum HealthAuthorization {
  notRequested,
  requested,
  denied,
  unavailable,
}

class HealthSleepSegment {
  const HealthSleepSegment({
    required this.id,
    required this.stage,
    required this.start,
    required this.end,
  });

  final String id;
  final String stage;
  final DateTime start;
  final DateTime end;
}

class HealthWorkoutSummary {
  const HealthWorkoutSummary({
    required this.id,
    required this.start,
    required this.end,
    required this.activity,
  });

  final String id;
  final DateTime start;
  final DateTime end;
  final String activity;
}

class HealthDataSnapshot {
  const HealthDataSnapshot({
    required this.source,
    this.steps,
    this.walkingRunningDistanceKm,
    this.activeEnergyKcal,
    this.restingHeartRate,
    this.weightKg,
    this.sleep = const [],
    this.workouts = const [],
  });

  final String source;
  final int? steps;
  final double? walkingRunningDistanceKm;
  final double? activeEnergyKcal;
  final int? restingHeartRate;
  final double? weightKg;
  final List<HealthSleepSegment> sleep;
  final List<HealthWorkoutSummary> workouts;

  bool get hasData =>
      steps != null ||
      walkingRunningDistanceKm != null ||
      activeEnergyKcal != null ||
      restingHeartRate != null ||
      weightKg != null ||
      sleep.isNotEmpty ||
      workouts.isNotEmpty;
}

abstract interface class HealthDataProvider {
  String get source;

  Future<bool> isAvailable();

  bool supports(HealthMetric metric);

  Future<HealthAuthorization> requestAuthorization(HealthMetric metric);

  Future<HealthDataSnapshot?> read({
    required DateTime from,
    required DateTime to,
    required Set<HealthMetric> metrics,
  });
}

class AppleHealthProvider implements HealthDataProvider {
  AppleHealthProvider({
    Health? health,
    Future<bool> Function()? capabilityProbe,
    bool? isIOS,
  })  : _health = health ?? Health(),
        _capabilityProbe = capabilityProbe ??
            (AppConfig.isPersonalSideload ? personalHealthKitCapability : null),
        _isIOS = isIOS ?? Platform.isIOS;

  final Health _health;
  final Future<bool> Function()? _capabilityProbe;
  final bool _isIOS;
  bool _configured = false;

  @override
  String get source => 'healthkit';

  @override
  Future<bool> isAvailable() async {
    if (!_isIOS || AppConfig.appleHealthDisabled) return false;
    try {
      if (_capabilityProbe != null && !await _capabilityProbe()) return false;
      await _configure();
      return _health.isDataTypeAvailable(HealthDataType.STEPS);
    } on Object {
      return false;
    }
  }

  @override
  bool supports(HealthMetric metric) {
    if (!_isIOS || AppConfig.appleHealthDisabled) return false;
    return _types(metric).every(_health.isDataTypeAvailable);
  }

  @override
  Future<HealthAuthorization> requestAuthorization(HealthMetric metric) async {
    if (!await isAvailable() || !supports(metric)) {
      return HealthAuthorization.unavailable;
    }
    try {
      final types = _types(metric);
      final shown = await _health.requestAuthorization(
        types,
        permissions: List.filled(types.length, HealthDataAccess.READ),
      );
      // Apple intentionally does not disclose read authorization. A successful
      // request means only that the sheet completed without an API error.
      return shown ? HealthAuthorization.requested : HealthAuthorization.denied;
    } on Object {
      return HealthAuthorization.denied;
    }
  }

  @override
  Future<HealthDataSnapshot?> read({
    required DateTime from,
    required DateTime to,
    required Set<HealthMetric> metrics,
  }) async {
    if (!await isAvailable()) return null;
    int? steps;
    double? distanceKm;
    double? activeEnergy;
    int? restingHeartRate;
    var sleep = <HealthSleepSegment>[];
    var workouts = <HealthWorkoutSummary>[];
    try {
      if (metrics.contains(HealthMetric.steps)) {
        // Uses HealthKit's aggregate step query instead of summing samples from
        // iPhone, Apple Watch, and third-party sources.
        steps = await _health.getTotalStepsInInterval(from, to);
      }
      final queryTypes = <HealthDataType>[
        if (metrics.contains(HealthMetric.walkingRunningDistance))
          HealthDataType.DISTANCE_WALKING_RUNNING,
        if (metrics.contains(HealthMetric.activeEnergyBurned))
          HealthDataType.ACTIVE_ENERGY_BURNED,
        if (metrics.contains(HealthMetric.restingHeartRate))
          HealthDataType.RESTING_HEART_RATE,
        if (metrics.contains(HealthMetric.sleep)) ..._types(HealthMetric.sleep),
        if (metrics.contains(HealthMetric.workouts)) HealthDataType.WORKOUT,
      ];
      if (queryTypes.isNotEmpty) {
        final points = await _health.getHealthDataFromTypes(
          types: queryTypes,
          startTime: from,
          endTime: to,
        );
        final unique = _health.removeDuplicates(points);
        distanceKm = _sumNumeric(
          unique,
          HealthDataType.DISTANCE_WALKING_RUNNING,
        );
        if (distanceKm != null) distanceKm /= 1000;
        activeEnergy = _sumNumeric(
          unique,
          HealthDataType.ACTIVE_ENERGY_BURNED,
        );
        restingHeartRate = _latestNumeric(
          unique,
          HealthDataType.RESTING_HEART_RATE,
        )?.round();
        sleep = unique
            .where((point) => _sleepTypes.contains(point.type))
            .map(
              (point) => HealthSleepSegment(
                id: point.uuid,
                stage: _sleepStage(point.type),
                start: point.dateFrom,
                end: point.dateTo,
              ),
            )
            .toList()
          ..sort((a, b) => a.start.compareTo(b.start));
        workouts = unique
            .where((point) => point.type == HealthDataType.WORKOUT)
            .map(
              (point) => HealthWorkoutSummary(
                id: point.uuid,
                start: point.dateFrom,
                end: point.dateTo,
                activity: point.workoutSummary?.workoutType ?? 'other',
              ),
            )
            .toList();
      }
    } on Object {
      // Permission denial, a locked device, and no data are recoverable states.
      // The UI distinguishes null from a real zero.
      return null;
    }
    final snapshot = HealthDataSnapshot(
      source: source,
      steps: steps,
      walkingRunningDistanceKm: distanceKm,
      activeEnergyKcal: activeEnergy,
      restingHeartRate: restingHeartRate,
      sleep: sleep,
      workouts: workouts,
    );
    return snapshot.hasData ? snapshot : null;
  }

  Future<void> _configure() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  static List<HealthDataType> _types(HealthMetric metric) => switch (metric) {
        HealthMetric.steps => [HealthDataType.STEPS],
        HealthMetric.walkingRunningDistance => [
            HealthDataType.DISTANCE_WALKING_RUNNING,
          ],
        HealthMetric.activeEnergyBurned => [
            HealthDataType.ACTIVE_ENERGY_BURNED,
          ],
        HealthMetric.restingHeartRate => [HealthDataType.RESTING_HEART_RATE],
        HealthMetric.sleep => _sleepTypes,
        HealthMetric.workouts => [HealthDataType.WORKOUT],
      };

  static const _sleepTypes = [
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.SLEEP_AWAKE,
    HealthDataType.SLEEP_DEEP,
    HealthDataType.SLEEP_LIGHT,
    HealthDataType.SLEEP_REM,
    HealthDataType.SLEEP_IN_BED,
  ];

  static double? _sumNumeric(
    List<HealthDataPoint> points,
    HealthDataType type,
  ) {
    final values = points
        .where((point) => point.type == type)
        .map((point) => point.value)
        .whereType<NumericHealthValue>()
        .map((value) => value.numericValue.toDouble())
        .toList();
    if (values.isEmpty) return null;
    return values.fold<double>(0, (total, value) => total + value);
  }

  static double? _latestNumeric(
    List<HealthDataPoint> points,
    HealthDataType type,
  ) {
    final matches = points.where((point) => point.type == type).toList()
      ..sort((a, b) => b.dateTo.compareTo(a.dateTo));
    if (matches.isEmpty) return null;
    final value = matches.first.value;
    return value is NumericHealthValue ? value.numericValue.toDouble() : null;
  }

  static String _sleepStage(HealthDataType type) => switch (type) {
        HealthDataType.SLEEP_AWAKE => 'awake',
        HealthDataType.SLEEP_DEEP => 'deep',
        HealthDataType.SLEEP_REM => 'rem',
        HealthDataType.SLEEP_LIGHT => 'core',
        HealthDataType.SLEEP_IN_BED => 'in_bed',
        _ => 'asleep',
      };
}

typedef ManualHealthReader = Future<HealthDataSnapshot?> Function({
  required DateTime from,
  required DateTime to,
  required Set<HealthMetric> metrics,
});

HealthDataProvider personalSideloadHealthProvider({
  required bool free,
  required HealthDataProvider apple,
  required ManualHealthProvider manual,
}) =>
    free ? manual : PrioritizedHealthDataProvider([apple, manual]);

class ManualHealthProvider implements HealthDataProvider {
  const ManualHealthProvider(this._reader);

  final ManualHealthReader _reader;

  @override
  String get source => 'manual';

  @override
  Future<bool> isAvailable() async => true;

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
  }) =>
      _reader(from: from, to: to, metrics: metrics);
}

class MockHealthDataProvider implements HealthDataProvider {
  const MockHealthDataProvider({
    this.snapshot = const HealthDataSnapshot(
      source: 'mock',
      steps: 6200,
      walkingRunningDistanceKm: 4.3,
      activeEnergyKcal: 320,
      restingHeartRate: 67,
    ),
    this.available = true,
  });

  final HealthDataSnapshot? snapshot;
  final bool available;

  @override
  String get source => 'mock';

  @override
  Future<bool> isAvailable() async => available;

  @override
  bool supports(HealthMetric metric) => true;

  @override
  Future<HealthAuthorization> requestAuthorization(HealthMetric metric) async =>
      available
          ? HealthAuthorization.requested
          : HealthAuthorization.unavailable;

  @override
  Future<HealthDataSnapshot?> read({
    required DateTime from,
    required DateTime to,
    required Set<HealthMetric> metrics,
  }) async =>
      snapshot;
}

class PrioritizedHealthDataProvider implements HealthDataProvider {
  const PrioritizedHealthDataProvider(this.providers);

  final List<HealthDataProvider> providers;

  @override
  String get source => 'prioritized';

  @override
  Future<bool> isAvailable() async {
    for (final provider in providers) {
      try {
        if (await provider.isAvailable()) return true;
      } on Object {
        // Missing entitlement / platform plugin must not defeat manual data.
      }
    }
    return false;
  }

  @override
  bool supports(HealthMetric metric) {
    for (final provider in providers) {
      try {
        if (provider.supports(metric)) return true;
      } on Object {
        // Continue to the next capability provider.
      }
    }
    return false;
  }

  @override
  Future<HealthAuthorization> requestAuthorization(HealthMetric metric) async {
    for (final provider in providers) {
      try {
        if (!provider.supports(metric) || !await provider.isAvailable()) {
          continue;
        }
        final result = await provider.requestAuthorization(metric);
        if (result != HealthAuthorization.unavailable) return result;
      } on Object {
        // Capability errors are recoverable; explicit denial is not overridden.
      }
    }
    return HealthAuthorization.unavailable;
  }

  @override
  Future<HealthDataSnapshot?> read({
    required DateTime from,
    required DateTime to,
    required Set<HealthMetric> metrics,
  }) async {
    for (final provider in providers) {
      try {
        if (!await provider.isAvailable()) continue;
        final snapshot = await provider.read(
          from: from,
          to: to,
          metrics: metrics,
        );
        if (snapshot != null) return snapshot;
      } on Object {
        // Manual input remains usable even when a native capability fails.
      }
    }
    return null;
  }
}
