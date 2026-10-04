import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_health_os/features/health/data/health_models.dart';
import 'package:personal_health_os/features/health/presentation/health_controller.dart';
import 'package:personal_health_os/features/health/presentation/health_screen.dart';

void main() {
  testWidgets('health overview shows report summary and indicator trend',
      (tester) async {
    await _pumpHealth(tester);

    expect(find.byKey(const Key('health-screen')), findsOneWidget);
    expect(find.text('上次体检'), findsOneWidget);
    expect(find.text('需要关注 1 项 · 以报告参考范围为准'), findsOneWidget);

    await tester.tap(find.byKey(const Key('lab-result-HBA1C')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('lab-trend-chart')), findsOneWidget);
    expect(find.text('趋势只描述时间上的共同变化，不代表因果关系。'), findsOneWidget);
    expect(find.byKey(const Key('ask-about-indicator')), findsOneWidget);
  });

  testWidgets('lab upload presents camera photos and Files choices',
      (tester) async {
    await _pumpHealth(tester);

    await tester.tap(find.text('体检报告'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('upload-lab-report')));
    await tester.pumpAndSettle();

    expect(find.text('拍照'), findsOneWidget);
    expect(find.text('从相册选择'), findsOneWidget);
    expect(find.text('从 Files 选择 PDF'), findsOneWidget);
    expect(find.textContaining('只生成草稿'), findsOneWidget);
  });

  testWidgets('lab review keeps OCR values draft until explicit confirmation',
      (tester) async {
    var confirmed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LabReviewSheet(
            report: _draftReport(),
            onUpdate: (item, edit) async => _draftReport(),
            onConfirm: () async {
              confirmed = true;
              return _report();
            },
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('lab-draft-HBA1C')), findsOneWidget);
    expect(find.text('5.8 %\n参考：4.0–5.6'), findsOneWidget);
    expect(confirmed, isFalse);

    await tester.tap(find.text('修改'));
    await tester.pumpAndSettle();
    expect(find.text('标准化名称'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-lab-draft')));
    await tester.pumpAndSettle();
    expect(confirmed, isTrue);
  });

  testWidgets('health AI renders medical boundary and citations',
      (tester) async {
    await _pumpHealth(
      tester,
      messages: const [
        HealthChatMessage(
          text: '单个 HbA1c 数值不能确认诊断，建议结合正式标准和医生评估。',
          fromUser: false,
          medicalBoundary: true,
          evidence: [
            HealthEvidenceModel(
              title: 'The A1C Test & Diabetes',
              publisher: 'NIDDK',
              excerpt: 'A1C reflects average glucose over time.',
              category: 'blood_glucose',
              year: 2026,
            ),
          ],
        ),
      ],
    );

    await tester.tap(find.text('健康 AI'));
    await tester.pumpAndSettle();
    expect(find.text('医疗边界：此回答不构成诊断或处方建议。'), findsOneWidget);
    expect(find.text('依据来源'), findsOneWidget);
    expect(find.text('NIDDK｜The A1C Test & Diabetes'), findsNothing);
    await tester.ensureVisible(find.text('依据来源'));
    await tester.tap(find.text('依据来源'));
    await tester.pumpAndSettle();
    expect(find.text('NIDDK｜The A1C Test & Diabetes'), findsOneWidget);
    expect(find.text('2026 年'), findsOneWidget);
    expect(
        find.text('A1C reflects average glucose over time.'), findsOneWidget);
  });

  testWidgets('knowledge search results hide internal score and chunk ids',
      (tester) async {
    await _pumpHealth(
      tester,
      evidence: const [
        HealthEvidenceModel(
          title: '中国居民膳食指南（2022）',
          publisher: '中国营养学会',
          excerpt: '食物多样，合理搭配。',
          category: 'nutrition',
          year: 2022,
          sourceUrl: 'https://dg.cnsoc.org/',
        ),
      ],
    );
    await tester.tap(find.text('健康知识'));
    await tester.pumpAndSettle();

    expect(find.text('中国居民膳食指南（2022）'), findsOneWidget);
    expect(find.textContaining('score'), findsNothing);
    expect(find.textContaining('chunk_id'), findsNothing);
  });
}

Future<void> _pumpHealth(
  WidgetTester tester, {
  List<HealthChatMessage> messages = const [],
  List<HealthEvidenceModel> evidence = const [],
}) async {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        healthReportsProvider.overrideWith((ref) async => [_report()]),
        labTrendProvider.overrideWith((ref, name) async => _trend()),
        healthChatProvider.overrideWith(
          () => _FakeHealthChatController(messages),
        ),
        knowledgeSearchProvider.overrideWith(
          () => _FakeKnowledgeController(evidence),
        ),
      ],
      child: const MaterialApp(
          home: Scaffold(body: SafeArea(child: HealthScreen()))),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeHealthChatController extends HealthChatController {
  _FakeHealthChatController(this.messages);

  final List<HealthChatMessage> messages;

  @override
  Future<List<HealthChatMessage>> build() async => messages;
}

class _FakeKnowledgeController extends KnowledgeSearchController {
  _FakeKnowledgeController(this.evidence);

  final List<HealthEvidenceModel> evidence;

  @override
  Future<List<HealthEvidenceModel>> build() async => evidence;
}

LabReportModel _report() => LabReportModel(
      id: 'report-1',
      reportDate: DateTime(2026, 9, 1),
      hospitalName: '示例医院',
      originalFilename: 'report.pdf',
      ocrStatus: 'completed',
      reviewStatus: 'confirmed',
      retainOriginal: true,
      draftItems: const [],
      results: const [
        LabResultModel(
          id: 'result-1',
          reportId: 'report-1',
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

LabReportModel _draftReport() => LabReportModel(
      id: 'report-draft',
      reportDate: DateTime(2026, 9, 1),
      originalFilename: 'draft.pdf',
      ocrStatus: 'completed',
      reviewStatus: 'draft',
      retainOriginal: true,
      draftItems: const [
        LabDraftItemModel(
          id: 'draft-1',
          testName: 'HbA1c',
          normalizedName: 'HBA1C',
          value: 5.8,
          unit: '%',
          referenceMin: 4,
          referenceMax: 5.6,
          flag: 'high',
          category: 'blood_glucose',
          confidence: .95,
          userModified: false,
        ),
      ],
      results: const [],
    );

LabTrendModel _trend() => LabTrendModel(
      normalizedName: 'HBA1C',
      displayName: '糖化血红蛋白',
      canonicalUnit: '%',
      points: [
        LabTrendPointModel(
          reportId: 'report-0',
          date: DateTime(2026, 6, 1),
          value: 6.0,
          unit: '%',
          flag: 'high',
        ),
        LabTrendPointModel(
          reportId: 'report-1',
          date: DateTime(2026, 9, 1),
          value: 5.8,
          unit: '%',
          flag: 'high',
        ),
      ],
    );
