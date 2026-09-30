import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_health_os/core/database/local_database.dart';
import 'package:personal_health_os/features/profile/presentation/health_sync_screen.dart';
import 'package:personal_health_os/features/training/data/offline_workout_repository.dart';
import 'package:personal_health_os/features/training/data/training_models.dart';
import 'package:personal_health_os/features/training/presentation/training_controller.dart';
import 'package:personal_health_os/features/training/presentation/training_screen.dart';

void main() {
  testWidgets('training home shows today workout and exercise targets',
      (tester) async {
    await _pumpTraining(tester, _data());

    expect(find.byKey(const Key('training-home')), findsOneWidget);
    expect(find.text('训练 A'), findsOneWidget);
    expect(find.text('卧推'), findsOneWidget);
    expect(find.textContaining('3 × 8–12'), findsOneWidget);
  });

  testWidgets('records a set locally and starts the rest timer',
      (tester) async {
    final repository = _FakeWorkoutRepository();
    await _pumpTraining(tester, _data(), repository: repository);

    await tester.tap(find.byKey(const Key('start-workout')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('record-set')).first);
    await tester.pump();

    expect(repository.recorded, hasLength(1));
    expect(find.byKey(const Key('rest-timer')), findsOneWidget);
    expect(find.textContaining('40.0×8'), findsOneWidget);
  });

  testWidgets('plan section shows structured training days', (tester) async {
    await _pumpTraining(tester, _data());

    await tester.tap(find.text('计划'));
    await tester.pump();

    expect(find.text('每周 3 次 · beginner'), findsOneWidget);
    expect(find.textContaining('卧推'), findsWidgets);
  });

  testWidgets('progress section shows personal records', (tester) async {
    await _pumpTraining(tester, _data());

    await tester.tap(find.text('进度'));
    await tester.pump();

    expect(find.byKey(const Key('personal-record')), findsOneWidget);
    expect(find.text('估算 1RM PR · 置信度 normal'), findsOneWidget);
  });

  testWidgets('health settings render independent HealthKit switch states',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          healthPermissionsProvider.overrideWith(
            (ref) async => const [
              HealthPermissionModel(
                dataType: 'steps',
                enabled: true,
                authorizationStatus: 'unknown',
              ),
              HealthPermissionModel(
                dataType: 'sleep',
                enabled: false,
                authorizationStatus: 'not_requested',
              ),
              HealthPermissionModel(
                dataType: 'resting_heart_rate',
                enabled: false,
                authorizationStatus: 'not_requested',
              ),
              HealthPermissionModel(
                dataType: 'workouts',
                enabled: true,
                authorizationStatus: 'unknown',
              ),
            ],
          ),
        ],
        child: const MaterialApp(home: HealthSyncScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('步数'), findsOneWidget);
    expect(find.text('睡眠'), findsOneWidget);
    final switches = tester.widgetList<SwitchListTile>(
      find.byType(SwitchListTile),
    );
    expect(switches.map((value) => value.value), [true, false, false, true]);
  });

  testWidgets('opens structured AI training coach sheet', (tester) async {
    await _pumpTraining(
      tester,
      _data(),
      chatMessages: const [
        TrainingChatMessage(
          text: '卧推下次建议 42.5 kg。',
          fromUser: false,
          actions: [
            {
              'type': 'apply_progression',
              'label': '查看并应用建议',
              'target_id': 'exercise-bench',
              'payload': {
                'suggested_weight_kg': 42.5,
                'reason': '达到次数上限',
              },
            },
          ],
        ),
      ],
    );

    await tester.tap(find.byTooltip('AI 私教'));
    await tester.pumpAndSettle();

    expect(find.text('AI 私人训练教练'), findsOneWidget);
    expect(find.text('重量和进阶由程序规则计算'), findsOneWidget);
    expect(find.text('例如：明天还练吗？'), findsOneWidget);
    expect(find.byKey(const Key('apply-training-suggestion')), findsOneWidget);
  });
}

Future<void> _pumpTraining(
  WidgetTester tester,
  TrainingHomeData data, {
  WorkoutRepository? repository,
  List<TrainingChatMessage>? chatMessages,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        trainingHomeProvider.overrideWith((ref) async => data),
        offlineWorkoutRepositoryProvider.overrideWithValue(
          repository ?? _FakeWorkoutRepository(),
        ),
        workoutSyncTriggerProvider.overrideWithValue(() async {}),
        if (chatMessages != null)
          trainingChatProvider.overrideWith(
            () => _FakeTrainingChatController(chatMessages),
          ),
      ],
      child: const MaterialApp(
        home: Scaffold(body: SafeArea(child: TrainingScreen())),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeTrainingChatController extends TrainingChatController {
  _FakeTrainingChatController(this.messages);

  final List<TrainingChatMessage> messages;

  @override
  Future<List<TrainingChatMessage>> build() async => messages;
}

TrainingHomeData _data() {
  const exercise = ExerciseModel(
    id: 'exercise-bench',
    name: '卧推',
    movementPattern: 'horizontal_push',
    primaryMuscles: ['胸大肌'],
    equipment: ['barbell'],
    instructions: '控制下放并推起。',
    executionCues: ['肩胛稳定'],
    safetyNotes: ['使用保护架'],
    compound: true,
  );
  const trainingExercise = TrainingExerciseModel(
    id: 'plan-exercise',
    exercise: exercise,
    targetSets: 3,
    repMin: 8,
    repMax: 12,
    targetRir: 2,
    restSeconds: 120,
  );
  const day = TrainingDayModel(
    id: 'day-a',
    name: '训练 A',
    focus: '全身力量',
    estimatedDurationMin: 60,
    exercises: [trainingExercise],
  );
  const plan = TrainingPlanModel(
    id: 'plan',
    name: '三日全身训练',
    difficulty: 'beginner',
    sessionsPerWeek: 3,
    active: true,
    days: [day],
  );
  final previous = WorkoutModel(
    id: 'old-workout',
    trainingDayId: 'day-a',
    startedAt: DateTime(2026, 9, 20),
    status: 'completed',
    durationMin: 45,
    sets: const [
      WorkoutSetModel(
        id: 'old-set',
        exerciseId: 'exercise-bench',
        setNumber: 1,
        setType: 'working',
        weightKg: 40,
        reps: 10,
        rir: 2,
      ),
    ],
  );
  return TrainingHomeData(
    plans: const [plan],
    workouts: [previous],
    exercises: const [exercise],
    records: [
      PersonalRecordModel(
        exerciseId: 'exercise-bench',
        type: 'estimated_1rm',
        value: 53.3,
        achievedAt: DateTime(2026, 9, 20),
        confidence: 'normal',
      ),
    ],
  );
}

class _FakeWorkoutRepository implements WorkoutRepository {
  final recorded = <LocalWorkoutSetRecord>[];

  @override
  Future<void> complete(String sessionLocalId, {double? sessionRpe}) async {}

  @override
  Future<LocalWorkoutSetRecord> recordSet({
    required String sessionLocalId,
    required String exerciseId,
    required int setNumber,
    required double weightKg,
    required int reps,
    required double rir,
    required int restSeconds,
    String setType = 'working',
  }) async {
    final value = LocalWorkoutSetRecord(
      localId: 'set-$setNumber',
      sessionLocalId: sessionLocalId,
      exerciseId: exerciseId,
      setNumber: setNumber,
      setType: setType,
      weightKg: weightKg,
      reps: reps,
      rir: rir,
      restSeconds: restSeconds,
      syncStatus: 'pending',
      updatedAt: DateTime(2026, 9, 30),
    );
    recorded.add(value);
    return value;
  }

  @override
  Future<List<LocalWorkoutSetRecord>> sets(String sessionLocalId) async =>
      recorded;

  @override
  Future<LocalWorkoutRecord> start({String? trainingDayId}) async =>
      LocalWorkoutRecord(
        localId: 'local-session',
        trainingDayId: trainingDayId,
        startedAt: DateTime(2026, 9, 30),
        status: 'in_progress',
        syncStatus: 'pending',
        updatedAt: DateTime(2026, 9, 30),
      );
}
