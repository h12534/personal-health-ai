import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../core/files/ios_document_picker.dart';
import '../../coach/presentation/coach_screen.dart';
import '../data/health_models.dart';
import 'health_controller.dart';

class HealthScreen extends ConsumerStatefulWidget {
  const HealthScreen({super.key});

  @override
  ConsumerState<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends ConsumerState<HealthScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('health-screen'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('健康',
                        style: Theme.of(context).textTheme.headlineMedium),
                    const Text('体检趋势与可靠证据，不做自动诊断。'),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'AI 饮食教练',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(
                      body: SafeArea(child: CoachScreen()),
                    ),
                  ),
                ),
                icon: const Icon(Icons.restaurant_menu),
              ),
            ],
          ),
        ),
        TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: const [
            Tab(text: '概览'),
            Tab(text: '体检报告'),
            Tab(text: '健康知识'),
            Tab(text: '健康 AI'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _OverviewTab(
                  onOpenReports: () => _tabs.animateTo(1), onAsk: _ask),
              _ReportsTab(
                uploading: _uploading,
                onUpload: _chooseUpload,
                onAsk: _ask,
              ),
              const _KnowledgeTab(),
              const _HealthChatTab(),
            ],
          ),
        ),
      ],
    );
  }

  void _ask(LabResultModel result) {
    _tabs.animateTo(3);
    ref.read(healthChatProvider.notifier).send(
        '${result.testName} ${result.displayValue} ${result.unit ?? ''} 是什么意思？');
  }

  Future<void> _chooseUpload() async {
    final source = await showModalBottomSheet<_UploadSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            const ListTile(
              title: Text('上传体检报告'),
              subtitle: Text('识别结果只生成草稿，确认后才保存为正式指标。'),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('拍照'),
              onTap: () => Navigator.pop(context, _UploadSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('从相册选择'),
              onTap: () => Navigator.pop(context, _UploadSource.photos),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('从 Files 选择 PDF'),
              onTap: () => Navigator.pop(context, _UploadSource.files),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    try {
      setState(() => _uploading = true);
      final selected = await _pick(source);
      if (selected == null || !mounted) return;
      final options = await _uploadOptions();
      if (options == null || !mounted) return;
      final report = await HealthController(ref).upload(
        bytes: selected.bytes,
        filename: selected.filename,
        contentType: selected.contentType,
        reportDate: options.reportDate,
        sourceType: source.name,
        retainOriginal: options.retainOriginal,
        allowRemoteOcr: options.allowRemoteOcr,
        hospitalName: options.hospitalName,
      );
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => LabReviewSheet(
          report: report,
          onUpdate: (item, edit) => HealthController(ref).updateDraft(
            report.id,
            item,
            testName: edit.testName,
            normalizedName: edit.normalizedName,
            value: edit.value,
            unit: edit.unit,
            referenceMin: edit.referenceMin,
            referenceMax: edit.referenceMax,
          ),
          onConfirm: () => HealthController(ref).confirm(report.id),
        ),
      );
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<_SelectedUpload?> _pick(_UploadSource source) async {
    if (source == _UploadSource.files) {
      final file = await const IosDocumentPicker().pickPdf();
      if (file == null) return null;
      return _SelectedUpload(file.bytes, file.name, 'application/pdf');
    }
    final image = await ImagePicker().pickImage(
      source: source == _UploadSource.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      imageQuality: 92,
      maxWidth: 3000,
    );
    if (image == null) return null;
    final extension = image.name.toLowerCase();
    final type = extension.endsWith('.png')
        ? 'image/png'
        : extension.endsWith('.webp')
            ? 'image/webp'
            : 'image/jpeg';
    return _SelectedUpload(await image.readAsBytes(), image.name, type);
  }

  Future<_LabUploadOptions?> _uploadOptions() async {
    var retainOriginal = true;
    var allowRemoteOcr = false;
    var reportDate = DateTime.now();
    String? hospitalName;
    return showDialog<_LabUploadOptions>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('报告隐私'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('长期保留原文件'),
                subtitle: const Text('关闭后会在你确认指标时删除原图或 PDF。'),
                value: retainOriginal,
                onChanged: (value) =>
                    setDialogState(() => retainOriginal = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('允许本次第三方 OCR'),
                subtitle: const Text('仅在服务器配置了远程 OCR 时发送；默认关闭。'),
                value: allowRemoteOcr,
                onChanged: (value) =>
                    setDialogState(() => allowRemoteOcr = value),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('体检日期'),
                subtitle: Text(DateFormat('yyyy-MM-dd').format(reportDate)),
                trailing: const Icon(Icons.calendar_month_outlined),
                onTap: () async {
                  final selected = await showDatePicker(
                    context: context,
                    initialDate: reportDate,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now(),
                  );
                  if (selected != null) {
                    setDialogState(() => reportDate = selected);
                  }
                },
              ),
              TextFormField(
                decoration: const InputDecoration(labelText: '医院（可选）'),
                onChanged: (value) =>
                    hospitalName = value.trim().isEmpty ? null : value.trim(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                _LabUploadOptions(
                  retainOriginal,
                  allowRemoteOcr,
                  reportDate,
                  hospitalName,
                ),
              ),
              child: const Text('继续上传'),
            ),
          ],
        ),
      ),
    );
  }
}

enum _UploadSource { camera, photos, files }

class _SelectedUpload {
  const _SelectedUpload(this.bytes, this.filename, this.contentType);

  final Uint8List bytes;
  final String filename;
  final String contentType;
}

class _LabUploadOptions {
  const _LabUploadOptions(
    this.retainOriginal,
    this.allowRemoteOcr,
    this.reportDate,
    this.hospitalName,
  );

  final bool retainOriginal;
  final bool allowRemoteOcr;
  final DateTime reportDate;
  final String? hospitalName;
}

class _OverviewTab extends ConsumerWidget {
  const _OverviewTab({required this.onOpenReports, required this.onAsk});

  final VoidCallback onOpenReports;
  final ValueChanged<LabResultModel> onAsk;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reports = ref.watch(healthReportsProvider);
    return RefreshIndicator(
      onRefresh: () => ref.refresh(healthReportsProvider.future),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: ListTile(
              leading: const Icon(Icons.health_and_safety_outlined),
              title: const Text('个人健康时间线'),
              subtitle: const Text('体重、睡眠、训练和体检只描述共同变化，不轻易断言因果。'),
            ),
          ),
          const SizedBox(height: 12),
          ...switch (reports) {
            AsyncData(:final value) when value.isEmpty => [
                _EmptyReports(onPressed: onOpenReports),
              ],
            AsyncData(:final value) => [
                _LatestReportCard(report: value.first, onAsk: onAsk),
              ],
            AsyncError(:final error) => [
                Text('暂时无法读取体检记录：$error'),
              ],
            _ => [const Center(child: CircularProgressIndicator())],
          },
          const SizedBox(height: 12),
          const Card(
            child: ListTile(
              leading: Icon(Icons.verified_user_outlined),
              title: Text('医疗安全边界'),
              subtitle: Text('危急症状优先就医；AI 不确诊、不改药，也不会因轻度异常罗列严重疾病。'),
            ),
          ),
        ],
      ),
    );
  }
}

class _LatestReportCard extends StatelessWidget {
  const _LatestReportCard({required this.report, required this.onAsk});

  final LabReportModel report;
  final ValueChanged<LabResultModel> onAsk;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('上次体检', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(DateFormat('yyyy-MM-dd').format(report.reportDate)),
            Text('需要关注 ${report.attentionCount} 项 · 以报告参考范围为准'),
            const Divider(height: 24),
            ...report.results.take(4).map(
                  (item) => _LabResultTile(result: item, onAsk: onAsk),
                ),
          ],
        ),
      ),
    );
  }
}

class _EmptyReports extends StatelessWidget {
  const _EmptyReports({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Icon(Icons.description_outlined, size: 36),
              const SizedBox(height: 8),
              const Text('还没有已保存的体检报告'),
              const SizedBox(height: 12),
              FilledButton.tonal(
                  onPressed: onPressed, child: const Text('去上传')),
            ],
          ),
        ),
      );
}

class _ReportsTab extends ConsumerWidget {
  const _ReportsTab({
    required this.uploading,
    required this.onUpload,
    required this.onAsk,
  });

  final bool uploading;
  final VoidCallback onUpload;
  final ValueChanged<LabResultModel> onAsk;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reports = ref.watch(healthReportsProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('upload-lab-report'),
              onPressed: uploading ? null : onUpload,
              icon: uploading
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_file),
              label: Text(uploading ? '识别中…' : '上传体检报告'),
            ),
          ),
        ),
        Expanded(
          child: switch (reports) {
            AsyncData(:final value) => value.isEmpty
                ? const Center(child: Text('支持拍照、相册图片和多页 PDF'))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                    itemCount: value.length,
                    itemBuilder: (context, index) => _ReportCard(
                      report: value[index],
                      onAsk: onAsk,
                      onReview: () => showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        showDragHandle: true,
                        builder: (_) => LabReviewSheet(
                          report: value[index],
                          onUpdate: (item, edit) =>
                              HealthController(ref).updateDraft(
                            value[index].id,
                            item,
                            testName: edit.testName,
                            normalizedName: edit.normalizedName,
                            value: edit.value,
                            unit: edit.unit,
                            referenceMin: edit.referenceMin,
                            referenceMax: edit.referenceMax,
                          ),
                          onConfirm: () =>
                              HealthController(ref).confirm(value[index].id),
                        ),
                      ),
                      onDelete: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('删除体检报告？'),
                            content: const Text(
                              '原文件会被删除，关联指标将不再出现在趋势和健康 AI 中。',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('取消'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('确认删除'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed == true) {
                          await HealthController(ref)
                              .deleteReport(value[index].id);
                        }
                      },
                    ),
                  ),
            AsyncError(:final error) => Center(child: Text(error.toString())),
            _ => const Center(child: CircularProgressIndicator()),
          },
        ),
      ],
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.report,
    required this.onAsk,
    required this.onReview,
    required this.onDelete,
  });

  final LabReportModel report;
  final ValueChanged<LabResultModel> onAsk;
  final VoidCallback onReview;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Card(
        child: ExpansionTile(
          leading: const Icon(Icons.biotech_outlined),
          title: Text(DateFormat('yyyy-MM-dd').format(report.reportDate)),
          subtitle: Text(
            report.reviewStatus == 'confirmed'
                ? '${report.results.length} 项已确认 · ${report.attentionCount} 项需关注'
                : '${report.draftItems.length} 项待确认',
          ),
          trailing: PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'delete') onDelete();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'delete', child: Text('删除报告与关联指标')),
            ],
          ),
          children: [
            if (report.reviewStatus == 'draft')
              ListTile(
                leading: const Icon(Icons.fact_check_outlined),
                title: const Text('OCR 草稿尚未确认'),
                trailing: FilledButton.tonal(
                  key: const Key('resume-lab-draft'),
                  onPressed: onReview,
                  child: const Text('继续核对'),
                ),
              ),
            ...report.results.map(
              (item) => _LabResultTile(result: item, onAsk: onAsk),
            ),
          ],
        ),
      );
}

class _LabResultTile extends ConsumerWidget {
  const _LabResultTile({required this.result, required this.onAsk});

  final LabResultModel result;
  final ValueChanged<LabResultModel> onAsk;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListTile(
        key: Key('lab-result-${result.normalizedName}'),
        contentPadding: EdgeInsets.zero,
        leading: _FlagDot(flag: result.flag),
        title: Text(result.testName),
        subtitle: Text('参考：${result.referenceDisplay}'),
        trailing: Text('${result.displayValue} ${result.unit ?? ''}'),
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) =>
              _IndicatorDetail(result: result, onAsk: () => onAsk(result)),
        ),
      );
}

class _FlagDot extends StatelessWidget {
  const _FlagDot({required this.flag});

  final String flag;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (flag) {
      'high' || 'low' => Colors.amber.shade700,
      'critical' => scheme.error,
      'normal' => scheme.primary,
      _ => scheme.outline,
    };
    return Icon(Icons.circle, size: 12, color: color);
  }
}

class _IndicatorDetail extends ConsumerWidget {
  const _IndicatorDetail({required this.result, required this.onAsk});

  final LabResultModel result;
  final VoidCallback onAsk;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trend = ref.watch(labTrendProvider(result.normalizedName));
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(result.testName,
                style: Theme.of(context).textTheme.headlineSmall),
            Text('当前 ${result.displayValue} ${result.unit ?? ''}'),
            Text('本报告参考范围：${result.referenceDisplay}'),
            const SizedBox(height: 18),
            SizedBox(
              height: 150,
              width: double.infinity,
              child: switch (trend) {
                AsyncData(:final value) => LabTrendChart(trend: value),
                AsyncError() => const Center(child: Text('暂无可比较的历史趋势')),
                _ => const Center(child: CircularProgressIndicator()),
              },
            ),
            const SizedBox(height: 12),
            const Text('趋势只描述时间上的共同变化，不代表因果关系。'),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                key: const Key('ask-about-indicator'),
                onPressed: () {
                  Navigator.pop(context);
                  onAsk();
                },
                icon: const Icon(Icons.auto_awesome_outlined),
                label: const Text('这个指标是什么意思？'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LabTrendChart extends StatelessWidget {
  const LabTrendChart({super.key, required this.trend});

  final LabTrendModel trend;

  @override
  Widget build(BuildContext context) => CustomPaint(
        key: const Key('lab-trend-chart'),
        painter: _TrendPainter(
          points: trend.points.map((point) => point.value).toList(),
          color: Theme.of(context).colorScheme.primary,
        ),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Text('${trend.points.length} 次记录 · ${trend.canonicalUnit}'),
        ),
      );
}

class _TrendPainter extends CustomPainter {
  const _TrendPainter({required this.points, required this.color});

  final List<double> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final minimum = points.reduce(math.min);
    final maximum = points.reduce(math.max);
    final spread = math.max(0.001, maximum - minimum);
    final path = Path();
    for (var index = 0; index < points.length; index++) {
      final x = points.length == 1
          ? size.width / 2
          : size.width * index / (points.length - 1);
      final y =
          16 + (size.height - 52) * (1 - (points[index] - minimum) / spread);
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      canvas.drawCircle(Offset(x, y), 4, Paint()..color = color);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.color != color;
}

class LabReviewSheet extends StatefulWidget {
  const LabReviewSheet({
    super.key,
    required this.report,
    required this.onUpdate,
    required this.onConfirm,
  });

  final LabReportModel report;
  final Future<LabReportModel> Function(LabDraftItemModel, LabDraftEdit)
      onUpdate;
  final Future<LabReportModel> Function() onConfirm;

  @override
  State<LabReviewSheet> createState() => _LabReviewSheetState();
}

class _LabReviewSheetState extends State<LabReviewSheet> {
  late LabReportModel _report = widget.report;
  bool _saving = false;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .82,
          child: Column(
            children: [
              ListTile(
                title: const Text('核对识别草稿'),
                subtitle: Text('${_report.draftItems.length} 项 · 修改后再确认'),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _report.draftItems.length,
                  itemBuilder: (context, index) {
                    final item = _report.draftItems[index];
                    return Card(
                      key: Key('lab-draft-${item.normalizedName}'),
                      child: ListTile(
                        leading: _FlagDot(flag: item.flag),
                        title: Text(item.testName),
                        subtitle: Text(
                          '${item.displayValue} ${item.unit ?? ''}\n参考：${item.referenceDisplay}',
                        ),
                        isThreeLine: true,
                        trailing: TextButton(
                          onPressed: _saving ? null : () => _edit(item),
                          child: const Text('修改'),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const Key('confirm-lab-draft'),
                    onPressed: _saving ? null : _confirm,
                    child: Text(_saving ? '保存中…' : '确认全部并保存'),
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  Future<void> _edit(LabDraftItemModel item) async {
    final edit = await showDialog<LabDraftEdit>(
      context: context,
      builder: (_) => _LabEditDialog(item: item),
    );
    if (edit == null) return;
    setState(() => _saving = true);
    try {
      _report = await widget.onUpdate(item, edit);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirm() async {
    setState(() => _saving = true);
    try {
      await widget.onConfirm();
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class LabDraftEdit {
  const LabDraftEdit({
    required this.testName,
    required this.normalizedName,
    this.value,
    this.unit,
    this.referenceMin,
    this.referenceMax,
  });

  final String testName;
  final String normalizedName;
  final double? value;
  final String? unit;
  final double? referenceMin;
  final double? referenceMax;
}

class _LabEditDialog extends StatefulWidget {
  const _LabEditDialog({required this.item});

  final LabDraftItemModel item;

  @override
  State<_LabEditDialog> createState() => _LabEditDialogState();
}

class _LabEditDialogState extends State<_LabEditDialog> {
  late final _name = TextEditingController(text: widget.item.testName);
  late final _normalized =
      TextEditingController(text: widget.item.normalizedName);
  late final _value =
      TextEditingController(text: widget.item.value?.toString() ?? '');
  late final _unit = TextEditingController(text: widget.item.unit ?? '');
  late final _minimum =
      TextEditingController(text: widget.item.referenceMin?.toString() ?? '');
  late final _maximum =
      TextEditingController(text: widget.item.referenceMax?.toString() ?? '');

  @override
  void dispose() {
    for (final controller in [
      _name,
      _normalized,
      _value,
      _unit,
      _minimum,
      _maximum
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('修改指标'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: '名称')),
              TextField(
                controller: _normalized,
                decoration: const InputDecoration(labelText: '标准化名称'),
              ),
              TextField(
                controller: _value,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: '数值'),
              ),
              TextField(
                  controller: _unit,
                  decoration: const InputDecoration(labelText: '单位')),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _minimum,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: '参考下限'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _maximum,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: '参考上限'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              LabDraftEdit(
                testName: _name.text.trim(),
                normalizedName: _normalized.text.trim(),
                value: double.tryParse(_value.text.trim()),
                unit: _unit.text.trim().isEmpty ? null : _unit.text.trim(),
                referenceMin: double.tryParse(_minimum.text.trim()),
                referenceMax: double.tryParse(_maximum.text.trim()),
              ),
            ),
            child: const Text('保存'),
          ),
        ],
      );
}

class _KnowledgeTab extends ConsumerStatefulWidget {
  const _KnowledgeTab();

  @override
  ConsumerState<_KnowledgeTab> createState() => _KnowledgeTabState();
}

class _KnowledgeTabState extends ConsumerState<_KnowledgeTab> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(knowledgeSearchProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        SearchBar(
          key: const Key('health-knowledge-search'),
          controller: _query,
          hintText: '蛋白质、胰岛素抵抗、体重波动…',
          leading: const Icon(Icons.search),
          trailing: [
            IconButton(
              onPressed: () => ref
                  .read(knowledgeSearchProvider.notifier)
                  .search(_query.text),
              icon: const Icon(Icons.arrow_forward),
            ),
          ],
          onSubmitted: ref.read(knowledgeSearchProvider.notifier).search,
        ),
        const SizedBox(height: 12),
        const Text('仅检索已导入并启用的可靠知识来源。'),
        const SizedBox(height: 12),
        ...switch (results) {
          AsyncData(:final value) when value.isEmpty => [
              const Card(child: ListTile(title: Text('输入问题开始检索'))),
            ],
          AsyncData(:final value) => value.map(_EvidenceCard.new),
          AsyncError(:final error) => [Text(error.toString())],
          _ => [const Center(child: CircularProgressIndicator())],
        },
      ],
    );
  }
}

class _EvidenceCard extends StatelessWidget {
  const _EvidenceCard(this.evidence);

  final HealthEvidenceModel evidence;

  @override
  Widget build(BuildContext context) => Card(
        child: ExpansionTile(
          title: Text(evidence.title),
          subtitle: Text(
            '${evidence.publisher}${evidence.year == null ? '' : ' · ${evidence.year}'}',
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Align(
                alignment: Alignment.centerLeft, child: Text(evidence.excerpt)),
            if (evidence.sourceUrl case final url?) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: SelectableText(url,
                    style: Theme.of(context).textTheme.bodySmall),
              ),
            ],
          ],
        ),
      );
}

class _HealthChatTab extends ConsumerStatefulWidget {
  const _HealthChatTab();

  @override
  ConsumerState<_HealthChatTab> createState() => _HealthChatTabState();
}

class _HealthChatTabState extends ConsumerState<_HealthChatTab> {
  final _message = TextEditingController();

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(healthChatProvider);
    final messages = chat.valueOrNull ?? const <HealthChatMessage>[];
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
            children: [
              const Card(
                child: ListTile(
                  leading: Icon(Icons.shield_outlined),
                  title: Text('证据 + 个人数据 + 安全规则'),
                  subtitle: Text('没有足够依据时会明确说明；不能替代医生诊断或处方。'),
                ),
              ),
              ...messages.map(_HealthMessageBubble.new),
              if (chat.isLoading) const LinearProgressIndicator(),
              if (chat.hasError) Text(chat.error.toString()),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('health-chat-input'),
                    controller: _message,
                    decoration: const InputDecoration(
                      hintText: '例如：我最近的减脂速度健康吗？',
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                IconButton(
                  key: const Key('send-health-chat'),
                  onPressed: _send,
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _send() {
    final value = _message.text;
    _message.clear();
    ref.read(healthChatProvider.notifier).send(value);
  }
}

class _HealthMessageBubble extends StatelessWidget {
  const _HealthMessageBubble(this.message);

  final HealthChatMessage message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment:
          message.fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: message.fromUser
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: message.riskLevel == 'urgent'
              ? Border.all(color: scheme.error, width: 2)
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message.text),
            if (message.medicalBoundary) ...[
              const SizedBox(height: 8),
              const Text('医疗边界：此回答不构成诊断或处方建议。'),
            ],
            if (message.evidence.isNotEmpty) ...[
              const Divider(height: 22),
              const Text('依据来源'),
              ...message.evidence.map(
                (item) => Text('• ${item.publisher}｜${item.title}'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
