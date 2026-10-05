import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_health_os/core/theme/app_theme.dart';
import 'package:personal_health_os/core/theme/app_navigation_bar.dart';
import 'package:personal_health_os/core/network/api_client.dart';
import 'package:personal_health_os/features/dashboard/data/dashboard_model.dart';
import 'package:personal_health_os/features/dashboard/presentation/dashboard_screen.dart';
import 'package:personal_health_os/features/nutrition/presentation/nutrition_screen.dart';
import 'package:personal_health_os/features/health/presentation/health_controller.dart';
import 'package:personal_health_os/features/health/presentation/health_screen.dart';
import 'package:personal_health_os/features/coach/presentation/coach_controller.dart';
import 'package:personal_health_os/features/coach/presentation/coach_screen.dart';
import 'package:personal_health_os/features/training/presentation/training_controller.dart';
import 'package:personal_health_os/features/training/presentation/training_screen.dart';
import 'package:personal_health_os/features/profile/presentation/profile_screen.dart';
import 'ui_rollout_fixtures.dart';
import 'ui_shared_fixtures.dart';
import 'ui_redesign_golden_test.dart' show sampleReport, sampleTrend;
import 'ui_rollout_training_test.dart' show rolloutTraining;
import 'ui_rollout_coach_test.dart' show rolloutCoachOverview, RolloutCoachChat;

class _FailedHealth extends SharedHealthChat {
  @override
  Future<void> send(String message) async {
    state = AsyncError(StateError('secret-health'), StackTrace.current);
  }
}

class _FailedCoach extends RolloutCoachChat {
  @override
  Future<void> send(String message) async {
    state = AsyncError(StateError('secret-coach'), StackTrace.current);
  }
}

Future<void> _pump(WidgetTester tester, Widget screen, Size size, bool dark,
    {double keyboard = 0, double scale = 2}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(ProviderScope(
      key: UniqueKey(),
      overrides: [
        healthReportsProvider.overrideWith((ref) async => [sampleReport]),
        labTrendProvider.overrideWith((ref, name) async => sampleTrend),
        healthChatProvider.overrideWith(_FailedHealth.new),
        knowledgeSearchProvider.overrideWith(SharedKnowledge.new),
        coachOverviewProvider.overrideWith((ref) async => rolloutCoachOverview),
        coachChatProvider.overrideWith(_FailedCoach.new),
        trainingHomeProvider.overrideWith((ref) async => rolloutTraining),
        visionPrivacyProvider
            .overrideWith((ref) async => const VisionPrivacySettings())
      ],
      child: MaterialApp(
          theme: dark ? AppTheme.dark : AppTheme.light,
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(scale),
                  disableAnimations: true,
                  viewInsets: EdgeInsets.only(bottom: keyboard)),
              child: child!),
          home: Scaffold(
              body: SafeArea(child: screen),
              bottomNavigationBar:
                  AppNavigationBar(index: 3, onSelect: (_) {})))));
  await tester.pumpAndSettle();
}

void main() {
  for (final size in [
    const Size(320, 568),
    const Size(393, 852),
    const Size(430, 932)
  ]) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 1.3, 2.0]) {
        testWidgets('root semantics and 44pt $size dark=$dark scale=$scale',
            (tester) async {
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final handle = tester.ensureSemantics();
          try {
            for (final screen in <Widget>[
              DashboardContent(
                  data: DashboardModel(
                      date: DateTime(2026, 10, 4),
                      todayWeightKg: 98.6,
                      average7dKg: 98.8,
                      weekChangeKg: -.2,
                      caloriesConsumed: 1000,
                      caloriesTarget: 2200,
                      proteinG: 80,
                      proteinTargetG: 135,
                      steps: 7420,
                      stepsTarget: 8000,
                      waterMl: 1250,
                      trainingCompleted: false,
                      morningWeightCompleted: true,
                      aiNextAction: '继续记录'),
                  onAddWeight: () {},
                  onOpenTasks: () {}),
              NutritionContent(
                  data: rolloutNutrition,
                  onRefresh: () async {},
                  onAddFood: (_) {},
                  onEditItem: (_, __) {},
                  onAnalyzePhoto: () {}),
              const TrainingScreen(),
              const HealthScreen(),
              const CoachScreen(),
              const ProfileScreen()
            ]) {
              await _pump(tester, screen, size, dark, scale: scale);
              expect(tester.takeException(), isNull,
                  reason: '${screen.runtimeType}');
              await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
              if (screen is HealthScreen) {
                await tester.ensureVisible(find.text('健康 AI'));
                await tester.tap(find.text('健康 AI'));
                await tester.pumpAndSettle();
                expect(tester.takeException(), isNull,
                    reason: 'Health AI after navigation');
                await expectLater(
                    tester, meetsGuideline(iOSTapTargetGuideline));
                expect(find.byTooltip('发送健康问题'), findsOneWidget);
              }
              await tester.pumpWidget(const SizedBox());
            }
          } finally {
            handle.dispose();
          }
        });
      }
      testWidgets('keyboard composer remains reachable $size dark=$dark 200%',
          (tester) async {
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        for (final screen in [const HealthScreen(), const CoachScreen()]) {
          await _pump(tester, screen, size, dark, keyboard: 300);
          if (screen is HealthScreen) {
            await tester.ensureVisible(find.text('健康 AI'));
            await tester.tap(find.text('健康 AI'));
            await tester.pumpAndSettle();
          }
          expect(tester.takeException(), isNull,
              reason: '${screen.runtimeType} keyboard');
          final input = find.byType(TextField).last;
          await tester.enterText(input, '这是用于测试键盘布局的较长中文问题，输入内容应当完整保留。');
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final send = find.byTooltip(screen is HealthScreen ? '发送健康问题' : '发送');
          expect(send.hitTestable(), findsOneWidget);
          final box = tester.getRect(send);
          expect(box.bottom, lessThanOrEqualTo(size.height - 300),
              reason: 'Send above keyboard');
          expect(box.width, greaterThanOrEqualTo(44));
          expect(box.height, greaterThanOrEqualTo(44));
          await tester.tap(send);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull,
              reason: 'Failed send with keyboard remains usable');
          expect(send.hitTestable(), findsOneWidget);
          expect(find.textContaining('secret-health'), findsNothing);
          expect(find.textContaining('secret-coach'), findsNothing);
          expect(tester.widget<TextField>(input).controller!.text,
              contains('输入内容应当完整保留'));
        }
      });
    }
  }
}
