double? _nullableNumber(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

class LabDraftItemModel {
  const LabDraftItemModel({
    required this.id,
    required this.testName,
    required this.normalizedName,
    required this.flag,
    required this.category,
    required this.confidence,
    required this.userModified,
    this.value,
    this.valueText,
    this.unit,
    this.referenceMin,
    this.referenceMax,
    this.referenceText,
  });

  factory LabDraftItemModel.fromJson(Map<String, dynamic> json) =>
      LabDraftItemModel(
        id: json['id'] as String,
        testName: json['test_name'] as String,
        normalizedName: json['normalized_name'] as String,
        value: _nullableNumber(json['value_numeric']),
        valueText: json['value_text'] as String?,
        unit: json['unit'] as String?,
        referenceMin: _nullableNumber(json['reference_min']),
        referenceMax: _nullableNumber(json['reference_max']),
        referenceText: json['reference_text'] as String?,
        flag: json['flag'] as String? ?? 'unknown',
        category: json['category'] as String? ?? 'other',
        confidence: _nullableNumber(json['confidence']) ?? 0,
        userModified: json['user_modified'] as bool? ?? false,
      );

  final String id;
  final String testName;
  final String normalizedName;
  final double? value;
  final String? valueText;
  final String? unit;
  final double? referenceMin;
  final double? referenceMax;
  final String? referenceText;
  final String flag;
  final String category;
  final double confidence;
  final bool userModified;

  String get displayValue =>
      value == null ? valueText ?? '—' : _formatNumber(value!);

  String get referenceDisplay {
    if (referenceText != null && referenceText!.isNotEmpty) {
      return referenceText!;
    }
    if (referenceMin != null && referenceMax != null) {
      return '${referenceMin!}–${referenceMax!}';
    }
    if (referenceMin != null) {
      return '≥ ${referenceMin!}';
    }
    if (referenceMax != null) {
      return '≤ ${referenceMax!}';
    }
    return '报告未提供';
  }
}

class LabResultModel {
  const LabResultModel({
    required this.id,
    required this.reportId,
    required this.testName,
    required this.normalizedName,
    required this.flag,
    required this.category,
    this.value,
    this.valueText,
    this.unit,
    this.referenceMin,
    this.referenceMax,
    this.referenceText,
  });

  factory LabResultModel.fromJson(Map<String, dynamic> json) => LabResultModel(
        id: json['id'] as String,
        reportId: json['report_id'] as String,
        testName: json['test_name'] as String,
        normalizedName: json['normalized_name'] as String,
        value: _nullableNumber(json['value_numeric']),
        valueText: json['value_text'] as String?,
        unit: json['unit'] as String?,
        referenceMin: _nullableNumber(json['reference_min']),
        referenceMax: _nullableNumber(json['reference_max']),
        referenceText: json['reference_text'] as String?,
        flag: json['flag'] as String? ?? 'unknown',
        category: json['category'] as String? ?? 'other',
      );

  final String id;
  final String reportId;
  final String testName;
  final String normalizedName;
  final double? value;
  final String? valueText;
  final String? unit;
  final double? referenceMin;
  final double? referenceMax;
  final String? referenceText;
  final String flag;
  final String category;

  String get displayValue =>
      value == null ? valueText ?? '—' : _formatNumber(value!);

  String get referenceDisplay {
    if (referenceText != null && referenceText!.isNotEmpty) {
      return referenceText!;
    }
    if (referenceMin != null && referenceMax != null) {
      return '${referenceMin!}–${referenceMax!}';
    }
    return '报告未提供';
  }
}

class LabReportModel {
  const LabReportModel({
    required this.id,
    required this.reportDate,
    required this.originalFilename,
    required this.ocrStatus,
    required this.reviewStatus,
    required this.retainOriginal,
    required this.draftItems,
    required this.results,
    this.hospitalName,
  });

  factory LabReportModel.fromJson(Map<String, dynamic> json) => LabReportModel(
        id: json['id'] as String,
        reportDate: DateTime.parse(json['report_date'] as String),
        hospitalName: json['hospital_name'] as String?,
        originalFilename: json['original_filename'] as String,
        ocrStatus: json['ocr_status'] as String,
        reviewStatus: json['review_status'] as String,
        retainOriginal: json['retain_original'] as bool? ?? true,
        draftItems: (json['draft_items'] as List<dynamic>? ?? const [])
            .map((item) =>
                LabDraftItemModel.fromJson(item as Map<String, dynamic>))
            .toList(),
        results: (json['results'] as List<dynamic>? ?? const [])
            .map(
                (item) => LabResultModel.fromJson(item as Map<String, dynamic>))
            .toList(),
      );

  final String id;
  final DateTime reportDate;
  final String? hospitalName;
  final String originalFilename;
  final String ocrStatus;
  final String reviewStatus;
  final bool retainOriginal;
  final List<LabDraftItemModel> draftItems;
  final List<LabResultModel> results;

  int get attentionCount =>
      results.where((item) => item.flag == 'high' || item.flag == 'low').length;

  Map<String, dynamic> toJson() => {
        'id': id,
        'report_date': reportDate.toIso8601String().substring(0, 10),
        'hospital_name': hospitalName,
        'original_filename': originalFilename,
        'ocr_status': ocrStatus,
        'review_status': reviewStatus,
        'retain_original': retainOriginal,
        'draft_items': const <Object>[],
        'results': results
            .map(
              (item) => {
                'id': item.id,
                'report_id': item.reportId,
                'test_name': item.testName,
                'normalized_name': item.normalizedName,
                'value_numeric': item.value,
                'value_text': item.valueText,
                'unit': item.unit,
                'reference_min': item.referenceMin,
                'reference_max': item.referenceMax,
                'reference_text': item.referenceText,
                'flag': item.flag,
                'category': item.category,
              },
            )
            .toList(),
      };
}

class LabTrendPointModel {
  const LabTrendPointModel({
    required this.reportId,
    required this.date,
    required this.value,
    required this.unit,
    required this.flag,
    this.referenceMin,
    this.referenceMax,
  });

  factory LabTrendPointModel.fromJson(Map<String, dynamic> json) =>
      LabTrendPointModel(
        reportId: json['report_id'] as String,
        date: DateTime.parse(json['report_date'] as String),
        value: _nullableNumber(json['value']) ?? 0,
        unit: json['unit'] as String,
        flag: json['flag'] as String? ?? 'unknown',
        referenceMin: _nullableNumber(json['reference_min']),
        referenceMax: _nullableNumber(json['reference_max']),
      );

  final String reportId;
  final DateTime date;
  final double value;
  final String unit;
  final String flag;
  final double? referenceMin;
  final double? referenceMax;
}

class LabTrendModel {
  const LabTrendModel({
    required this.normalizedName,
    required this.displayName,
    required this.canonicalUnit,
    required this.points,
  });

  factory LabTrendModel.fromJson(Map<String, dynamic> json) => LabTrendModel(
        normalizedName: json['normalized_name'] as String,
        displayName: json['display_name'] as String,
        canonicalUnit: json['canonical_unit'] as String,
        points: (json['points'] as List<dynamic>? ?? const [])
            .map((item) =>
                LabTrendPointModel.fromJson(item as Map<String, dynamic>))
            .toList(),
      );

  final String normalizedName;
  final String displayName;
  final String canonicalUnit;
  final List<LabTrendPointModel> points;

  Map<String, dynamic> toJson() => {
        'normalized_name': normalizedName,
        'display_name': displayName,
        'canonical_unit': canonicalUnit,
        'points': points
            .map(
              (point) => {
                'report_id': point.reportId,
                'report_date': point.date.toIso8601String().substring(0, 10),
                'value': point.value,
                'unit': point.unit,
                'flag': point.flag,
                'reference_min': point.referenceMin,
                'reference_max': point.referenceMax,
              },
            )
            .toList(),
      };
}

class HealthEvidenceModel {
  const HealthEvidenceModel({
    required this.title,
    required this.publisher,
    required this.excerpt,
    required this.category,
    this.year,
    this.heading,
    this.sourceUrl,
  });

  factory HealthEvidenceModel.fromJson(Map<String, dynamic> json) =>
      HealthEvidenceModel(
        title: json['title'] as String,
        publisher: json['publisher'] as String,
        year: json['year'] as int?,
        heading: json['heading'] as String?,
        sourceUrl: json['source_url'] as String?,
        excerpt: json['excerpt'] as String? ?? '',
        category: json['category'] as String? ?? '',
      );

  final String title;
  final String publisher;
  final int? year;
  final String? heading;
  final String? sourceUrl;
  final String excerpt;
  final String category;
}

class HealthChatReplyModel {
  const HealthChatReplyModel({
    required this.conversationId,
    required this.intent,
    required this.answer,
    required this.evidence,
    required this.personalContextUsed,
    required this.riskLevel,
    required this.medicalBoundary,
    required this.actions,
  });

  factory HealthChatReplyModel.fromJson(Map<String, dynamic> json) =>
      HealthChatReplyModel(
        conversationId: json['conversation_id'] as String,
        intent: json['intent'] as String,
        answer: json['answer'] as String,
        evidence: (json['evidence'] as List<dynamic>? ?? const [])
            .map((item) =>
                HealthEvidenceModel.fromJson(item as Map<String, dynamic>))
            .toList(),
        personalContextUsed:
            (json['personal_context_used'] as List<dynamic>? ?? const [])
                .map((item) => item.toString())
                .toList(),
        riskLevel: json['risk_level'] as String? ?? 'normal',
        medicalBoundary: json['medical_boundary'] as bool? ?? false,
        actions: (json['suggested_actions'] as List<dynamic>? ?? const [])
            .map((item) => item as Map<String, dynamic>)
            .toList(),
      );

  final String conversationId;
  final String intent;
  final String answer;
  final List<HealthEvidenceModel> evidence;
  final List<String> personalContextUsed;
  final String riskLevel;
  final bool medicalBoundary;
  final List<Map<String, dynamic>> actions;
}

String _formatNumber(double value) => value
    .toStringAsFixed(3)
    .replaceFirst(RegExp(r'0+$'), '')
    .replaceFirst(RegExp(r'\.$'), '');
