import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_health_os/core/theme/app_theme.dart';
import 'package:personal_health_os/features/dashboard/data/dashboard_model.dart';
import 'package:personal_health_os/features/dashboard/presentation/dashboard_screen.dart';
import 'package:personal_health_os/features/supervision/data/supervision_models.dart';

void main() {
  for (final width in [320.0, 393.0, 430.0]) {
    for (final dark in [false, true]) {
      testWidgets('home $width dark=$dark 200% and skipped truth',
          (tester) async {
        tester.view.physicalSize = Size(width, 852);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(MaterialApp(
            theme: dark ? AppTheme.dark : AppTheme.light,
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2)),
                child: child!),
            home: Scaffold(
                body: DashboardContent(
                    data: _data(), onAddWeight: () {}, onOpenTasks: () {}))));
        expect(find.text('下一项：午餐'), findsOneWidget);
        for (var i = 0; i < 12; i++) {
          await tester.drag(
              find.byType(Scrollable).first, const Offset(0, -400));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        await tester.scrollUntilVisible(find.text('其他今日记录'), -300,
            scrollable: find.byType(Scrollable).first);
        await tester.tap(find.text('其他今日记录'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets(
      'weight validates, retains failed input and prevents duplicate saves',
      (tester) async {
    final pending = Completer<void>();
    var attempts = 0;
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => showDialog<bool>(
                        context: context,
                        builder: (_) => WeightEntryDialog(onSave: (value) {
                              attempts++;
                              expect(value, 98.6);
                              return pending.future;
                            })),
                    child: const Text('打开'))))));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'abc');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.textContaining('20–500'), findsOneWidget);
    expect(attempts, 0);
    await tester.enterText(find.byType(TextFormField), '98.6');
    await tester.tap(find.text('保存'));
    await tester.pump();
    await tester.tap(find.text('正在保存…'));
    await tester.pump();
    expect(attempts, 1);
    pending.completeError(StateError('secret-internal-server-error'));
    await tester.pumpAndSettle();
    expect(find.text('98.6'), findsOneWidget);
    expect(find.text('重试保存'), findsOneWidget);
    expect(find.textContaining('secret-internal'), findsNothing);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
  });
}

DashboardModel _data() => DashboardModel(
        date: DateTime(2026, 9, 29),
        todayWeightKg: null,
        average7dKg: null,
        weekChangeKg: null,
        proteinTargetG: null,
        stepsTarget: 8000,
        caloriesConsumed: 0,
        caloriesTarget: 0,
        proteinG: 0,
        steps: null,
        waterMl: 0,
        trainingCompleted: false,
        morningWeightCompleted: false,
        aiNextAction: '下一步来自现有规则。',
        keyTasks: [
          DailyTaskModel(
              id: 'skip',
              date: DateTime(2026, 9, 29),
              taskType: 'weight',
              title: '晨重',
              description: '',
              status: 'skipped',
              priority: 0),
          DailyTaskModel(
              id: 'pending',
              date: DateTime(2026, 9, 29),
              taskType: 'meal',
              title: '午餐',
              description: '',
              status: 'pending',
              priority: 1),
        ]);
