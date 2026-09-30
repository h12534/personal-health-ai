import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../data/health_models.dart';
import '../data/lab_offline_cache.dart';

final healthReportsProvider = FutureProvider<List<LabReportModel>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final cache = ref.watch(labOfflineCacheProvider);
  try {
    final reports = await api.fetchLabReports();
    await cache.saveReports(reports);
    return reports;
  } on Object {
    final cached = await cache.loadReports();
    if (cached.isNotEmpty) return cached;
    rethrow;
  }
});

final labTrendProvider =
    FutureProvider.family<LabTrendModel, String>((ref, normalizedName) async {
  final api = ref.watch(apiClientProvider);
  final cache = ref.watch(labOfflineCacheProvider);
  try {
    final trend = await api.fetchLabTrend(normalizedName);
    await cache.saveTrend(trend);
    return trend;
  } on Object {
    final cached = await cache.loadTrend(normalizedName);
    if (cached != null) return cached;
    rethrow;
  }
});

class HealthController {
  const HealthController(this.ref);

  final WidgetRef ref;

  Future<LabReportModel> upload({
    required Uint8List bytes,
    required String filename,
    required String contentType,
    required DateTime reportDate,
    required String sourceType,
    required bool retainOriginal,
    required bool allowRemoteOcr,
    String? hospitalName,
  }) async {
    final value = await ref.read(apiClientProvider).uploadLabReport(
          bytes: bytes,
          filename: filename,
          contentType: contentType,
          reportDate: reportDate,
          sourceType: sourceType,
          retainOriginal: retainOriginal,
          allowRemoteOcr: allowRemoteOcr,
          hospitalName: hospitalName,
        );
    ref.invalidate(healthReportsProvider);
    return value;
  }

  Future<LabReportModel> updateDraft(
    String reportId,
    LabDraftItemModel item, {
    required String testName,
    required String normalizedName,
    double? value,
    String? unit,
    double? referenceMin,
    double? referenceMax,
  }) {
    return ref.read(apiClientProvider).updateLabDraftItem(
          reportId: reportId,
          itemId: item.id,
          testName: testName,
          normalizedName: normalizedName,
          value: value,
          valueText: item.valueText,
          unit: unit,
          referenceMin: referenceMin,
          referenceMax: referenceMax,
          referenceText: item.referenceText,
        );
  }

  Future<LabReportModel> confirm(String reportId) async {
    final value = await ref.read(apiClientProvider).confirmLabReport(reportId);
    ref.invalidate(healthReportsProvider);
    for (final result in value.results) {
      ref.invalidate(labTrendProvider(result.normalizedName));
    }
    return value;
  }

  Future<void> deleteReport(String reportId) async {
    await ref.read(apiClientProvider).deleteLabReport(reportId);
    ref.invalidate(healthReportsProvider);
  }
}

class HealthChatMessage {
  const HealthChatMessage({
    required this.text,
    required this.fromUser,
    this.evidence = const [],
    this.riskLevel = 'normal',
    this.medicalBoundary = false,
  });

  final String text;
  final bool fromUser;
  final List<HealthEvidenceModel> evidence;
  final String riskLevel;
  final bool medicalBoundary;
}

final healthChatProvider =
    AsyncNotifierProvider<HealthChatController, List<HealthChatMessage>>(
  HealthChatController.new,
);

class HealthChatController extends AsyncNotifier<List<HealthChatMessage>> {
  String? _conversationId;

  @override
  Future<List<HealthChatMessage>> build() async => const [];

  Future<void> send(String raw) async {
    final message = raw.trim();
    if (message.isEmpty || state.isLoading) return;
    state = AsyncData([
      ...(state.valueOrNull ?? const []),
      HealthChatMessage(text: message, fromUser: true),
    ]);
    try {
      final reply = await ref.read(apiClientProvider).sendHealthMessage(
            message,
            conversationId: _conversationId,
          );
      _conversationId = reply.conversationId;
      state = AsyncData([
        ...(state.valueOrNull ?? const []),
        HealthChatMessage(
          text: reply.answer,
          fromUser: false,
          evidence: reply.evidence,
          riskLevel: reply.riskLevel,
          medicalBoundary: reply.medicalBoundary,
        ),
      ]);
    } on Object catch (error, stack) {
      state = AsyncError(error, stack);
    }
  }
}

final knowledgeSearchProvider =
    AsyncNotifierProvider<KnowledgeSearchController, List<HealthEvidenceModel>>(
  KnowledgeSearchController.new,
);

class KnowledgeSearchController
    extends AsyncNotifier<List<HealthEvidenceModel>> {
  @override
  Future<List<HealthEvidenceModel>> build() async => const [];

  Future<void> search(String raw) async {
    final query = raw.trim();
    if (query.length < 2) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(apiClientProvider).searchHealthKnowledge(query),
    );
  }
}
