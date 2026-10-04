import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_health_os/core/theme/app_theme.dart';
import 'package:personal_health_os/core/theme/app_navigation_bar.dart';
import 'package:personal_health_os/features/dashboard/data/dashboard_model.dart';
import 'package:personal_health_os/features/dashboard/presentation/dashboard_screen.dart';
import 'package:personal_health_os/features/nutrition/data/nutrition_models.dart';
import 'package:personal_health_os/features/nutrition/presentation/nutrition_controller.dart';
import 'package:personal_health_os/features/nutrition/presentation/nutrition_screen.dart';
import 'package:personal_health_os/features/training/data/training_models.dart';
import 'package:personal_health_os/features/training/presentation/training_controller.dart';
import 'package:personal_health_os/features/training/presentation/training_screen.dart';
import 'package:personal_health_os/features/health/data/health_models.dart';
import 'package:personal_health_os/features/health/presentation/health_controller.dart';
import 'package:personal_health_os/features/health/presentation/health_screen.dart';
import 'package:personal_health_os/features/health/presentation/health_overview_content.dart';

const _frameKey = Key('golden-frame');

void main() {
  setUpAll(() async {
    final font = FontLoader('GoldenTestChinese')
      ..addFont(Future.value(ByteData.sublistView(
        await File('test/assets/NotoSansSC.ttf').readAsBytes(),
      )));
    await font.load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
    await (FontLoader('packages/cupertino_icons/CupertinoIcons')
          ..addFont(rootBundle
              .load('packages/cupertino_icons/assets/CupertinoIcons.ttf')))
        .load();
  });

  for (final entry in [
    ('health-overview-light', false, HealthOverviewVariant.dataForward),
    ('health-overview-dark', true, HealthOverviewVariant.dataForward),
    ('health-variant-clinical', false, HealthOverviewVariant.clinical),
    ('health-variant-warm', false, HealthOverviewVariant.warm),
  ]) {
    final (name, dark, variant) = entry;
    testWidgets('$name golden', (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final theme = dark ? AppTheme.dark : AppTheme.light;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          healthReportsProvider.overrideWith((ref) async => [sampleReport]),
          labTrendProvider.overrideWith((ref, name) async => sampleTrend),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme.copyWith(
            platform: TargetPlatform.iOS,
            textTheme: theme.textTheme.apply(fontFamily: 'GoldenTestChinese'),
          ),
          home: RepaintBoundary(
            key: _frameKey,
            child: Scaffold(
              body: SafeArea(child: HealthScreen(overviewVariant: variant)),
              bottomNavigationBar:
                  const AppNavigationBar(index: 3, onSelect: _ignoreSelection),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final filename = '$name.png';
      await expectLater(
        find.byKey(_frameKey),
        matchesGoldenFile('goldens/$filename'),
      );
    });
  }

  for (final name in ['dashboard', 'nutrition', 'training']) {
    testWidgets('$name themed golden', (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final Widget screen = switch (name) {
        'dashboard' => DashboardContent(data: _dashboard, onAddWeight: () {}),
        'nutrition' => NutritionContent(
            data: _nutrition,
            onRefresh: () async {},
            onAddFood: (_) {},
            onEditItem: (_, __) {}),
        _ => const TrainingScreen(),
      };
      final theme = AppTheme.light;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          trainingHomeProvider.overrideWith((ref) async => _training)
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme.copyWith(
              platform: TargetPlatform.iOS,
              textTheme:
                  theme.textTheme.apply(fontFamily: 'GoldenTestChinese')),
          home: RepaintBoundary(
              key: _frameKey,
              child: Scaffold(
                  body: SafeArea(child: screen),
                  bottomNavigationBar: AppNavigationBar(
                      index:
                          ['dashboard', 'nutrition', 'training'].indexOf(name),
                      onSelect: _ignoreSelection))),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
          find.byKey(_frameKey), matchesGoldenFile('goldens/$name-light.png'));
    });
  }
}

void _ignoreSelection(int value) {}

final _dashboard = DashboardModel(
  date: DateTime(2026, 9, 29),
  todayWeightKg: 100,
  average7dKg: 100.4,
  weekChangeKg: -.6,
  caloriesConsumed: 1680,
  caloriesTarget: 2200,
  proteinG: 92,
  proteinTargetG: 135,
  steps: 5340,
  stepsTarget: 8000,
  waterMl: 1250,
  trainingCompleted: false,
  morningWeightCompleted: true,
  aiNextAction: '晚餐优先选择现实可获得的优质蛋白质。',
);

final _nutrition = NutritionViewState(
  daily: DailyNutritionModel(
      date: DateTime(2026, 9, 29),
      totals: const NutritionTotals(
          calories: 403, protein: 18, carbs: 57.1, fat: 10.1),
      meals: const {'breakfast': NutritionTotals(calories: 403, protein: 18)},
      mealCounts: const {'breakfast': 1}),
  meals: const [],
  goal: const NutritionGoalModel(calories: 2200, protein: 135, fiber: 25),
  offline: true,
);

const _exercise = ExerciseModel(
    id: 'synthetic-bench',
    name: '卧推',
    movementPattern: 'horizontal_push',
    primaryMuscles: ['胸大肌'],
    equipment: ['barbell'],
    instructions: '控制下放并推起。',
    executionCues: ['肩胛稳定'],
    safetyNotes: ['使用保护架'],
    compound: true);
const _day = TrainingDayModel(
    id: 'synthetic-day',
    name: '训练 A',
    focus: '全身力量',
    estimatedDurationMin: 60,
    exercises: [
      TrainingExerciseModel(
          id: 'synthetic-plan-exercise',
          exercise: _exercise,
          targetSets: 3,
          repMin: 8,
          repMax: 12,
          targetRir: 2,
          restSeconds: 120)
    ]);
const _plan = TrainingPlanModel(
    id: 'synthetic-plan',
    name: '三日全身训练',
    difficulty: 'beginner',
    sessionsPerWeek: 3,
    active: true,
    days: [_day]);
const _training = TrainingHomeData(
    plans: [_plan], workouts: [], exercises: [_exercise], records: []);

final sampleReport = LabReportModel(
  id: 'synthetic-report',
  reportDate: DateTime(2026, 9, 1),
  originalFilename: 'synthetic.pdf',
  ocrStatus: 'completed',
  reviewStatus: 'confirmed',
  retainOriginal: true,
  draftItems: const [],
  results: const [
    LabResultModel(
      id: 'synthetic-hba1c',
      reportId: 'synthetic-report',
      testName: '糖化血红蛋白',
      normalizedName: 'HBA1C',
      value: 5.8,
      unit: '%',
      referenceMin: 4,
      referenceMax: 5.6,
      flag: 'high',
      category: 'blood_glucose',
    ),
  ],
);

final sampleTrend = LabTrendModel(
  normalizedName: 'HBA1C',
  displayName: '糖化血红蛋白',
  canonicalUnit: '%',
  points: [
    LabTrendPointModel(
      reportId: 'synthetic-previous',
      date: DateTime(2026, 6, 1),
      value: 6,
      unit: '%',
      flag: 'high',
    ),
    LabTrendPointModel(
      reportId: 'synthetic-report',
      date: DateTime(2026, 9, 1),
      value: 5.8,
      unit: '%',
      flag: 'high',
    ),
  ],
);
