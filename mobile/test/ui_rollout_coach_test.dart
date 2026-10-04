import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_health_os/core/theme/app_theme.dart';
import 'package:personal_health_os/features/coach/data/coach_models.dart';
import 'package:personal_health_os/features/coach/presentation/coach_controller.dart';
import 'package:personal_health_os/features/coach/presentation/coach_screen.dart';
import 'package:personal_health_os/features/coach/presentation/hunger_entry_dialog.dart';

const rolloutCoachOverview = CoachOverviewModel(
    headline: '看趋势，不追逐单日波动。',
    observations: ['合成测试背景：记录还不完整。'],
    nextActions: ['继续记录晨重和饮食。'],
    trend: WeightTrendModel(
        direction: 'stable',
        plateau: false,
        plateauEligible: false,
        note: '数据不足，不判断平台期。',
        average7d: 98.6,
        change14d: -0.4));

class RolloutCoachChat extends CoachChatController {
  @override
  Future<List<CoachBubble>> build() async => const [
        CoachBubble(text: '今天晚餐怎么安排？', fromUser: true),
        CoachBubble(
            text: '先参考已有的下一餐范围，再选择蛋白质来源。',
            fromUser: false,
            safetyNotice: '建议不能替代医疗诊断。')
      ];
}

class _SlowChat extends CoachChatController {
  final pending = Completer<void>();
  int calls = 0;
  bool fail = true;
  @override
  Future<List<CoachBubble>> build() async =>
      const [CoachBubble(text: '之前的教练回复', fromUser: false)];
  @override
  Future<void> send(String message) async {
    calls++;
    final prior = state.valueOrNull ?? const <CoachBubble>[];
    state = AsyncData([...prior, CoachBubble(text: message, fromUser: true)]);
    if (calls == 1) await pending.future;
    if (fail) {
      state = AsyncError(StateError('secret raw error'), StackTrace.current);
    } else {
      state = AsyncData([
        ...prior,
        CoachBubble(text: message, fromUser: true),
        const CoachBubble(text: '重试后真实回复', fromUser: false)
      ]);
    }
  }
}

void main() {
  testWidgets(
      'actual declined adjustment is kept target, not unknown or actionable',
      (tester) async {
    const overview = CoachOverviewModel(
        headline: '本周记录',
        observations: [],
        nextActions: [],
        trend: WeightTrendModel(
            direction: 'stable',
            plateau: false,
            plateauEligible: false,
            note: '继续记录'),
        adjustment: DietAdjustmentModel(
            id: 'declined-adjustment',
            status: 'declined',
            previousCalories: 2200,
            proposedCalories: 2100,
            reason: '真实状态测试'));
    await tester.pumpWidget(ProviderScope(overrides: [
      coachOverviewProvider.overrideWith((ref) async => overview),
      coachChatProvider.overrideWith(RolloutCoachChat.new)
    ], child: const MaterialApp(home: Scaffold(body: CoachScreen()))));
    await tester.pumpAndSettle();
    expect(find.text('已保持当前目标'), findsOneWidget);
    expect(find.text('建议状态待确认'), findsNothing);
    expect(find.text('接受调整'), findsNothing);
  });
  for (final width in [320.0, 393.0, 430.0]) {
    for (final dark in [false, true]) {
      testWidgets('coach $width dark=$dark 200%', (tester) async {
        tester.view.physicalSize = Size(width, 852);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(ProviderScope(
            overrides: [
              coachOverviewProvider
                  .overrideWith((ref) async => rolloutCoachOverview),
              coachChatProvider.overrideWith(RolloutCoachChat.new)
            ],
            child: MaterialApp(
                theme: dark ? AppTheme.dark : AppTheme.light,
                home: MediaQuery(
                    data: MediaQueryData(
                        size: Size(width, 852),
                        textScaler: TextScaler.linear(2)),
                    child: const Scaffold(
                        body: SafeArea(child: CoachScreen()))))));
        await tester.pumpAndSettle();
        await tester.drag(find.byType(ListView).first, const Offset(0, -1600));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byTooltip('发送').hitTestable(), findsOneWidget);
      });
    }
  }
  testWidgets(
      'slow send locks all entries, retains history and retries without losing earlier replies',
      (tester) async {
    final chat = _SlowChat();
    await tester.pumpWidget(ProviderScope(overrides: [
      coachOverviewProvider.overrideWith((ref) async => rolloutCoachOverview),
      coachChatProvider.overrideWith(() => chat)
    ], child: const MaterialApp(home: Scaffold(body: CoachScreen()))));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '我的问题');
    await tester.tap(find.byTooltip('发送'));
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    expect(chat.calls, 1);
    chat.pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('我的问题'), findsWidgets);
    expect(find.textContaining('secret raw'), findsNothing);
    await tester.drag(find.byType(ListView).first, const Offset(0, -1200));
    await tester.pumpAndSettle();
    expect(find.text('之前的教练回复'), findsOneWidget);
    chat.fail = false;
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();
    expect(chat.calls, 2);
    expect(
        tester
            .widget<ListView>(find.byType(ListView).first)
            .childrenDelegate
            .estimatedChildCount,
        4,
        reason:
            'Context, prior reply, one retried question and its reply; no duplicated failed attempt.');
    expect(find.text('之前的教练回复'), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -800));
    await tester.pumpAndSettle();
    expect(find.text('重试后真实回复'), findsOneWidget);
  });
  testWidgets('hunger save awaits once and preserves all failed fields',
      (tester) async {
    final pending = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => HungerEntryDialog(onSave: (h, c, m, n) {
                              calls++;
                              expect(
                                  [h, c, m, n], [3, 2, 'before_dinner', '训练后']);
                              return pending.future;
                            })),
                    child: const Text('打开'))))));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '训练后');
    await tester.tap(find.text('保存'));
    await tester.pump();
    await tester.tap(find.text('正在保存…'));
    expect(calls, 1);
    pending.completeError(StateError('secret'));
    await tester.pumpAndSettle();
    expect(find.text('训练后'), findsOneWidget);
    expect(find.text('重试保存'), findsOneWidget);
    expect(find.text('secret'), findsNothing);
  });
}
