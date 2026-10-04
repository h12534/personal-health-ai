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
import 'package:personal_health_os/core/network/api_client.dart';
import 'package:personal_health_os/features/coach/data/coach_models.dart';
import 'package:personal_health_os/features/coach/presentation/coach_controller.dart';
import 'package:personal_health_os/features/coach/presentation/coach_screen.dart';
import 'package:personal_health_os/features/profile/presentation/profile_screen.dart';
import 'package:personal_health_os/core/widgets/app_components.dart';
import 'package:personal_health_os/features/nutrition/presentation/meal_analysis_screen.dart';
import 'ui_rollout_fixtures.dart';
import 'ui_rollout_training_test.dart' show rolloutTraining;
import 'ui_rollout_coach_test.dart' show rolloutCoachOverview, RolloutCoachChat;
import 'ui_rollout_profile_test.dart'
    show rolloutPreferences, rolloutPermissions, RolloutUnlockedLock;
import 'package:personal_health_os/features/profile/presentation/health_sync_screen.dart';
import 'package:personal_health_os/features/supervision/presentation/supervision_controller.dart'
    as supervision;
import 'package:personal_health_os/features/supervision/presentation/supervision_screens.dart';
import 'package:personal_health_os/core/privacy/privacy_lock.dart';

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

  for (final entry in [
    ('dashboard', false),
    ('dashboard', true),
    ('nutrition', false),
    ('nutrition', true),
    ('training', false),
    ('training', true),
    ('training-progress', false),
    ('training-progress', true),
    ('coach', false),
    ('coach', true),
    ('coach-conversation', false),
    ('coach-conversation', true),
    ('profile', false),
    ('profile', true),
    ('health-sync', false),
    ('health-sync', true),
    ('notifications', false),
    ('notifications', true),
    ('privacy-data', false),
    ('privacy-data', true),
    ('nutrition-flow', false),
    ('nutrition-flow', true),
    ('meal-draft', false),
    ('meal-draft', true),
  ]) {
    final (name, dark) = entry;
    testWidgets('$name ${dark ? 'dark' : 'light'} themed golden',
        (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final note = TextEditingController();
      addTearDown(note.dispose);
      final Widget screen = switch (name) {
        'dashboard' => DashboardContent(data: _dashboard, onAddWeight: () {}),
        'nutrition' => NutritionContent(
            data: _nutrition,
            onRefresh: () async {},
            onAddFood: (_) {},
            onEditItem: (_, __) {}),
        'coach' || 'coach-conversation' => const CoachScreen(),
        'profile' => const ProfileScreen(),
        'health-sync' => const HealthSyncScreen(),
        'notifications' => const NotificationSettingsScreen(),
        'privacy-data' => const PrivacyDataScreen(),
        'nutrition-flow' => NutritionContent(
            data: rolloutNutrition,
            onRefresh: () async {},
            onAddFood: (_) {},
            onEditItem: (_, __) {},
            onAnalyzePhoto: () {},
            onOpenCanteen: () {}),
        'meal-draft' => SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: MealDraftReview(
                analysis: rolloutDraft,
                busy: false,
                mealType: 'lunch',
                noteController: note,
                onMealTypeChanged: (_) {},
                onAdjust: (_, __) {},
                onEditWeight: (_) {},
                onReplace: (_) {},
                onDelete: (_) {},
                onAdd: () {})),
        _ => const TrainingScreen(),
      };
      final theme = dark ? AppTheme.dark : AppTheme.light;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          healthKitCapabilityProvider.overrideWith((ref) async => true),
          healthPermissionsProvider
              .overrideWith((ref) async => rolloutPermissions),
          healthSyncStatusProvider.overrideWith((ref) async => []),
          supervision.reminderPreferencesProvider
              .overrideWith((ref) async => rolloutPreferences),
          privacyLockControllerProvider.overrideWith(RolloutUnlockedLock.new),
          trainingHomeProvider.overrideWith((ref) async =>
              name == 'training-progress' ? rolloutTraining : _training),
          coachChatProvider.overrideWith(name == 'coach-conversation'
              ? RolloutCoachChat.new
              : _GoldenCoachChat.new),
          coachOverviewProvider.overrideWith((ref) async =>
              name == 'coach-conversation'
                  ? rolloutCoachOverview
                  : _coachOverview),
          visionPrivacyProvider
              .overrideWith((ref) async => const VisionPrivacySettings())
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
                  appBar: name == 'meal-draft'
                      ? DetailPageHeader(label: '核对餐食')
                      : null,
                  body: SafeArea(child: screen),
                  bottomNavigationBar: name == 'meal-draft'
                      ? BottomActionArea(
                          child: FilledButton.icon(
                              onPressed: () {},
                              icon: const Icon(Icons.check_circle_outline),
                              label: const Text('确认并计入今日营养')))
                      : AppNavigationBar(
                          index: switch (name) {
                            'dashboard' => 0,
                            'nutrition' => 1,
                            'nutrition-flow' => 1,
                            'training' || 'training-progress' => 2,
                            _ => 4
                          },
                          onSelect: _ignoreSelection))),
        ),
      ));
      await tester.pumpAndSettle();
      if (name == 'training-progress') {
        await tester.tap(find.text('进度'));
        await tester.pumpAndSettle();
      }
      if (name == 'coach-conversation') {
        await tester.drag(find.byType(ListView).first, const Offset(0, -650));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      await expectLater(find.byKey(_frameKey),
          matchesGoldenFile('goldens/$name-${dark ? 'dark' : 'light'}.png'));
    });
  }
}

void _ignoreSelection(int value) {}

class _GoldenCoachChat extends CoachChatController {
  @override
  Future<List<CoachBubble>> build() async => const [];
}

const _coachOverview = CoachOverviewModel(
    headline: '看趋势，不追逐单日波动。',
    observations: ['记录完整'],
    nextActions: ['继续执行'],
    trend: WeightTrendModel(
        direction: 'stable',
        plateau: false,
        plateauEligible: false,
        note: '数据不足，不判断平台期。'));

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
