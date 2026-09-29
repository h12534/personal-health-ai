import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/database/local_database.dart';
import '../data/meal_photo_service.dart';
import '../data/nutrition_models.dart';
import '../data/sync_service.dart';
import 'food_search_screen.dart';
import 'meal_analysis_screen.dart';
import 'nutrition_controller.dart';

class NutritionScreen extends ConsumerStatefulWidget {
  const NutritionScreen({super.key});

  @override
  ConsumerState<NutritionScreen> createState() => _NutritionScreenState();
}

class _NutritionScreenState extends ConsumerState<NutritionScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _recoverLostPhoto());
  }

  Future<void> _recoverLostPhoto() async {
    try {
      final task = await ref
          .read(mealPhotoServiceProvider)
          .recoverLostImage(mealType: _currentMealType());
      if (task != null && mounted) {
        await _openVisionTask(context, ref, task);
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('上次拍摄的照片恢复失败，请重新选择图片。')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(connectivitySyncProvider);
    final nutrition = ref.watch(nutritionControllerProvider);
    return nutrition.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(
        child: FilledButton.tonal(
          onPressed: () =>
              ref.read(nutritionControllerProvider.notifier).refresh(),
          child: const Text('重新加载饮食记录'),
        ),
      ),
      data: (data) => NutritionContent(
        data: data,
        onRefresh: () =>
            ref.read(nutritionControllerProvider.notifier).refresh(),
        onAddFood: (mealType) => _openFoodSearch(context, ref, mealType),
        onEditItem: (meal, item) => _editItem(context, ref, meal, item),
        onAnalyzePhoto: () => _openMealPhoto(context, ref),
        onResumeVision: (task) => _openVisionTask(context, ref, task),
      ),
    );
  }

  static Future<void> _openMealPhoto(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            const ListTile(
              title: Text('选择照片来源'),
              subtitle: Text('照片会先在本机压缩，AI 结果仅生成可编辑草稿。'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('拍照'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('从相册选择'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !context.mounted) return;
    try {
      final task = await ref
          .read(mealPhotoServiceProvider)
          .pickAndPersist(source: source, mealType: _currentMealType());
      if (task != null && context.mounted) {
        await _openVisionTask(context, ref, task);
      }
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error.toString().contains('permission')
                  ? '无法访问相机或相册，请在系统设置中授予权限。'
                  : error.toString(),
            ),
          ),
        );
      }
    }
  }

  static Future<void> _openVisionTask(
    BuildContext context,
    WidgetRef ref,
    VisionTaskRecord task,
  ) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => MealAnalysisScreen(task: task)),
    );
    if (saved == true || context.mounted) {
      await ref.read(nutritionControllerProvider.notifier).refresh();
    }
  }

  static String _currentMealType() {
    final hour = DateTime.now().hour;
    if (hour < 10) return 'breakfast';
    if (hour < 15) return 'lunch';
    if (hour < 21) return 'dinner';
    return 'snack';
  }

  static Future<void> _openFoodSearch(
    BuildContext context,
    WidgetRef ref,
    String mealType,
  ) async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => FoodSearchScreen(mealType: mealType)),
    );
    if (added == true) {
      await ref.read(nutritionControllerProvider.notifier).refresh();
    }
  }

  static Future<void> _editItem(
    BuildContext context,
    WidgetRef ref,
    MealModel meal,
    MealItemModel item,
  ) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('修改份量'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('删除条目'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || action == null) return;
    try {
      if (action == 'delete') {
        await ref
            .read(nutritionControllerProvider.notifier)
            .deleteItem(meal, item);
        return;
      }
      final controller = TextEditingController(
        text: item.amount.toStringAsFixed(1),
      );
      final amount = await showDialog<double>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('修改 ${item.foodName}'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: '份量', suffixText: item.unit),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final value = double.tryParse(controller.text.trim());
                if (value != null && value > 0) Navigator.pop(context, value);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      );
      controller.dispose();
      if (amount != null) {
        await ref
            .read(nutritionControllerProvider.notifier)
            .updateItem(meal, item, amount);
      }
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }
}

class NutritionContent extends StatelessWidget {
  const NutritionContent({
    super.key,
    required this.data,
    required this.onRefresh,
    required this.onAddFood,
    required this.onEditItem,
    this.onAnalyzePhoto,
    this.onResumeVision,
  });

  final NutritionViewState data;
  final Future<void> Function() onRefresh;
  final void Function(String mealType) onAddFood;
  final void Function(MealModel meal, MealItemModel item) onEditItem;
  final VoidCallback? onAnalyzePhoto;
  final void Function(VisionTaskRecord task)? onResumeVision;

  @override
  Widget build(BuildContext context) {
    final totals = data.daily.totals;
    final goal = data.goal;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '今日饮食',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              if (data.offline) const Chip(label: Text('离线模式')),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${data.daily.date.year}年${data.daily.date.month}月${data.daily.date.day}日 · '
            '按实际份量记录，营养值会自动换算。',
          ),
          const SizedBox(height: 18),
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.document_scanner_outlined),
                      const SizedBox(width: 8),
                      Text(
                        '拍照识别一餐',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text('识别菜品和份量后先生成草稿，由你修改确认后才会计入营养。'),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: onAnalyzePhoto,
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('拍照或选择图片'),
                  ),
                ],
              ),
            ),
          ),
          if (data.visionTasks.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('待完成的照片草稿', style: Theme.of(context).textTheme.titleSmall),
            for (final task in data.visionTasks)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.cloud_upload_outlined),
                title: Text(_visionStatus(task.status)),
                subtitle: Text(task.lastError ?? '照片已保存在本机'),
                trailing: const Icon(Icons.chevron_right),
                onTap:
                    onResumeVision == null ? null : () => onResumeVision!(task),
              ),
          ],
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('今日营养', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 14),
                  _ProgressMetric(
                    label: '热量',
                    value: totals.calories,
                    target: goal?.calories.toDouble(),
                    unit: 'kcal',
                  ),
                  _ProgressMetric(
                    label: '蛋白质',
                    value: totals.protein,
                    target: goal?.protein,
                    unit: 'g',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 18,
                    runSpacing: 8,
                    children: [
                      Text('碳水 ${totals.carbs.toStringAsFixed(1)} g'),
                      Text('脂肪 ${totals.fat.toStringAsFixed(1)} g'),
                      Text('纤维 ${totals.fiber.toStringAsFixed(1)} g'),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          for (final type in const [
            'breakfast',
            'lunch',
            'dinner',
            'snack',
          ]) ...[
            _MealSection(
              mealType: type,
              meals: data.meals.where((meal) => meal.mealType == type).toList(),
              onAdd: () => onAddFood(type),
              onEditItem: onEditItem,
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  static String _visionStatus(String status) => switch (status) {
        'uploading' => '正在上传的照片',
        'pending' || 'processing' => '正在识别的照片',
        'completed' => '待确认的识别草稿',
        'failed' => '识别失败，可重试',
        _ => '等待联网识别的照片',
      };
}

class _ProgressMetric extends StatelessWidget {
  const _ProgressMetric({
    required this.label,
    required this.value,
    required this.target,
    required this.unit,
  });

  final String label;
  final double value;
  final double? target;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final progress = target == null || target == 0
        ? 0.0
        : (value / target!).clamp(0.0, 1.0).toDouble();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label)),
              Text(
                target == null
                    ? '${value.toStringAsFixed(0)} $unit'
                    : '${value.toStringAsFixed(0)} / ${target!.toStringAsFixed(0)} $unit',
              ),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: progress),
        ],
      ),
    );
  }
}

class _MealSection extends StatelessWidget {
  const _MealSection({
    required this.mealType,
    required this.meals,
    required this.onAdd,
    required this.onEditItem,
  });

  final String mealType;
  final List<MealModel> meals;
  final VoidCallback onAdd;
  final void Function(MealModel meal, MealItemModel item) onEditItem;

  @override
  Widget build(BuildContext context) {
    final label = const {
      'breakfast': '早餐',
      'lunch': '午餐',
      'dinner': '晚餐',
      'snack': '加餐',
    }[mealType]!;
    final calories = meals.fold<double>(
      0,
      (sum, meal) => sum + meal.totals.calories,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('$label · ${calories.toStringAsFixed(0)} kcal'),
                ),
                IconButton(
                  tooltip: '添加食物',
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
            if (meals.isEmpty)
              const Align(alignment: Alignment.centerLeft, child: Text('尚未记录'))
            else
              for (final meal in meals)
                for (final item in meal.items)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Row(
                      children: [
                        Expanded(child: Text(item.foodName)),
                        if (meal.pending)
                          const Icon(Icons.cloud_upload_outlined, size: 16),
                      ],
                    ),
                    subtitle: Text(
                      '${item.amount.toStringAsFixed(1)} ${item.unit}',
                    ),
                    trailing: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${item.nutrition.calories.toStringAsFixed(0)} kcal',
                        ),
                        Text(
                          '蛋白质 ${item.nutrition.protein.toStringAsFixed(1)} g',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    onTap: () => onEditItem(meal, item),
                  ),
          ],
        ),
      ),
    );
  }
}
