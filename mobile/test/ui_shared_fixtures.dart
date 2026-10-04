import 'package:personal_health_os/features/health/data/health_models.dart';
import 'package:personal_health_os/features/health/presentation/health_controller.dart';
import 'package:personal_health_os/features/supervision/data/supervision_models.dart';

const sharedEvidence = HealthEvidenceModel(
    title: '合成测试：理解个人趋势',
    publisher: '测试资料库',
    excerpt: '这是用于界面审查的合成引用摘要，不是实际医学结论。真实界面只展示服务器返回的已启用来源。',
    category: 'other',
    year: 2026,
    sourceUrl: 'https://docs.example.invalid/health/context');

class SharedHealthChat extends HealthChatController {
  @override
  Future<List<HealthChatMessage>> build() async => const [
        HealthChatMessage(text: '这个指标要如何理解？', fromUser: true),
        HealthChatMessage(
            text: '请结合该次报告范围与已有记录理解；单次记录不能替代诊断。',
            fromUser: false,
            evidence: [sharedEvidence],
            medicalBoundary: true,
            riskLevel: 'urgent')
      ];
}

class SharedKnowledge extends KnowledgeSearchController {
  @override
  Future<List<HealthEvidenceModel>> build() async => const [sharedEvidence];
}

const sharedDraftItem = LabDraftItemModel(
    id: 'synthetic-draft-item',
    testName: '合成测试指标',
    normalizedName: 'SYNTHETIC',
    flag: 'unknown',
    category: 'other',
    confidence: .5,
    userModified: false,
    value: 1.234567,
    unit: 'mmol/L',
    referenceMin: -.25,
    referenceMax: 2.345678);
final sharedDraftReport = LabReportModel(
    id: 'synthetic-review',
    reportDate: DateTime(2026, 10, 4),
    originalFilename: 'synthetic.pdf',
    ocrStatus: 'completed',
    reviewStatus: 'draft',
    retainOriginal: false,
    draftItems: const [sharedDraftItem],
    results: const []);
final sharedFollowup = HealthFollowupModel(
    id: 'synthetic-followup',
    reason: '合成测试建议；经本人确认后才创建任务。',
    recommendedDate: DateTime(2026, 11, 4),
    status: 'suggested');
