import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/local_database.dart';
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
      _statusText = value.status == 'completed' ? '识别草稿已生成' : '识别未完成';
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
    final controller = TextEditingController(
      text: item.weightG.toStringAsFixed(0),
    );
    final weight = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('修改 ${item.foodName ?? item.name} 份量'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: '重量', suffixText: 'g'),
          onSubmitted: (value) {
            final parsed = double.tryParse(value.trim());
            if (parsed != null && parsed > 0) Navigator.pop(context, parsed);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final parsed = double.tryParse(controller.text.trim());
              if (parsed != null && parsed > 0) Navigator.pop(context, parsed);
            },
            child: const Text('更新估算'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (weight == null || !mounted) return;
    await _updateWeight(item, weight);
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

  Future<void> _mutate(Future<MealAnalysisModel> Function() action) async {
    setState(() => _busy = true);
    try {
      final result = await action();
      if (mounted) setState(() => _analysis = result);
    } on Object catch (error) {
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
        _ => error.message,
      };
    }
    return '网络暂不可用，照片已保留在本机。';
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
      appBar: AppBar(title: const Text('拍照识别一餐')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Image.file(
              File(widget.task.imagePath),
              height: 210,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox(
                height: 160,
                child: Center(child: Text('本地照片不可用')),
              ),
            ),
          ),
          const SizedBox(height: 14),
          _StatusCard(
            text: _statusText,
            busy: _busy,
            progress: _progress,
            error: _error,
            onRetry: _retry,
            onManual: () => Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => FoodSearchScreen(mealType: _mealType),
              ),
            ),
          ),
          if (analysis != null && analysis.editable) ...[
            const SizedBox(height: 14),
            _SummaryCard(analysis: analysis),
            for (final warning in analysis.warnings)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('提示：$warning'),
              ),
            const SizedBox(height: 12),
            for (final item in analysis.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _AnalysisItemCard(
                  item: item,
                  enabled: !_busy,
                  onAdjust: (delta) => _adjust(item, delta),
                  onEditWeight: () => _editWeight(item),
                  onReplace: () => _chooseFood(replace: item),
                  onDelete: () => _deleteItem(item),
                ),
              ),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _chooseFood(),
              icon: const Icon(Icons.add),
              label: const Text('补充遗漏食物'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _mealType,
              decoration: const InputDecoration(labelText: '餐次'),
              items: const [
                DropdownMenuItem(value: 'breakfast', child: Text('早餐')),
                DropdownMenuItem(value: 'lunch', child: Text('午餐')),
                DropdownMenuItem(value: 'dinner', child: Text('晚餐')),
                DropdownMenuItem(value: 'snack', child: Text('加餐')),
              ],
              onChanged:
                  _busy ? null : (value) => setState(() => _mealType = value!),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _noteController,
              maxLength: 400,
              decoration: const InputDecoration(labelText: '备注（可选）'),
            ),
            const Text('AI 结果只是可编辑草稿。营养值由食物库按确认份量计算，保存前请核对菜品、份量和隐藏用油。'),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _confirm,
              icon: const Icon(Icons.check_circle_outline),
              label: Text(_busy ? '处理中' : '确认并计入今日营养'),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.text,
    required this.busy,
    required this.progress,
    required this.error,
    required this.onRetry,
    required this.onManual,
  });

  final String text;
  final bool busy;
  final double progress;
  final String? error;
  final VoidCallback onRetry;
  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) => Card(
        color: error == null
            ? Theme.of(context).colorScheme.primaryContainer
            : Theme.of(context).colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(error == null ? Icons.auto_awesome : Icons.cloud_off),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      text,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              if (busy) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: progress > 0 && progress < 1 ? progress : null,
                ),
              ],
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton.tonal(
                      onPressed: onRetry,
                      child: const Text('继续识别'),
                    ),
                    TextButton(
                        onPressed: onManual, child: const Text('改用手工记录')),
                  ],
                ),
              ],
            ],
          ),
        ),
      );
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.analysis});

  final MealAnalysisModel analysis;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('本餐估算',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Text(
                      '${analysis.totals.center.calories.toStringAsFixed(0)} kcal '
                      '（${analysis.totals.minCalories.toStringAsFixed(0)}–'
                      '${analysis.totals.maxCalories.toStringAsFixed(0)}）',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    Text(
                      '蛋白质 ${analysis.totals.center.protein.toStringAsFixed(1)} g · '
                      '碳水 ${analysis.totals.center.carbs.toStringAsFixed(1)} g · '
                      '脂肪 ${analysis.totals.center.fat.toStringAsFixed(1)} g',
                    ),
                  ],
                ),
              ),
              _ConfidenceChip(label: analysis.confidenceLabel ?? 'low'),
            ],
          ),
        ),
      );
}

class _AnalysisItemCard extends StatelessWidget {
  const _AnalysisItemCard({
    required this.item,
    required this.enabled,
    required this.onAdjust,
    required this.onEditWeight,
    required this.onReplace,
    required this.onDelete,
  });

  final MealAnalysisItemModel item;
  final bool enabled;
  final void Function(double delta) onAdjust;
  final VoidCallback onEditWeight;
  final VoidCallback onReplace;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final unmatched = item.foodId == null;
    return Card(
      color: unmatched ? Theme.of(context).colorScheme.errorContainer : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (item.hiddenIngredient)
                  const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: Icon(Icons.opacity, size: 18),
                  ),
                Expanded(
                  child: Text(
                    item.foodName ?? item.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                _ConfidenceChip(label: item.confidenceLabel),
                PopupMenuButton<String>(
                  enabled: enabled,
                  onSelected: (value) =>
                      value == 'replace' ? onReplace() : onDelete(),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'replace', child: Text('更换食物匹配')),
                    PopupMenuItem(value: 'delete', child: Text('删除条目')),
                  ],
                ),
              ],
            ),
            if (unmatched)
              const Text('未匹配食物库，确认前必须手动选择。')
            else if (item.foodName != item.name)
              Text('识别为 ${item.name} · ${_matchLabel(item.matchType)}'),
            const SizedBox(height: 8),
            Text(
              '${item.weightG.toStringAsFixed(0)} g '
              '（${item.minWeightG.toStringAsFixed(0)}–${item.maxWeightG.toStringAsFixed(0)} g）',
            ),
            Text(
              '${item.calories.toStringAsFixed(0)} kcal '
              '（${item.minCalories.toStringAsFixed(0)}–${item.maxCalories.toStringAsFixed(0)}）',
            ),
            if (item.cookingMethod != null || item.portionDescription != null)
              Text(
                [
                  item.cookingMethod,
                  item.portionDescription,
                ].whereType<String>().join(' · '),
              ),
            if (item.hiddenIngredients.isNotEmpty)
              Text('可能隐藏：${item.hiddenIngredients.join('、')}'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final delta in const [-50.0, -25.0, 25.0, 50.0])
                  ActionChip(
                    onPressed: enabled ? () => onAdjust(delta) : null,
                    label: Text('${delta > 0 ? '+' : ''}${delta.toInt()}g'),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: enabled ? onEditWeight : null,
                  label: const Text('直接输入'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _matchLabel(String value) => switch (value) {
        'personal_memory' => '来自个人纠正记忆',
        'custom_exact' => '匹配自定义食物',
        'alias' => '别名匹配',
        'fuzzy' => '相似匹配，请核对',
        'manual' => '已手动选择',
        _ => '食物库精确匹配',
      };
}

class _ConfidenceChip extends StatelessWidget {
  const _ConfidenceChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final (text, color) = switch (label) {
      'high' => ('高置信度', Colors.green),
      'medium' => ('中置信度', Colors.orange),
      _ => ('低置信度', Colors.red),
    };
    return Chip(
      visualDensity: VisualDensity.compact,
      label: Text(text),
      side: BorderSide(color: color),
    );
  }
}
