import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network/api_client.dart';
import '../../nutrition/data/sync_service.dart';
import '../data/training_models.dart';

class TrainingHomeData {
  const TrainingHomeData({
    required this.plans,
    required this.workouts,
    required this.exercises,
    required this.records,
  });

  final List<TrainingPlanModel> plans;
  final List<WorkoutModel> workouts;
  final List<ExerciseModel> exercises;
  final List<PersonalRecordModel> records;

  TrainingPlanModel? get activePlan {
    for (final plan in plans) {
      if (plan.active) return plan;
    }
    return plans.isEmpty ? null : plans.first;
  }

  TrainingDayModel? get nextDay {
    final plan = activePlan;
    if (plan == null || plan.days.isEmpty) return null;
    final completed = workouts.where((value) => value.status == 'completed');
    return plan.days[completed.length % plan.days.length];
  }
}

final trainingHomeProvider = FutureProvider<TrainingHomeData>((ref) async {
  final api = ref.watch(apiClientProvider);
  final values = await Future.wait<Object>([
    api.fetchTrainingPlans(),
    api.fetchWorkouts(),
    api.fetchExercises(),
    api.fetchPersonalRecords(),
  ]);
  return TrainingHomeData(
    plans: values[0] as List<TrainingPlanModel>,
    workouts: values[1] as List<WorkoutModel>,
    exercises: values[2] as List<ExerciseModel>,
    records: values[3] as List<PersonalRecordModel>,
  );
});

final workoutSyncTriggerProvider = Provider<Future<void> Function()>((ref) {
  return ref.watch(syncServiceProvider).syncPending;
});

class TrainingPlanController {
  const TrainingPlanController(this.ref);

  final WidgetRef ref;

  Future<void> generateDefault() async {
    await ref.read(apiClientProvider).generateDefaultTrainingPlan();
    ref.invalidate(trainingHomeProvider);
  }
}

class TrainingChatMessage {
  const TrainingChatMessage({
    required this.text,
    required this.fromUser,
    this.safetyNotice,
    this.actions = const [],
  });

  final String text;
  final bool fromUser;
  final String? safetyNotice;
  final List<Map<String, dynamic>> actions;
}

final trainingChatProvider =
    AsyncNotifierProvider<TrainingChatController, List<TrainingChatMessage>>(
  TrainingChatController.new,
);

class TrainingChatController extends AsyncNotifier<List<TrainingChatMessage>> {
  @override
  Future<List<TrainingChatMessage>> build() async => const [];

  Future<void> send(String raw) async {
    final message = raw.trim();
    if (message.isEmpty || state.isLoading) return;
    state = AsyncData([
      ...(state.valueOrNull ?? const []),
      TrainingChatMessage(text: message, fromUser: true),
    ]);
    try {
      final reply =
          await ref.read(apiClientProvider).sendTrainingCoachMessage(message);
      state = AsyncData([
        ...(state.valueOrNull ?? const []),
        TrainingChatMessage(
          text: reply.message,
          fromUser: false,
          safetyNotice: reply.safetyNotice,
          actions: reply.actions,
        ),
      ]);
    } on Object catch (error, stack) {
      state = AsyncError(error, stack);
    }
  }

  Future<void> applySuggestion(Map<String, dynamic> action) async {
    if (action['type'] != 'apply_progression') return;
    final exerciseId = action['target_id'] as String?;
    final payload = action['payload'] as Map<String, dynamic>?;
    final rawWeight = payload?['suggested_weight_kg'];
    final weight = rawWeight is num
        ? rawWeight.toDouble()
        : double.tryParse(rawWeight?.toString() ?? '');
    final reason = payload?['reason'] as String?;
    if (exerciseId == null || weight == null || reason == null) {
      throw StateError('训练建议缺少必要信息');
    }
    await ref.read(apiClientProvider).applyTrainingProgression(
          exerciseId: exerciseId,
          suggestedWeightKg: weight,
          reason: reason,
          idempotencyKey: const Uuid().v4(),
          evidenceSnapshot: payload ?? const {},
        );
  }
}
