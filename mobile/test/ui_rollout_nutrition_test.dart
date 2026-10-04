import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_health_os/core/theme/app_theme.dart';
import 'package:personal_health_os/core/widgets/app_components.dart';
import 'package:personal_health_os/features/nutrition/presentation/nutrition_screen.dart';
import 'package:personal_health_os/features/nutrition/presentation/meal_analysis_screen.dart';
import 'ui_rollout_fixtures.dart';
import 'package:personal_health_os/features/nutrition/data/nutrition_models.dart';
import 'package:personal_health_os/features/nutrition/presentation/nutrition_controller.dart';

void main() {
  testWidgets('offline prefilled zero aggregates are not existing meals',
      (tester) async {
    final state = NutritionViewState(
        daily: DailyNutritionModel(
            date: DateTime(2026, 9, 29),
            totals: const NutritionTotals(),
            meals: const {
              'breakfast': NutritionTotals(),
              'lunch': NutritionTotals(),
              'dinner': NutritionTotals(),
              'snack': NutritionTotals()
            },
            mealCounts: const {
              'breakfast': 0,
              'lunch': 0,
              'dinner': 0,
              'snack': 0
            }),
        meals: const [],
        goal: null,
        offline: true);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: NutritionContent(
                data: state,
                onRefresh: () async {},
                onAddFood: (_) {},
                onEditItem: (_, __) {}))));
    for (var i = 0; i < 8; i++) {
      expect(find.text('餐食明细暂不可用'), findsNothing);
      expect(find.textContaining('已有餐次汇总'), findsNothing);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -250));
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });
  for (final width in [320.0, 393.0, 430.0]) {
    for (final dark in [false, true]) {
      testWidgets('nutrition + draft $width dark=$dark 200%', (tester) async {
        tester.view.physicalSize = Size(width, 852);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        Widget frame(Widget content) => MaterialApp(
            theme: dark ? AppTheme.dark : AppTheme.light,
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2)),
                child: child!),
            home: Scaffold(body: content));
        await tester.pumpWidget(frame(NutritionContent(
            data: rolloutNutrition,
            onRefresh: () async {},
            onAddFood: (_) {},
            onEditItem: (_, __) {},
            onAnalyzePhoto: () {})));
        expect(find.textContaining('按现有范围选择'), findsOneWidget);
        expect(find.textContaining('本机待同步记录'), findsOneWidget);
        for (var i = 0; i < 16; i++) {
          await tester.drag(
              find.byType(Scrollable).first, const Offset(0, -300));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        final note = TextEditingController();
        addTearDown(note.dispose);
        await tester.pumpWidget(frame(SingleChildScrollView(
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
                onAdd: () {}))));
        for (var i = 0; i < 14; i++) {
          await tester.drag(
              find.byType(Scrollable).first, const Offset(0, -300));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        expect(find.textContaining('尚未计入'), findsOneWidget);
      });
    }
  }
  testWidgets('quantity rejects infinity and preserves input after failure',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: NumberEntryDialog(
                title: '修改份量',
                initialValue: '250',
                unit: 'g',
                onSave: (_) async {
                  calls++;
                  throw StateError('secret-error');
                }))));
    await tester.enterText(find.byType(TextFormField), 'Infinity');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.textContaining('有效数值'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '275');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('275'), findsOneWidget);
    expect(find.text('重试保存'), findsOneWidget);
    expect(find.textContaining('secret-error'), findsNothing);
  });
}
