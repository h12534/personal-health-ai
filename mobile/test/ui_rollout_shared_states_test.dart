import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_health_os/core/theme/app_theme.dart';
import 'package:personal_health_os/core/widgets/app_components.dart';
import 'package:personal_health_os/features/health/data/health_models.dart';
import 'package:personal_health_os/features/health/presentation/health_controller.dart';
import 'package:personal_health_os/features/health/presentation/health_screen.dart';
import 'package:personal_health_os/features/health/presentation/health_trend_chart.dart';
import 'package:personal_health_os/features/supervision/presentation/supervision_controller.dart'
    as supervision;
import 'package:personal_health_os/features/supervision/presentation/supervision_screens.dart';
import 'ui_shared_fixtures.dart';
import 'ui_redesign_golden_test.dart' show sampleReport, sampleTrend;

class _SlowHealthChat extends HealthChatController {
  final pending = Completer<void>();
  int calls = 0;
  bool fail = true;
  @override
  Future<List<HealthChatMessage>> build() async =>
      const [HealthChatMessage(text: '之前的健康回复', fromUser: false)];
  @override
  Future<void> send(String message) async {
    calls++;
    final prior = state.valueOrNull ?? const <HealthChatMessage>[];
    state =
        AsyncData([...prior, HealthChatMessage(text: message, fromUser: true)]);
    if (calls == 1) await pending.future;
    state = fail
        ? AsyncError(StateError('secret health error'), StackTrace.current)
        : AsyncData([
            ...prior,
            HealthChatMessage(text: message, fromUser: true),
            const HealthChatMessage(text: '重试后的健康回复', fromUser: false)
          ]);
  }
}

class _EmptyKnowledge extends KnowledgeSearchController {
  int calls = 0;
  @override
  Future<List<HealthEvidenceModel>> build() async => const [];
  @override
  Future<void> search(String query) async {
    calls++;
    state = const AsyncData([]);
  }
}

Future<void> _health(WidgetTester tester,
    {HealthChatController Function()? chat,
    KnowledgeSearchController Function()? knowledge}) async {
  await tester.pumpWidget(ProviderScope(
      overrides: [
        healthReportsProvider.overrideWith((ref) async => [sampleReport]),
        labTrendProvider.overrideWith((ref, name) async => sampleTrend),
        healthChatProvider.overrideWith(chat ?? SharedHealthChat.new),
        knowledgeSearchProvider.overrideWith(knowledge ?? SharedKnowledge.new)
      ],
      child: MaterialApp(
          theme: AppTheme.light, home: const Scaffold(body: HealthScreen()))));
  await tester.pumpAndSettle();
}

Future<void> _reach(WidgetTester tester, Finder target, String listKey) async {
  for (var i = 0; i < 8 && target.hitTestable().evaluate().isEmpty; i++) {
    await tester.drag(find.byKey(Key(listKey)), const Offset(0, -350));
    await tester.pumpAndSettle();
  }
  expect(target.hitTestable(), findsOneWidget,
      reason: 'Reachable action in $listKey');
}

void main() {
  for (final width in [320.0, 393.0, 430.0]) {
    for (final dark in [false, true]) {
      testWidgets('shared health and auxiliary states $width dark=$dark 200%',
          (tester) async {
        tester.view.physicalSize = Size(width, 852);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        for (final screen in [
          const HealthScreen(),
          const ReportsScreen(),
          const HealthTimelineScreen(),
          const FollowupsScreen(),
          LabReviewSheet(
              report: sharedDraftReport,
              onUpdate: (item, edit) async => sharedDraftReport,
              onConfirm: () async => sharedDraftReport)
        ]) {
          await tester.pumpWidget(ProviderScope(
              overrides: [
                healthReportsProvider
                    .overrideWith((ref) async => [sampleReport]),
                labTrendProvider.overrideWith((ref, name) async => sampleTrend),
                healthChatProvider.overrideWith(SharedHealthChat.new),
                knowledgeSearchProvider.overrideWith(SharedKnowledge.new),
                supervision.healthReportsProvider
                    .overrideWith((ref, type) async => []),
                supervision.healthTimelineProvider
                    .overrideWith((ref, category) async => []),
                supervision.healthFollowupsProvider
                    .overrideWith((ref) async => [sharedFollowup])
              ],
              child: MaterialApp(
                  theme: dark ? AppTheme.dark : AppTheme.light,
                  home: MediaQuery(
                      data: MediaQueryData(
                          size: Size(width, 852),
                          textScaler: TextScaler.linear(2)),
                      child: Scaffold(body: SafeArea(child: screen))))));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull,
              reason: '${screen.runtimeType} initial');
          if (screen is HealthScreen) {
            for (final tab in ['体检报告', '健康知识', '健康 AI']) {
              await tester.ensureVisible(find.text(tab));
              await tester.tap(find.text(tab));
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull, reason: tab);
              if (tab == '健康知识') {
                await tester.tap(find.text(sharedEvidence.title));
                await tester.pumpAndSettle();
                expect(tester.takeException(), isNull);
              }
              if (tab == '健康 AI') {
                await _reach(tester, find.text('依据来源'), 'health-chat-history');
                await tester.tap(find.text('依据来源'));
                await tester.pumpAndSettle();
                await tester.drag(find.byKey(const Key('health-chat-history')),
                    const Offset(0, -450));
                await tester.pumpAndSettle();
                expect(tester.takeException(), isNull);
              }
            }
          } else {
            for (var i = 0; i < 3; i++) {
              await tester.drag(
                  find.byType(ListView).first, const Offset(0, -350));
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
            }
          }
          await tester.pumpWidget(const SizedBox());
        }
      });
    }
  }
  testWidgets(
      'health chat awaiting failure retry retains history without duplicates',
      (tester) async {
    final chat = _SlowHealthChat();
    await _health(tester, chat: () => chat);
    await tester.tap(find.text('健康 AI'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('health-chat-input')), '这次记录说明什么？');
    await tester.tap(find.byKey(const Key('send-health-chat')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('send-health-chat')));
    await tester.pump();
    expect(chat.calls, 1);
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('health-chat-input')))
            .enabled,
        isFalse);
    chat.pending.complete();
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('health-chat-input')))
            .controller!
            .text,
        '这次记录说明什么？');
    expect(find.text('之前的健康回复'), findsOneWidget);
    expect(find.textContaining('secret health error'), findsNothing);
    chat.fail = false;
    await tester.tap(find.byKey(const Key('send-health-chat')));
    await tester.pumpAndSettle();
    expect(chat.calls, 2);
    expect(find.text('之前的健康回复'), findsOneWidget);
    expect(
        (tester
                .widget<ListView>(find.byKey(const Key('health-chat-history')))
                .childrenDelegate as SliverChildBuilderDelegate)
            .estimatedChildCount,
        4);
    await _reach(tester, find.text('重试后的健康回复'), 'health-chat-history');
    expect(find.text('重试后的健康回复'), findsOneWidget);
    expect(find.text('这次记录说明什么？'), findsOneWidget);
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('health-chat-input')))
            .controller!
            .text,
        isEmpty);
  });
  testWidgets('indicator asks use same guarded health UI send path',
      (tester) async {
    final chat = _SlowHealthChat();
    await _health(tester, chat: () => chat);
    await _reach(tester, find.text('一起理解这个指标'), 'health-overview-list');
    await tester.tap(find.text('一起理解这个指标'));
    await tester.pumpAndSettle();
    expect(chat.calls, 1);
    expect(
        tester
            .widget<IconButton>(find.byKey(const Key('send-health-chat')))
            .onPressed,
        isNull);
    chat.pending.complete();
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('health-chat-input')))
            .controller!
            .text,
        contains('糖化血红蛋白'));
  });
  testWidgets('knowledge no matches is distinct from first visit',
      (tester) async {
    final search = _EmptyKnowledge();
    await _health(tester, knowledge: () => search);
    await tester.tap(find.text('健康知识'));
    await tester.pumpAndSettle();
    expect(find.text('从一个健康问题开始'), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('health-knowledge-search')), '个人趋势');
    await tester.tap(find.byTooltip('查找'));
    await tester.pumpAndSettle();
    expect(search.calls, 1);
    expect(find.text('没有找到匹配的来源'), findsOneWidget);
    expect(find.text('调整关键词'), findsOneWidget);
    expect(find.text('从一个健康问题开始'), findsNothing);
  });
  testWidgets(
      'clinical adapter keeps raw precision, range, duplicate dates and filters',
      (tester) async {
    final trend = LabTrendModel(
        normalizedName: 'SYNTHETIC',
        displayName: '合成指标',
        canonicalUnit: 'mmol/L',
        points: [
          LabTrendPointModel(
              reportId: 'first',
              date: DateTime(2026, 10, 4),
              value: 1.234567,
              unit: 'mmol/L',
              flag: 'normal',
              referenceMin: -.25,
              referenceMax: 2.345678),
          LabTrendPointModel(
              reportId: 'second',
              date: DateTime(2026, 10, 4),
              value: 1.987654,
              unit: 'mmol/L',
              flag: 'normal'),
          LabTrendPointModel(
              reportId: 'wrong-unit',
              date: DateTime(2026, 10, 5),
              value: 5,
              unit: 'mg/dL',
              flag: 'normal'),
          LabTrendPointModel(
              reportId: 'invalid',
              date: DateTime(2026, 10, 5),
              value: double.nan,
              unit: 'mmol/L',
              flag: 'unknown')
        ]);
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: LabTrendChart(trend: trend))));
    expect(find.text('已排除单位不同或无效的记录'), findsOneWidget);
    expect(find.text('2026年10月4日  ·  1.987654 mmol/L'), findsOneWidget);
    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2026年10月4日  ·  1.234567 mmol/L').last);
    await tester.pumpAndSettle();
    expect(find.text('2026年10月4日  ·  1.234567 mmol/L'), findsOneWidget);
    expect(find.text('该次报告范围：-0.25–2.345678 mmol/L'), findsOneWidget);
  });
  testWidgets(
      'lab editor rejects nonfinite, preserves negative precision and failed input',
      (tester) async {
    var calls = 0;
    LabDraftEdit? saved;
    final pending = Completer<LabReportModel>();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: LabEditDialog(
                item: sharedDraftItem,
                onSave: (edit) {
                  calls++;
                  saved = edit;
                  return pending.future;
                }))));
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(2), 'NaN');
    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(calls, 0);
    await tester.enterText(fields.at(2), '-0.123456');
    await tester.tap(find.text('保存'));
    await tester.pump();
    await tester.tap(find.text('正在保存…'));
    await tester.pump();
    expect(calls, 1);
    expect(saved!.value, -.123456);
    expect(saved!.referenceMax, 2.345678);
    pending.completeError(StateError('secret draft error'));
    await tester.pumpAndSettle();
    expect(find.textContaining('修改已保留'), findsOneWidget);
    expect(tester.widget<TextFormField>(fields.at(2)).controller!.text,
        '-0.123456');
    expect(find.textContaining('secret draft error'), findsNothing);
  });
  testWidgets('shared awaited action prevents duplicates and shows safe retry',
      (tester) async {
    var calls = 0;
    final pending = Completer<void>();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AsyncActionButton(
                label: '生成本期报告',
                onPressed: () {
                  calls++;
                  return pending.future;
                }))));
    await tester.tap(find.text('生成本期报告'));
    await tester.pump();
    await tester.tap(find.text('正在处理…'));
    await tester.pump();
    expect(calls, 1);
    pending.completeError(StateError('secret action error'));
    await tester.pumpAndSettle();
    expect(find.textContaining('请检查结果后重试'), findsOneWidget);
    expect(find.textContaining('secret action error'), findsNothing);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull);
  });
}
