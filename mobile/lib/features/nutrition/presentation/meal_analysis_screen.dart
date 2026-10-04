import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/local_database.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_components.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../dashboard/presentation/dashboard_controller.dart';
import '../data/meal_analysis_models.dart';
import '../data/nutrition_models.dart';
import 'food_search_screen.dart';
import 'nutrition_controller.dart';

class MealAnalysisScreen extends ConsumerStatefulWidget {
  const MealAnalysisScreen({super.key, required this.task});

  final VisionTaskRecord task;

  @override
  ConsumerState<MealAnalysisScreen> createState() => _MealAnalysisScreenState();
}

class _MealAnalysisScreenState extends ConsumerState<MealAnalysisScreen> {
  final _noteController = TextEditingController();
  MealAnalysisModel? _analysis;
  late String _mealType;
  String _statusText = '准备上传照片';
  double _progress = 0;
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _mealType = widget.task.mealType;
    Future<void>.microtask(_start);
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity.contains(ConnectivityResult.none)) {
      await _fail('当前离线，照片已安全保存在本机。联网后可继续识别。');
      return;
    }
    try {
      final api = ref.read(apiClientProvider);
      MealAnalysisModel analysis;
      if (widget.task.analysisId != null) {
        _setStatus('正在恢复识别草稿');
        analysis = await api.fetchMealAnalysis(widget.task.analysisId!);
      } else {
        _setStatus('正在上传照片');
        analysis = await api.analyzeMealImage(
          imagePath: widget.task.imagePath,
          mealType: _mealType,
          idempotencyKey: widget.task.localId,
          locationContext: widget.task.locationContext,
          onSendProgress: (sent, total) {
            if (!mounted || total <= 0) return;
            final progress = sent / total;
            setState(() => _progress = progress);
            unawaited(
              ref.read(localDatabaseProvider).updateVisionTask(
                    widget.task.localId,
                    status: 'uploading',
                    uploadProgress: progress,
                  ),
            );
          },
        );
        await ref.read(localDatabaseProvider).updateVisionTask(
              widget.task.localId,
              analysisId: analysis.id,
              status: analysis.status,
              uploadProgress: 1,
            );
      }
      await _poll(analysis);
    } on Object catch (error) {
      await _fail(_friendlyError(error));
    }
  }

  Future<void> _poll(MealAnalysisModel initial) async {
    var value = initial;
    _setAnalysis(value);
    for (var attempt = 0; value.processing && attempt < 18; attempt++) {
      _setStatus(value.status == 'pending' ? '等待开始识别' : '正在识别菜品和份量');
      await Future<void>.delayed(Duration(seconds: min(5, attempt + 1)));
      if (!mounted) return;
      value = await ref.read(apiClientProvider).fetchMealAnalysis(value.id);
      _setAnalysis(value);
    }
    if (value.processing) {
      await _fail('识别仍在后台进行。稍后点击“继续识别”即可恢复，不会丢失照片。');
      return;
    }
    await ref.read(localDatabaseProvider).updateVisionTask(
          widget.task.localId,
          analysisId: value.id,
          status: value.status,
          uploadProgress: 1,
          lastError: value.errorMessage,
        );
    if (!mounted) return;
    setState(() {
      _analysis = value;
      _busy = false;
      _error = value.status == 'failed' ? _analysisFailure(value) : null;
      _statusText = switch (value.status) {
        'completed' => '识别草稿已生成',
        'confirmed' => '已保存到今日饮食',
        _ => '识别未完成'
      };
    });
  }

  Future<void> _retry() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _statusText = '正在重试';
    });
    try {
      final current = _analysis;
      if (current != null && current.status == 'failed') {
        await _poll(
          await ref.read(apiClientProvider).reanalyzeMeal(current.id),
        );
      } else {
        await _start();
      }
    } on Object catch (error) {
      await _fail(_friendlyError(error));
    }
  }

  Future<void> _adjust(MealAnalysisItemModel item, double delta) async {
    final next = max(1, item.weightG + delta).toDouble();
    await _updateWeight(item, next);
  }

  Future<void> _editWeight(MealAnalysisItemModel item) async {
    await showDialog<bool>(
        context: context,
        builder: (_) => NumberEntryDialog(
            title: '修改 ${item.foodName ?? item.name} 份量',
            initialValue: item.weightG.toStringAsFixed(0),
            unit: 'g',
            onSave: (next) => _mutate(
                () => ref.read(apiClientProvider).updateMealAnalysisItem(
                    analysisId: _analysis!.id,
                    itemId: item.id,
                    weightG: next,
                    minWeightG: max(1, next * 0.75).toDouble(),
                    maxWeightG: next * 1.25),
                retainError: true)));
  }

  Future<void> _updateWeight(MealAnalysisItemModel item, double next) async {
    await _mutate(
      () => ref.read(apiClientProvider).updateMealAnalysisItem(
            analysisId: _analysis!.id,
            itemId: item.id,
            weightG: next,
            minWeightG: max(1, next * 0.75).toDouble(),
            maxWeightG: next * 1.25,
          ),
    );
  }

  Future<void> _deleteItem(MealAnalysisItemModel item) => _mutate(
        () => ref
            .read(apiClientProvider)
            .deleteMealAnalysisItem(_analysis!.id, item.id),
      );

  Future<void> _mutate(Future<MealAnalysisModel> Function() action,
      {bool retainError = false}) async {
    setState(() => _busy = true);
    try {
      final result = await action();
      if (mounted) setState(() => _analysis = result);
    } on Object catch (error) {
      if (retainError) rethrow;
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_friendlyError(error))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _chooseFood({MealAnalysisItemModel? replace}) async {
    final queryController = TextEditingController(text: replace?.name ?? '');
    final query = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(replace == null ? '添加食物' : '更换食物匹配'),
        content: TextField(
          controller: queryController,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(hintText: '输入食物名称'),
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, queryController.text.trim()),
            child: const Text('搜索'),
          ),
        ],
      ),
    );
    queryController.dispose();
    if (!mounted || query == null || query.isEmpty) return;
    try {
      final foods = await ref.read(apiClientProvider).searchFoods(query);
      if (!mounted) return;
      final selected = await showDialog<FoodModel>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('选择食物库条目'),
          children: [
            if (foods.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('没有匹配结果，请换个关键词。'),
              ),
            for (final food in foods.take(10))
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, food),
                child: Text(
                  '${food.name} · ${food.caloriesPer100g.toStringAsFixed(0)} kcal/100g',
                ),
              ),
          ],
        ),
      );
      if (selected == null) return;
      if (replace != null) {
        await _mutate(
          () => ref.read(apiClientProvider).updateMealAnalysisItem(
                analysisId: _analysis!.id,
                itemId: replace.id,
                foodId: selected.id,
              ),
        );
      } else {
        await _mutate(
          () => ref.read(apiClientProvider).addMealAnalysisItem(
                analysisId: _analysis!.id,
                foodId: selected.id,
                name: selected.name,
                weightG: selected.servingWeightG ?? 100,
              ),
        );
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_friendlyError(error))));
      }
    }
  }

  Future<void> _confirm() async {
    final analysis = _analysis;
    if (analysis == null || !analysis.editable || _busy) return;
    if (analysis.items.any((item) => item.foodId == null)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('仍有未匹配食物，请先选择食物库条目。')));
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(apiClientProvider).confirmMealAnalysis(
            analysisId: analysis.id,
            mealType: _mealType,
            eatenAt: DateTime.now(),
            idempotencyKey: 'confirm-${widget.task.localId}',
            note: _noteController.text.trim().isEmpty
                ? null
                : _noteController.text.trim(),
          );
      await ref
          .read(localDatabaseProvider)
          .deleteVisionTask(widget.task.localId);
      ref.invalidate(nutritionControllerProvider);
      ref.invalidate(dashboardProvider);
      if (mounted) Navigator.pop(context, true);
    } on Object catch (error) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_friendlyError(error))));
      }
    }
  }

  Future<void> _fail(String message) async {
    await ref.read(localDatabaseProvider).updateVisionTask(
          widget.task.localId,
          status: 'waiting_network',
          lastError: message,
        );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = message;
      _statusText = '暂未完成识别';
    });
  }

  void _setStatus(String value) {
    if (mounted) setState(() => _statusText = value);
  }

  void _setAnalysis(MealAnalysisModel value) {
    if (mounted) setState(() => _analysis = value);
  }

  String _friendlyError(Object error) {
    if (error is ApiException) {
      return switch (error.code) {
        'image_too_large' => '图片超过 10 MB，请裁剪或降低画质后重试。',
        'invalid_image_type' => '仅支持 JPEG、PNG 或 WEBP 图片。',
        'vision_timeout' => '识别超时，照片已保留，可直接重试。',
        'vision_daily_limit_reached' => '今日识别次数已用完，可改用手工记录。',
        'no_food_detected' => '没有识别到食物，请换一张更清晰、光线更好的照片。',
        _ => UiFailure.message(error),
      };
    }
    return '暂时无法完成识别。照片已保留在本机，可重试或手工记录。';
  }

  String _analysisFailure(MealAnalysisModel analysis) =>
      switch (analysis.errorCode) {
        'no_food_detected' => '没有可靠识别到食物。请靠近一些，让完整餐盘处于良好光线下再拍。',
        'vision_timeout' => '识别超时，照片已保留，可直接重试。',
        'invalid_vision_response' => '识别结果格式异常，请重试或改用手工记录。',
        'image_not_found' => '临时照片已过期，请重新拍摄。',
        _ => '识别失败，请重试或手动添加食物。',
      };

  @override
  Widget build(BuildContext context) {
    final analysis = _analysis;
    return Scaffold(
        appBar: DetailPageHeader(label: '核对餐食'),
        bottomNavigationBar: analysis != null && analysis.editable
            ? BottomActionArea(
                child: FilledButton.icon(
                    onPressed: _busy ? null : _confirm,
                    icon: const Icon(Icons.check_circle_outline),
                    label: Text(_busy ? '处理中…' : '确认并计入今日营养')))
            : null,
        body: ListView(padding: AppSpacing.pageInsets, children: [
          if (analysis != null && analysis.editable)
            MealDraftReview(
                analysis: analysis,
                busy: _busy,
                mealType: _mealType,
                noteController: _noteController,
                onMealTypeChanged: (value) => setState(() => _mealType = value),
                onAdjust: _adjust,
                onEditWeight: _editWeight,
                onReplace: (item) => _chooseFood(replace: item),
                onDelete: _deleteItem,
                onAdd: () => _chooseFood()),
          Semantics(
              liveRegion: true,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    Text(_statusText, style: AppTypography.secondary),
                    if (_busy) ...[
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                          value: _progress > 0 && _progress < 1
                              ? _progress
                              : MediaQuery.disableAnimationsOf(context)
                                  ? 0
                                  : null,
                          minHeight: 3,
                          semanticsLabel: _statusText)
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(_error!),
                      const SizedBox(height: 12),
                      Wrap(spacing: 12, runSpacing: 8, children: [
                        TextButton(
                            onPressed: _retry, child: const Text('继续识别')),
                        TextButton(
                            onPressed: () => Navigator.of(context)
                                .pushReplacement(MaterialPageRoute(
                                    builder: (_) =>
                                        FoodSearchScreen(mealType: _mealType))),
                            child: const Text('改用手工记录')),
                      ])
                    ],
                    if (analysis?.status == 'confirmed')
                      TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('返回饮食记录')),
                  ])),
          ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('查看原照片'),
              children: [
                ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.large),
                    child: Image.file(File(widget.task.imagePath),
                        height: 210,
                        fit: BoxFit.cover,
                        semanticLabel: '用于核对餐食份量的原照片',
                        errorBuilder: (_, __, ___) => const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text('本地照片不可用，草稿数据仍可核对')))),
              ]),
        ]));
  }
}

/// Pure draft presentation; all estimates, warnings and edit actions come from the existing model.
class MealDraftReview extends StatelessWidget {
  const MealDraftReview(
      {super.key,
      required this.analysis,
      required this.busy,
      required this.mealType,
      required this.noteController,
      required this.onMealTypeChanged,
      required this.onAdjust,
      required this.onEditWeight,
      required this.onReplace,
      required this.onDelete,
      required this.onAdd});
  final MealAnalysisModel analysis;
  final bool busy;
  final String mealType;
  final TextEditingController noteController;
  final void Function(String) onMealTypeChanged;
  final void Function(MealAnalysisItemModel, double) onAdjust;
  final void Function(MealAnalysisItemModel) onEditWeight, onReplace, onDelete;
  final VoidCallback onAdd;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        MetricHero(
            label: '本餐估算',
            value: AppFormat.number(analysis.totals.center.calories),
            unit: 'kcal',
            detail:
                '估计范围 ${AppFormat.number(analysis.totals.minCalories)}–${AppFormat.number(analysis.totals.maxCalories)} kcal'),
        const SizedBox(height: 12),
        Text(
            '蛋白质 ${AppFormat.number(analysis.totals.center.protein, decimals: 1)} g · 碳水 ${AppFormat.number(analysis.totals.center.carbs, decimals: 1)} g · 脂肪 ${AppFormat.number(analysis.totals.center.fat, decimals: 1)} g',
            style: AppTypography.secondary),
        const SizedBox(height: 12),
        const Text('这是可编辑草稿，尚未计入今日营养。请核对菜品、份量和隐藏用油。',
            style: AppTypography.secondary),
        for (final warning in analysis.warnings)
          Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('提示：$warning',
                  style: AppTypography.secondary
                      .copyWith(color: AppColors.of(context).attention))),
        if (analysis.items.isEmpty)
          EmptyState(
              title: '草稿暂无食物',
              message: '请补充食物后再确认。',
              actionLabel: '补充食物',
              onAction: busy ? null : onAdd)
        else
          for (final item in analysis.items)
            _DraftItem(
                item: item,
                enabled: !busy,
                onAdjust: (delta) => onAdjust(item, delta),
                onEdit: () => onEditWeight(item),
                onReplace: () => onReplace(item),
                onDelete: () => onDelete(item)),
        TextButton.icon(
            onPressed: busy ? null : onAdd,
            icon: const Icon(Icons.add),
            label: const Text('补充遗漏食物')),
        AppSection(
            title: '记录到哪一餐',
            child: Column(children: [
              DropdownButtonFormField<String>(
                  initialValue: mealType,
                  isExpanded: true,
                  itemHeight: null,
                  decoration: const InputDecoration(labelText: '餐次'),
                  items: const [
                    DropdownMenuItem(value: 'breakfast', child: Text('早餐')),
                    DropdownMenuItem(value: 'lunch', child: Text('午餐')),
                    DropdownMenuItem(value: 'dinner', child: Text('晚餐')),
                    DropdownMenuItem(value: 'snack', child: Text('加餐')),
                  ],
                  onChanged: busy
                      ? null
                      : (value) {
                          if (value != null) onMealTypeChanged(value);
                        }),
              const SizedBox(height: 16),
              TextField(
                  controller: noteController,
                  enabled: !busy,
                  maxLength: 400,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: '备注（可选）')),
            ])),
        ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('识别与估计详情'),
            children: [
              ListRow(
                  title: _confidence(analysis.confidenceLabel),
                  subtitle: '提供方 ${analysis.provider} · 模型 ${analysis.model}'),
            ]),
      ]);
  static String _confidence(String? value) => switch (value) {
        'high' => '估计把握较高',
        'medium' => '估计把握中等',
        'low' => '估计把握较低，请认真核对',
        _ => '估计把握未提供',
      };
}

class _DraftItem extends StatelessWidget {
  const _DraftItem(
      {required this.item,
      required this.enabled,
      required this.onAdjust,
      required this.onEdit,
      required this.onReplace,
      required this.onDelete});
  final MealAnalysisItemModel item;
  final bool enabled;
  final void Function(double) onAdjust;
  final VoidCallback onEdit, onReplace, onDelete;
  @override
  Widget build(BuildContext context) => AppSection(
      title: item.foodName ?? item.name,
      action: PopupMenuButton<String>(
          tooltip: '更多：${item.foodName ?? item.name}',
          enabled: enabled,
          onSelected: (value) => value == 'replace' ? onReplace() : onDelete(),
          itemBuilder: (_) => const [
                PopupMenuItem(value: 'replace', child: Text('更换食物匹配')),
                PopupMenuItem(value: 'delete', child: Text('删除条目'))
              ]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (item.foodId == null)
          Text('未匹配食物库，确认前请手动选择。',
              style: AppTypography.secondary
                  .copyWith(color: AppColors.of(context).warning)),
        if (item.hiddenIngredient)
          const Text('隐藏配料估计', style: AppTypography.caption),
        Text(
            '${AppFormat.number(item.weightG)} g · ${AppFormat.number(item.calories)} kcal',
            style: AppTypography.metric),
        Text(
            '估计范围 ${AppFormat.number(item.minWeightG)}–${AppFormat.number(item.maxWeightG)} g · ${AppFormat.number(item.minCalories)}–${AppFormat.number(item.maxCalories)} kcal',
            style: AppTypography.caption
                .copyWith(color: AppColors.of(context).secondaryText)),
        if (item.hiddenIngredients.isNotEmpty)
          Text('可能隐藏：${item.hiddenIngredients.join('、')}',
              style: AppTypography.secondary),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final delta in const [-50.0, -25.0, 25.0, 50.0])
            TextButton(
                onPressed: enabled ? () => onAdjust(delta) : null,
                child: Text('${delta > 0 ? '+' : ''}${delta.toInt()}g')),
          TextButton.icon(
              onPressed: enabled ? onEdit : null,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('直接输入')),
        ]),
        ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('核对匹配详情'),
            children: [
              ListRow(
                  title: MealDraftReview._confidence(item.confidenceLabel),
                  subtitle:
                      '识别为 ${item.name} · ${_matchLabel(item.matchType)}'),
              if (item.cookingMethod != null || item.portionDescription != null)
                Text(
                    [item.cookingMethod, item.portionDescription]
                        .whereType<String>()
                        .join(' · '),
                    style: AppTypography.secondary),
            ]),
      ]));
  static String _matchLabel(String value) => switch (value) {
        'personal_memory' => '来自个人纠正记忆',
        'custom_exact' => '匹配自定义食物',
        'alias' => '别名匹配',
        'fuzzy' => '相似匹配，请核对',
        'manual' => '已手动选择',
        'exact' => '食物库精确匹配',
        _ => '匹配方式待核对',
      };
}
