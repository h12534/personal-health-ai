import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/files/ios_document_picker.dart';
import '../../../core/config/app_config.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_components.dart';
import '../../profile/presentation/health_sync_screen.dart';
import '../../coach/presentation/coach_screen.dart';
import '../data/health_models.dart';
import 'health_controller.dart';
import 'health_overview_content.dart';
import 'health_trend_chart.dart';

class HealthScreen extends ConsumerStatefulWidget {
  const HealthScreen(
      {super.key, this.overviewVariant = HealthOverviewVariant.dataForward});
  final HealthOverviewVariant overviewVariant;

  @override
  ConsumerState<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends ConsumerState<HealthScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool _uploading = false;
  bool _asking = false;
  String? _indicatorQuestion;
  int _promptVersion = 0;

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
        if (AppConfig.appleHealthDisabled) const PersonalManualHealthNotice(),
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.page, AppSpacing.lg, AppSpacing.md, AppSpacing.sm),
          child: RootPageHeader(
              title: '健康',
              subtitle: '你的记录，逐步看清。',
              action: IconButton(
                tooltip: 'AI 饮食教练',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(
                      body: SafeArea(child: CoachScreen()),
                    ),
                  ),
                ),
                icon: const Icon(Icons.restaurant_menu),
              )),
        ),
        TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          dividerColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          indicatorSize: TabBarIndicatorSize.tab,
          indicator: BoxDecoration(
              color: AppColors.of(context).softTint,
              borderRadius: BorderRadius.circular(AppRadius.small)),
          indicatorPadding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          labelColor: AppColors.of(context).primary,
          unselectedLabelColor: AppColors.of(context).secondaryText,
          labelStyle: Theme.of(context).textTheme.labelMedium,
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
                  variant: widget.overviewVariant,
                  onOpenReports: () =>
                      _tabs.animateTo(1, duration: AppMotion.duration(context)),
                  onAsk: _ask),
              _ReportsTab(
                uploading: _uploading,
                onUpload: _chooseUpload,
                onAsk: _ask,
              ),
              const _KnowledgeTab(),
              _HealthChatTab(
                  externalSending: _asking,
                  prompt: _indicatorQuestion,
                  promptVersion: _promptVersion,
                  onBusyChanged: (busy) {
                    if (mounted) setState(() => _asking = busy);
                  }),
            ],
          ),
        ),
      ],
    );
  }

  void _ask(LabResultModel result) {
    if (_asking) return;
    setState(() {
      _asking = true;
      _indicatorQuestion =
          '${result.testName} ${result.displayValue} ${result.unit ?? ''} 是什么意思？';
      _promptVersion++;
    });
    _tabs.animateTo(3, duration: AppMotion.duration(context));
  }

  Future<void> _chooseUpload() async {
    if (_uploading) return;
    setState(() => _uploading = true);
    try {
      final source = await showModalBottomSheet<_UploadSource>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: SingleChildScrollView(
              child: Column(
            mainAxisSize: MainAxisSize.min,
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
          )),
        ),
      );
      if (source == null) return;
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
          SnackBar(content: Text(UiFailure.message(error))),
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
          scrollable: true,
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
                subtitle: Text(AppFormat.fullDate(reportDate)),
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
  const _OverviewTab(
      {required this.onOpenReports,
      required this.onAsk,
      required this.variant});
  final HealthOverviewVariant variant;

  final VoidCallback onOpenReports;
  final ValueChanged<LabResultModel> onAsk;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reports = ref.watch(healthReportsProvider);
    return RefreshIndicator(
      onRefresh: () => ref.refresh(healthReportsProvider.future),
      child: ListView(
        key: const Key('health-overview-list'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: AppSpacing.pageInsets,
        children: [
          ...switch (reports) {
            AsyncData(:final value) when value.isEmpty => [
                _EmptyReports(onPressed: onOpenReports),
              ],
            AsyncData(:final value) => [
                if (value
                    .any((report) => report.reviewStatus != 'confirmed')) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('有体检草稿待核对'),
                    subtitle: const Text('确认之前不会作为正式指标展示。'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: onOpenReports,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
                if (value.any((report) => report.reviewStatus == 'confirmed'))
                  _ConfirmedOverview(
                    report: value.firstWhere(
                        (report) => report.reviewStatus == 'confirmed'),
                    onOpenReports: onOpenReports,
                    onAsk: onAsk,
                    variant: variant,
                  )
                else
                  _EmptyReports(onPressed: onOpenReports),
              ],
            AsyncError(:final error) => [
                ErrorState(
                    inline: true,
                    error: error,
                    title: '体检记录暂时无法读取',
                    actionLabel: '重新读取体检记录',
                    onRetry: () => ref.invalidate(healthReportsProvider))
              ],
            _ => [const HealthSkeleton()],
          },
        ],
      ),
    );
  }
}

class _ConfirmedOverview extends ConsumerWidget {
  const _ConfirmedOverview(
      {required this.report,
      required this.onAsk,
      required this.onOpenReports,
      required this.variant});
  final HealthOverviewVariant variant;

  final LabReportModel report;
  final ValueChanged<LabResultModel> onAsk;
  final VoidCallback onOpenReports;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final focus = overviewFocus(report);
    final trend = focus == null || focus.value == null
        ? null
        : ref.watch(labTrendProvider(focus.normalizedName));
    return HealthOverviewContent(
      report: report,
      variant: variant,
      trend: trend?.valueOrNull,
      trendLoading: trend?.isLoading ?? false,
      onOpenReports: onOpenReports,
      onAsk: onAsk,
      onRetryTrend: trend?.hasError == true && focus != null
          ? () => ref.invalidate(labTrendProvider(focus.normalizedName))
          : null,
      onOpenIndicator: (result) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        useSafeArea: true,
        builder: (_) =>
            _IndicatorDetail(result: result, onAsk: () => onAsk(result)),
      ),
    );
  }
}

class _EmptyReports extends StatelessWidget {
  const _EmptyReports({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => EmptyState(
      title: '还没有已保存的体检报告',
      message: '上传图片或 PDF，核对识别草稿后，指标会保存在这里。',
      actionLabel: '去上传',
      onAction: onPressed,
      icon: Icons.description_outlined);
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
              icon: const Icon(Icons.upload_file_outlined),
              label: Text(uploading ? '识别中…' : '上传体检报告'),
            ),
          ),
        ),
        Expanded(
          child: switch (reports) {
            AsyncData(:final value) => value.isEmpty
                ? ListView(padding: AppSpacing.pageInsets, children: [
                    EmptyState(
                        title: '还没有体检报告',
                        message: '支持拍照、相册图片和多页 PDF。识别草稿经你确认后才成为正式指标。',
                        actionLabel: '上传第一份报告',
                        onAction: uploading ? null : onUpload)
                  ])
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                    itemCount: value.length,
                    itemBuilder: (context, index) => _ReportCard(
                      key: ValueKey(value[index].id),
                      onReload: () => ref.invalidate(healthReportsProvider),
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
                            scrollable: true,
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
            AsyncError(:final error) => ErrorState(
                error: error,
                onRetry: () => ref.invalidate(healthReportsProvider)),
            _ => const LoadingState(label: '正在读取体检报告'),
          },
        ),
      ],
    );
  }
}

class _ReportCard extends StatefulWidget {
  const _ReportCard(
      {super.key,
      required this.report,
      required this.onAsk,
      required this.onReview,
      required this.onDelete,
      required this.onReload});
  final LabReportModel report;
  final ValueChanged<LabResultModel> onAsk;
  final VoidCallback onReview;
  final Future<void> Function() onDelete;
  final VoidCallback onReload;
  @override
  State<_ReportCard> createState() => _ReportCardState();
}

class _ReportCardState extends State<_ReportCard> {
  bool _deleting = false;
  Object? _error;
  Future<void> _delete() async {
    if (_deleting) return;
    setState(() {
      _deleting = true;
      _error = null;
    });
    try {
      await widget.onDelete();
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ExpansionTile(
            tilePadding: EdgeInsets.zero,
            leading: const Icon(Icons.biotech_outlined),
            title: Text(AppFormat.fullDate(widget.report.reportDate)),
            subtitle: Text(_deleting
                ? '正在确认删除结果…'
                : widget.report.reviewStatus == 'confirmed'
                    ? '${widget.report.results.length} 项已确认 · ${widget.report.attentionCount} 项需关注'
                    : '${widget.report.draftItems.length} 项待确认'),
            trailing: PopupMenuButton<String>(
                tooltip: '报告操作',
                enabled: !_deleting,
                onSelected: (value) {
                  if (value == 'delete') _delete();
                },
                itemBuilder: (_) => const [
                      PopupMenuItem(value: 'delete', child: Text('删除报告与关联指标'))
                    ]),
            children: [
              if (widget.report.reviewStatus == 'draft')
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('OCR 草稿尚未确认'),
                          const SizedBox(height: 8),
                          FilledButton.tonal(
                              key: const Key('resume-lab-draft'),
                              onPressed: _deleting ? null : widget.onReview,
                              child: const Text('继续核对')),
                        ])),
              for (final item in widget.report.results)
                _LabResultTile(result: item, onAsk: widget.onAsk),
            ]),
        if (_error != null)
          Semantics(
              liveRegion: true,
              child: Text('${UiFailure.title(_error!)}。请重新读取报告后再决定是否重试。',
                  style: AppTypography.secondary
                      .copyWith(color: AppColors.of(context).danger))),
        if (_error != null)
          TextButton(
              onPressed: _deleting ? null : widget.onReload,
              child: const Text('重新读取报告')),
      ]);
}

class _LabResultTile extends ConsumerWidget {
  const _LabResultTile({required this.result, required this.onAsk});

  final LabResultModel result;
  final ValueChanged<LabResultModel> onAsk;

  @override
  Widget build(BuildContext context, WidgetRef ref) => HealthMetricRow(
        result: result,
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          useSafeArea: true,
          builder: (_) =>
              _IndicatorDetail(result: result, onAsk: () => onAsk(result)),
        ),
      );
}

class _FlagDot extends StatelessWidget {
  const _FlagDot({required this.flag});
  final String flag;
  @override
  Widget build(BuildContext context) => Semantics(
        label: labFlagLabel(flag),
        child: Icon(
            flag == 'normal' ? Icons.check_circle_outline : Icons.info_outline,
            size: AppIconSize.small,
            color: labFlagColor(AppColors.of(context), flag)),
      );
}

class _IndicatorDetail extends ConsumerWidget {
  const _IndicatorDetail({required this.result, required this.onAsk});

  final LabResultModel result;
  final VoidCallback onAsk;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trend = ref.watch(labTrendProvider(result.normalizedName));
    return SafeArea(
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .85),
        child: SingleChildScrollView(
          padding: AppSpacing.pageInsets,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DataDetailHeader(
                  title: result.testName,
                  value: result.displayValue,
                  unit: result.unit ?? '',
                  status: labFlagLabel(result.flag),
                  statusColor: labFlagColor(AppColors.of(context), result.flag),
                  reference:
                      '本报告参考范围：${result.referenceDisplay} ${result.unit ?? ''}'),
              const SizedBox(height: 18),
              switch (trend) {
                AsyncData(:final value) => LabTrendChart(trend: value),
                AsyncError(:final error) => ErrorState(
                    inline: true,
                    error: error,
                    title: '历史趋势暂时无法读取',
                    onRetry: () => ref
                        .invalidate(labTrendProvider(result.normalizedName))),
                _ => const HealthSkeleton(label: '正在读取历史记录', compact: true),
              },
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
      ),
    );
  }
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
  Object? _error;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: PopScope(
            canPop: !_saving,
            child: SizedBox(
              height: (MediaQuery.sizeOf(context).height -
                      MediaQuery.viewInsetsOf(context).bottom) *
                  .82,
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
                        return Padding(
                          key: Key('lab-draft-${item.normalizedName}'),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.testName,
                                    style: AppTypography.cardTitle),
                                const SizedBox(height: 8),
                                Text(
                                  '${item.displayValue} ${item.unit ?? ''}\n参考：${item.referenceDisplay}',
                                ),
                                Row(children: [
                                  _FlagDot(flag: item.flag),
                                  const SizedBox(width: 8),
                                  Expanded(
                                      child: Text(labFlagLabel(item.flag),
                                          style: AppTypography.caption))
                                ]),
                                TextButton(
                                  onPressed: _saving ? null : () => _edit(item),
                                  child: const Text('修改'),
                                ),
                              ]),
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
                  if (_error != null)
                    Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Semantics(
                            liveRegion: true,
                            child: Text(
                                '${UiFailure.title(_error!)}。草稿已保留，请重试。',
                                style: AppTypography.secondary.copyWith(
                                    color: AppColors.of(context).danger)))),
                ],
              ),
            )),
      );

  Future<void> _edit(LabDraftItemModel item) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final updated = await showDialog<LabReportModel>(
          context: context,
          barrierDismissible: false,
          builder: (_) => LabEditDialog(
              item: item, onSave: (edit) => widget.onUpdate(item, edit)));
      if (updated != null && mounted) setState(() => _report = updated);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirm() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onConfirm();
      if (mounted) Navigator.pop(context);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
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

class LabEditDialog extends StatefulWidget {
  const LabEditDialog({super.key, required this.item, required this.onSave});
  final LabDraftItemModel item;
  final Future<LabReportModel> Function(LabDraftEdit) onSave;
  @override
  State<LabEditDialog> createState() => _LabEditDialogState();
}

class _LabEditDialogState extends State<LabEditDialog> {
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
  final _form = GlobalKey<FormState>();
  bool _saving = false;
  Object? _error;
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

  String? _finiteOptional(String? input) {
    final text = input?.trim() ?? '';
    if (text.isEmpty) return null;
    final value = double.tryParse(text);
    return value == null || !value.isFinite ? '请输入有效数值，或留空。' : null;
  }

  Widget _field(TextEditingController controller, String label,
          {bool numeric = false, bool required = false}) =>
      TextFormField(
          controller: controller,
          enabled: !_saving,
          keyboardType: numeric
              ? const TextInputType.numberWithOptions(
                  decimal: true, signed: true)
              : null,
          decoration: InputDecoration(labelText: label),
          validator: numeric
              ? _finiteOptional
              : required
                  ? (value) =>
                      value?.trim().isNotEmpty == true ? null : '请填写$label'
                  : null);
  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        title: const Text('修改指标'),
        content: Form(
            key: _form,
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _field(_name, '名称', required: true),
                  _field(_normalized, '标准化名称', required: true),
                  _field(_value, '数值', numeric: true),
                  _field(_unit, '单位'),
                  _field(_minimum, '参考下限', numeric: true),
                  _field(_maximum, '参考上限', numeric: true),
                  if (_error != null)
                    Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Semantics(
                            liveRegion: true,
                            child: Text(
                                '${UiFailure.title(_error!)}。修改已保留，请重试。',
                                style: AppTypography.secondary.copyWith(
                                    color: AppColors.of(context).danger)))),
                ])),
        actions: [
          TextButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: const Text('取消')),
          FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? '正在保存…' : '保存'))
        ],
      ));
  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await widget.onSave(LabDraftEdit(
          testName: _name.text.trim(),
          normalizedName: _normalized.text.trim(),
          value: double.tryParse(_value.text.trim()),
          unit: _unit.text.trim().isEmpty ? null : _unit.text.trim(),
          referenceMin: double.tryParse(_minimum.text.trim()),
          referenceMax: double.tryParse(_maximum.text.trim())));
      if (mounted) Navigator.pop(context, updated);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _KnowledgeTab extends ConsumerStatefulWidget {
  const _KnowledgeTab();
  @override
  ConsumerState<_KnowledgeTab> createState() => _KnowledgeTabState();
}

class _KnowledgeTabState extends ConsumerState<_KnowledgeTab>
    with AutomaticKeepAliveClientMixin {
  final _query = TextEditingController();
  final _focus = FocusNode();
  bool _searched = false, _searching = false;
  String? _validation;
  @override
  bool get wantKeepAlive => true;
  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (_searching) return;
    if (_query.text.trim().length < 2) {
      setState(() => _validation = '至少输入两个字，再开始查找。');
      _focus.requestFocus();
      return;
    }
    setState(() {
      _searching = true;
      _searched = true;
      _validation = null;
    });
    try {
      await ref.read(knowledgeSearchProvider.notifier).search(_query.text);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final results = ref.watch(knowledgeSearchProvider);
    return ListView(
        key: const Key('health-knowledge-list'),
        padding: AppSpacing.pageInsets,
        children: [
          TextField(
              key: const Key('health-knowledge-search'),
              controller: _query,
              focusNode: _focus,
              enabled: !_searching,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                  labelText: '查找可靠知识',
                  hintText: '蛋白质、体重波动…',
                  errorText: _validation,
                  suffixIcon: IconButton(
                      tooltip: '查找',
                      onPressed: _searching ? null : _search,
                      icon: const Icon(Icons.search)))),
          const SizedBox(height: 16),
          const Text('仅检索已导入并启用的可靠知识来源。'),
          const SizedBox(height: 16),
          ...switch (results) {
            AsyncData(:final value) when value.isEmpty => [
                EmptyState(
                    title: _searched ? '没有找到匹配的来源' : '从一个健康问题开始',
                    message: _searched
                        ? '可尝试更简短的关键词；没有匹配结果不代表问题没有答案。'
                        : '输入至少两个字，查找已有的可靠来源。不会用缺失的证据补齐答案。',
                    actionLabel: _searched ? '调整关键词' : '输入问题',
                    onAction: _focus.requestFocus)
              ],
            AsyncData(:final value) => value.map(_EvidenceCard.new),
            AsyncError(:final error) => [
                ErrorState(inline: true, error: error, onRetry: _search)
              ],
            _ => [const LoadingState(inline: true, label: '正在查找已启用来源')],
          },
        ]);
  }
}

class _EvidenceCard extends StatelessWidget {
  const _EvidenceCard(this.evidence);
  final HealthEvidenceModel evidence;
  @override
  Widget build(BuildContext context) => ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(evidence.title),
      subtitle: Text(
          '${evidence.publisher}${evidence.year == null ? '' : ' · ${evidence.year}'}'),
      children: [_EvidenceContent(evidence)]);
}

class _EvidenceContent extends StatelessWidget {
  const _EvidenceContent(this.evidence, {this.showTitle = false});
  final HealthEvidenceModel evidence;
  final bool showTitle;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (showTitle)
          Text('${evidence.publisher}｜${evidence.title}',
              style: AppTypography.cardTitle),
        if (showTitle && evidence.year != null)
          Text('${evidence.year} 年', style: AppTypography.caption),
        SelectableText(evidence.excerpt, style: AppTypography.body),
        if (evidence.sourceUrl case final url?) ...[
          const SizedBox(height: 8),
          SelectableText(url,
              style: AppTypography.secondary
                  .copyWith(color: AppColors.of(context).secondaryText))
        ],
      ]));
}

class _HealthChatTab extends ConsumerStatefulWidget {
  const _HealthChatTab(
      {this.externalSending = false,
      this.prompt,
      this.promptVersion = 0,
      required this.onBusyChanged});
  final bool externalSending;
  final String? prompt;
  final int promptVersion;
  final ValueChanged<bool> onBusyChanged;
  @override
  ConsumerState<_HealthChatTab> createState() => _HealthChatTabState();
}

class _HealthChatTabState extends ConsumerState<_HealthChatTab>
    with AutomaticKeepAliveClientMixin {
  final _message = TextEditingController();
  final _focus = FocusNode();
  bool _sending = false;
  List<HealthChatMessage> _retained = const [], _historyPrefix = const [];
  final Set<HealthChatMessage> _hiddenFailedAttempts = {};
  @override
  bool get wantKeepAlive => true;
  @override
  void initState() {
    super.initState();
    _queuePrompt();
  }

  @override
  void didUpdateWidget(covariant _HealthChatTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.promptVersion != widget.promptVersion) _queuePrompt();
  }

  void _queuePrompt() {
    final prompt = widget.prompt;
    if (prompt != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _send(prompt);
      });
    }
  }

  @override
  void dispose() {
    _message.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final chat = ref.watch(healthChatProvider);
    if (chat.valueOrNull case final incoming?) {
      final includesPrefix = incoming.length >= _historyPrefix.length &&
          List.generate(
                  _historyPrefix.length,
                  (i) =>
                      incoming[i].text == _historyPrefix[i].text &&
                      incoming[i].fromUser == _historyPrefix[i].fromUser)
              .every((same) => same);
      if (includesPrefix) _historyPrefix = const [];
      _retained = [..._historyPrefix, ...incoming]
          .where((message) => !_hiddenFailedAttempts.contains(message))
          .toList();
    }
    final busy = _sending || widget.externalSending || chat.isLoading;
    return Column(children: [
      Expanded(
          child: ListView.builder(
              key: const Key('health-chat-history'),
              padding: AppSpacing.pageInsets,
              itemCount: _retained.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const InsightBlock(
                            title: '结合记录，理解健康',
                            message: '没有足够依据时会明确说明；不能替代医生诊断或处方。'),
                        if (_retained.isEmpty &&
                            !chat.isLoading &&
                            !chat.hasError)
                          EmptyState(
                              title: '从一个问题开始',
                              message: '可以询问指标含义、个人趋势或已有可靠证据。',
                              actionLabel: '写下健康问题',
                              onAction: _focus.requestFocus),
                      ]);
                }
                return _HealthConversationRow(_retained[index - 1]);
              })),
      Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (busy)
              Semantics(liveRegion: true, child: const Text('正在结合记录与证据整理回复…')),
            if (chat.hasError)
              Semantics(
                  liveRegion: true,
                  child: Text('${UiFailure.title(chat.error!)}。问题已保留，请重试。',
                      style: AppTypography.secondary
                          .copyWith(color: AppColors.of(context).danger))),
          ])),
      SafeArea(
          top: false,
          child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
              child: Row(children: [
                Expanded(
                    child: TextField(
                        key: const Key('health-chat-input'),
                        controller: _message,
                        focusNode: _focus,
                        enabled: !busy,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        decoration: const InputDecoration(
                            labelText: '写下健康问题', hintText: '询问指标含义或个人趋势'),
                        onSubmitted: (_) => _send())),
                IconButton(
                    key: const Key('send-health-chat'),
                    tooltip: '发送健康问题',
                    onPressed: busy ? null : _send,
                    icon: const Icon(Icons.send_outlined)),
              ]))),
    ]);
  }

  Future<void> _send([String? prompt]) async {
    final value = (prompt ?? _message.text).trim();
    if (_sending || value.isEmpty) return;
    if (prompt == null && widget.externalSending) return;
    if (prompt != null) _message.text = prompt;
    if (ref.read(healthChatProvider).hasError) {
      _historyPrefix = [..._retained];
      if (_historyPrefix.isNotEmpty &&
          _historyPrefix.last.fromUser &&
          _historyPrefix.last.text == value) {
        _hiddenFailedAttempts.add(_historyPrefix.last);
        _historyPrefix = _historyPrefix.sublist(0, _historyPrefix.length - 1);
      }
    }
    setState(() => _sending = true);
    widget.onBusyChanged(true);
    try {
      await ref.read(healthChatProvider.notifier).send(value);
      if (mounted && !ref.read(healthChatProvider).hasError) _message.clear();
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        widget.onBusyChanged(false);
      }
    }
  }
}

class _HealthConversationRow extends StatelessWidget {
  const _HealthConversationRow(this.message);
  final HealthChatMessage message;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Semantics(
            header: true,
            child: Text(message.fromUser ? '你' : '健康教练',
                style: AppTypography.cardTitle)),
        const SizedBox(height: 8),
        SelectableText(message.text, style: AppTypography.body),
        if (message.riskLevel == 'urgent')
          Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text('风险提示：该回复需要及时关注。请优先按回复中的安全建议处理。',
                  style: AppTypography.secondary
                      .copyWith(color: AppColors.of(context).danger))),
        if (message.medicalBoundary)
          Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text('医疗边界：此回答不构成诊断或处方建议。',
                  style: AppTypography.secondary
                      .copyWith(color: AppColors.of(context).attention))),
        if (message.evidence.isNotEmpty)
          ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('依据来源'),
              subtitle: Text('${message.evidence.length} 项真实来源 · 按需展开'),
              children: [
                for (final evidence in message.evidence)
                  _EvidenceContent(evidence, showTitle: true)
              ]),
      ]));
}
