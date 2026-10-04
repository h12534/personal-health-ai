import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_health_os/core/theme/app_theme.dart';
import 'package:personal_health_os/features/training/data/training_models.dart';
import 'package:personal_health_os/features/training/presentation/training_controller.dart';
import 'package:personal_health_os/features/training/presentation/training_screen.dart';

const rolloutExercise = ExerciseModel(
    id: 'exercise',
    name: '哑铃卧推',
    movementPattern: 'horizontal_push',
    primaryMuscles: ['胸部'],
    equipment: ['哑铃'],
    instructions: '控制下放。',
    executionCues: ['稳定肩胛'],
    safetyNotes: ['避免疼痛'],
    compound: true);
const rolloutTrainingItem = TrainingExerciseModel(
    id: 'item',
    exercise: rolloutExercise,
    targetSets: 3,
    repMin: 8,
    repMax: 12,
    targetRir: 2,
    restSeconds: 120,
    targetWeightKg: 20);
const rolloutDay = TrainingDayModel(
    id: 'day',
    name: '训练 A',
    focus: '全身力量',
    estimatedDurationMin: 45,
    exercises: [rolloutTrainingItem]);
final rolloutTraining = TrainingHomeData(plans: const [
  TrainingPlanModel(
      id: 'plan',
      name: '三日全身训练',
      difficulty: 'beginner',
      sessionsPerWeek: 3,
      active: true,
      days: [rolloutDay])
], workouts: [
  for (var i = 0; i < 3; i++)
    WorkoutModel(
        id: 'workout-$i',
        trainingDayId: 'day',
        startedAt: DateTime(2026, 9, 15 + i * 4),
        status: 'completed',
        durationMin: 45,
        sets: [
          WorkoutSetModel(
              id: 'set-$i',
              exerciseId: 'exercise',
              setNumber: 1,
              setType: 'working',
              weightKg: 15 + i * 2.5,
              reps: 10,
              rir: 2)
        ])
], exercises: const [
  rolloutExercise
], records: [
  PersonalRecordModel(
      exerciseId: 'exercise',
      type: 'max_weight',
      value: 20,
      achievedAt: DateTime(2026, 9, 23),
      confidence: 'normal')
]);

void main() {
  for (final width in [320.0, 393.0, 430.0]) {
    for (final dark in [false, true]) {
      testWidgets('training $width dark=$dark 200% all sections',
          (tester) async {
        tester.view.physicalSize = Size(width, 852);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(ProviderScope(
            overrides: [
              trainingHomeProvider.overrideWith((ref) async => rolloutTraining)
            ],
            child: MaterialApp(
                theme: dark ? AppTheme.dark : AppTheme.light,
                home: MediaQuery(
                    data: MediaQueryData(
                        size: Size(width, 852),
                        textScaler: TextScaler.linear(2)),
                    child: const Scaffold(
                        body: SafeArea(child: TrainingScreen()))))));
        await tester.pumpAndSettle();
        for (final label in ['计划', '历史', '动作库', '进度', '今日']) {
          await tester.ensureVisible(find.text(label));
          await tester.tap(find.text(label));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: label);
        }
        await tester.ensureVisible(find.byKey(const Key('record-set')));
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets(
      'set editor rejects invalid input, awaits once and retains failed values',
      (tester) async {
    final pending = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
            body: SingleChildScrollView(
                child: WorkoutSetEditor(
                    item: rolloutTrainingItem,
                    enabled: true,
                    completed: const [],
                    onRecord: (_, __, ___) {
                      calls++;
                      return pending.future;
                    })))));
    final fields = find.byType(TextFormField);
    for (final bad in ['NaN', '-1', '1001']) {
      await tester.enterText(fields.at(0), bad);
      await tester.tap(find.byKey(const Key('record-set')));
      await tester.pump();
      expect(calls, 0);
    }
    await tester.enterText(fields.at(0), '22.5');
    await tester.tap(find.byKey(const Key('record-set')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('record-set')));
    expect(calls, 1);
    pending.completeError(StateError('secret diagnostic must not display'));
    await tester.pump();
    expect(find.textContaining('输入已保留'), findsOneWidget);
    expect(find.text('22.5'), findsOneWidget);
    expect(find.textContaining('secret diagnostic'), findsNothing);
  });
  testWidgets('editing today fields survives section changes', (tester) async {
    await tester.pumpWidget(ProviderScope(overrides: [
      trainingHomeProvider.overrideWith((ref) async => rolloutTraining)
    ], child: const MaterialApp(home: Scaffold(body: TrainingScreen()))));
    await tester.pumpAndSettle();
    final editor = tester.state(find.byType(WorkoutSetEditor));
    await tester.tap(find.text('计划'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('今日'));
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(WorkoutSetEditor)), same(editor));
  });
}
