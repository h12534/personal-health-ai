import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_health_os/core/theme/app_theme.dart';
import 'package:personal_health_os/core/theme/app_tokens.dart';
import 'package:personal_health_os/core/theme/app_navigation_bar.dart';
import 'package:personal_health_os/features/health/data/health_models.dart';
import 'package:personal_health_os/features/health/presentation/health_controller.dart';
import 'package:personal_health_os/features/health/presentation/health_screen.dart';
import 'package:personal_health_os/features/health/presentation/health_trend_chart.dart';

import 'ui_redesign_golden_test.dart' show sampleReport, sampleTrend;

void main() {
  for (final colors in [AppColors.light, AppColors.dark]) {
    test(
        'semantic text and status contrast ${colors == AppColors.light ? 'light' : 'dark'}',
        () {
      for (final foreground in [
        colors.primaryText,
        colors.secondaryText,
        colors.tertiaryText
      ]) {
        for (final background in [
          colors.background,
          colors.surface,
          colors.softTint
        ]) {
          expect(_contrast(foreground, background), greaterThanOrEqualTo(4.5),
              reason: '$foreground on $background');
        }
      }
      for (final foreground in [
        colors.primary,
        colors.attention,
        colors.danger,
        colors.positive
      ]) {
        expect(
            _contrast(foreground, colors.softTint), greaterThanOrEqualTo(4.5));
      }
      final scheme =
          (colors == AppColors.light ? AppTheme.light : AppTheme.dark)
              .colorScheme;
      for (final pair in [
        (scheme.onPrimary, scheme.primary),
        (scheme.onSecondaryContainer, scheme.secondaryContainer),
        (scheme.onError, scheme.error),
      ]) {
        expect(_contrast(pair.$1, pair.$2), greaterThanOrEqualTo(4.5));
      }
    });
  }

  for (final dark in [false, true]) {
    testWidgets(
        '320pt large Chinese text and scrollable indicator ${dark ? 'dark' : 'light'}',
        (tester) async {
      final layoutErrors = <FlutterErrorDetails>[];
      final originalHandler = FlutterError.onError;
      FlutterError.onError = (details) {
        layoutErrors.add(details);
        originalHandler?.call(details);
      };
      try {
        await _pump(tester, dark: dark, size: const Size(320, 568), scale: 2);
      } finally {
        FlutterError.onError = originalHandler;
      }
      expect(find.text('高于本报告范围'), findsOneWidget);
      final exception = tester.takeException();
      expect(exception, isNull,
          reason: layoutErrors.map((e) => e.toString()).join('\n'));
      final indicatorTitle = find.text('糖化血红蛋白');
      await tester.ensureVisible(indicatorTitle);
      await tester.pumpAndSettle();
      await tester.tap(indicatorTitle);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byKey(const Key('ask-about-indicator')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ask-about-indicator')).hitTestable(),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('unconfirmed latest draft does not replace confirmed evidence',
      (tester) async {
    final draft = LabReportModel(
        id: 'synthetic-draft',
        reportDate: DateTime(2026, 10, 4),
        originalFilename: 'draft.pdf',
        ocrStatus: 'completed',
        reviewStatus: 'draft',
        retainOriginal: false,
        draftItems: const [],
        results: const []);
    await _pump(tester, reports: [draft, sampleReport]);
    expect(find.text('有体检草稿待核对'), findsOneWidget);
    expect(find.text('2026年9月1日'), findsNWidgets(2)); // Report date and chart endpoint now share the Chinese date format.
    expect(find.text('需要关注 0 项 · 以报告参考范围为准'), findsNothing);
  });

  testWidgets('empty error and loading have honest next steps', (tester) async {
    await _pump(tester, reports: []);
    expect(find.text('去上传'), findsOneWidget);
    await _pump(tester, fail: true);
    expect(find.text('重新读取体检记录'), findsOneWidget);
    expect(find.textContaining('sensitive-error'), findsNothing);
    final pending = Completer<List<LabReportModel>>();
    await _pump(tester, pending: pending.future, settle: false);
    expect(find.text('正在读取体检记录'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    pending.complete([]);
    await tester.pumpAndSettle();
  });

  testWidgets('status has readable semantics and controls meet 44pt',
      (tester) async {
    final handle = tester.ensureSemantics();
    try {
      await _pump(tester);
      expect(find.bySemanticsLabel(RegExp('糖化血红蛋白.*高于本报告范围')), findsOneWidget);
      final node =
          tester.getSemantics(find.bySemanticsLabel(RegExp('糖化血红蛋白.*高于本报告范围')));
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      final size = tester.getSize(find.byKey(const Key('lab-result-HBA1C')));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    } finally {
      handle.dispose();
    }
  });

  testWidgets('point picker reads dates and does not invent comparable units',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
            body: SizedBox(
                height: 220, child: LabTrendChart(trend: sampleTrend)))));
    expect(find.text('2026年9月1日  ·  5.8 %'), findsOneWidget);
    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2026年6月1日  ·  6.0 %').last);
    await tester.pumpAndSettle();
    expect(find.text('2026年6月1日  ·  6.0 %'), findsOneWidget);
    final wrongUnit = LabTrendModel(
        normalizedName: 'HBA1C',
        displayName: '糖化血红蛋白',
        canonicalUnit: '%',
        points: [
          LabTrendPointModel(
              reportId: 'synthetic-other',
              date: DateTime(2026, 9, 1),
              value: 39,
              unit: 'mmol/mol',
              flag: 'high')
        ]);
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
            body: SizedBox(
                height: 220, child: LabTrendChart(trend: wrongUnit)))));
    expect(find.text('暂无单位一致、可比较的历史记录'), findsOneWidget);
  });

  testWidgets('reduced motion resolves to zero transition', (tester) async {
    Duration? duration;
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Builder(builder: (context) {
              duration = AppMotion.duration(context);
              return const SizedBox.shrink();
            }))));
    expect(duration, Duration.zero);
  });
}

double _contrast(Color a, Color b) {
  final l1 = a.computeLuminance(), l2 = b.computeLuminance();
  return (l1 > l2 ? l1 + .05 : l2 + .05) / (l1 > l2 ? l2 + .05 : l1 + .05);
}

Future<void> _pump(WidgetTester tester,
    {bool dark = false,
    Size size = const Size(393, 852),
    double scale = 1,
    List<LabReportModel>? reports,
    bool fail = false,
    Future<List<LabReportModel>>? pending,
    bool settle = true}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    key: UniqueKey(),
    overrides: [
      healthReportsProvider.overrideWith((ref) async {
        if (fail) throw StateError('sensitive-error');
        return pending == null ? reports ?? [sampleReport] : await pending;
      }),
      labTrendProvider.overrideWith((ref, name) async => sampleTrend)
    ],
    child: MaterialApp(
      theme: dark ? AppTheme.dark : AppTheme.light,
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!),
      home: Scaffold(
          body: const SafeArea(child: HealthScreen()),
          bottomNavigationBar: AppNavigationBar(index: 3, onSelect: (_) {})),
    ),
  ));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}
