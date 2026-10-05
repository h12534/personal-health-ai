import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/widgets/app_components.dart';
import '../../../core/theme/app_tokens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/database/local_database.dart';
import '../../coach/presentation/canteen_screen.dart';
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
      loading: () => const LoadingState(label: '正在读取饮食记录'),
      error: (error, stack) => ErrorState(
          error: error,
          onRetry: () =>
              ref.read(nutritionControllerProvider.notifier).refresh()),
      data: (data) => NutritionContent(
        data: data,
        onRefresh: () =>
            ref.read(nutritionControllerProvider.notifier).refresh(),
        onAddFood: (mealType) => _openFoodSearch(context, ref, mealType),
        onEditItem: (meal, item) => _editItem(context, ref, meal, item),
        onAnalyzePhoto: () => _openMealPhoto(context, ref),
        onResumeVision: (task) => _openVisionTask(context, ref, task),
        onOpenCanteen: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CanteenScreen()),
        ),
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
              error is PlatformException &&
                      const {
                        'camera_access_denied',
                        'photo_access_denied',
                        'camera_access_restricted',
                        'photo_access_restricted'
                      }.contains(error.code)
                  ? '无法访问相机或相册，请在系统设置中授予权限。'
                  : UiFailure.message(error),
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
        await showDialog<bool>(
            context: context,
            builder: (_) => AwaitedEntryDialog(
                title: '删除这条餐食记录？',
                content: Text('${item.foodName} · '
                    '${AppFormat.editableNumber(item.amount)} '
                    '${item.unit == 'serving' ? '份' : item.unit}'),
                validate: () => null,
                saveLabel: '确认删除',
                busyLabel: '正在删除…',
                retryLabel: '重试删除',
                destructive: true,
                onSave: () => ref
                    .read(nutritionControllerProvider.notifier)
                    .deleteItem(meal, item)));
        return;
      }
      await showDialog<bool>(
          context: context,
          builder: (_) => NumberEntryDialog(
              title: '修改 ${item.foodName}',
              initialValue: AppFormat.editableNumber(item.amount),
              unit: item.unit,
              onSave: (amount) => ref
                  .read(nutritionControllerProvider.notifier)
                  .updateItem(meal, item, amount)));
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(UiFailure.message(error))));
      }
    }
  }
}

class NutritionContent extends StatelessWidget {
  const NutritionContent(
      {super.key,
      required this.data,
      required this.onRefresh,
      required this.onAddFood,
      required this.onEditItem,
      this.onAnalyzePhoto,
      this.onResumeVision,
      this.onOpenCanteen});
  final NutritionViewState data;
  final Future<void> Function() onRefresh;
  final void Function(String) onAddFood;
  final void Function(MealModel, MealItemModel) onEditItem;
  final VoidCallback? onAnalyzePhoto, onOpenCanteen;
  final void Function(VisionTaskRecord)? onResumeVision;

  @override
  Widget build(BuildContext context) {
    final totals = data.daily.totals;
    final goal = data.goal;
    String ratio(double value, double? target, String unit) =>
        target != null && target > 0
            ? '${AppFormat.number(value)} / ${AppFormat.number(target)} $unit'
            : '${AppFormat.number(value)} $unit';
    return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: AppSpacing.pageInsets,
            children: [
              // Bounded daily summary together; meal sections remain lazy.
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                RootPageHeader(
                    title: '今日饮食',
                    subtitle: '${AppFormat.date(data.daily.date)} · 按实际份量记录。',
                    action: data.offline
                        ? const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text('离线模式', style: AppTypography.caption))
                        : null),
                if (data.offline)
                  Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text('离线记录中 · 当前仅显示本机待同步记录',
                          style: AppTypography.caption.copyWith(
                              color: AppColors.of(context).secondaryText))),
                Semantics(
                    header: true,
                    child:
                        const Text('今日营养', style: AppTypography.sectionTitle)),
                ProgressMetric(
                    label: '热量',
                    value: ratio(
                        totals.calories, goal?.calories.toDouble(), 'kcal'),
                    amount: totals.calories,
                    target: goal?.calories.toDouble(),
                    unit: 'kcal'),
                ProgressMetric(
                    label: '蛋白质',
                    value: ratio(totals.protein, goal?.protein, 'g'),
                    amount: totals.protein,
                    target: goal?.protein,
                    unit: 'g'),
                ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('碳水、脂肪与纤维'),
                    children: [
                      MetricRow(
                          label: '碳水',
                          value:
                              '${AppFormat.number(totals.carbs, decimals: 1)} g'),
                      MetricRow(
                          label: '脂肪',
                          value:
                              '${AppFormat.number(totals.fat, decimals: 1)} g'),
                      MetricRow(
                          label: '膳食纤维',
                          value:
                              '${AppFormat.number(totals.fiber, decimals: 1)} g',
                          detail: goal == null
                              ? '目标待设置'
                              : '目标 ${AppFormat.number(goal.fiber)} g'),
                    ]),
                if (data.nextMeal case final plan?) ...[
                  const SizedBox(height: 20),
                  InsightBlock(
                      title: '下一餐 · ${plan.mealLabel}',
                      prominent: true,
                      message:
                          '${plan.target.caloriesMin}–${plan.target.caloriesMax} kcal · 蛋白质 ${AppFormat.number(plan.target.proteinMin)}–${AppFormat.number(plan.target.proteinMax)} g'
                          '${plan.strategy.isNotEmpty ? '\n${plan.strategy.first}' : plan.message.isNotEmpty ? '\n${plan.message}' : ''}',
                      action: TextButton.icon(
                          onPressed: onOpenCanteen,
                          icon: const Icon(Icons.storefront_outlined, size: 20),
                          label: const Text('按食堂菜品推荐'))),
                ],
                AppSection(
                    title: '拍照识别一餐',
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('先生成可编辑草稿，确认后才计入营养。',
                              style: AppTypography.secondary),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                              onPressed: onAnalyzePhoto,
                              icon: const Icon(Icons.camera_alt_outlined),
                              label: const Text('拍照记饮食')),
                        ])),
                if (data.visionTasks.isNotEmpty)
                  AppSection(
                      title: '照片草稿',
                      child: Column(children: [
                        for (final task in data.visionTasks)
                          ListRow(
                              title: _visionStatus(task.status),
                              subtitle: task.lastError == null
                                  ? '照片已保存在本机'
                                  : '暂未完成，打开草稿查看恢复选项',
                              icon: Icons.document_scanner_outlined,
                              onTap: onResumeVision == null
                                  ? null
                                  : () => onResumeVision!(task)),
                      ])),
              ]),
              for (final type in const [
                'breakfast',
                'lunch',
                'dinner',
                'snack'
              ])
                _MealSection(
                    mealType: type,
                    meals: data.meals
                        .where((meal) => meal.mealType == type)
                        .toList(),
                    aggregate: data.daily.meals[type],
                    knownCount: data.daily.mealCounts[type] ?? 0,
                    onAdd: () => onAddFood(type),
                    onEditItem: onEditItem),
            ]));
  }

  static String _visionStatus(String status) => switch (status) {
        'uploading' => '正在上传的照片',
        'pending' || 'processing' => '正在识别的照片',
        'completed' => '待确认的识别草稿',
        'confirmed' => '已经保存的餐食',
        'failed' => '识别未完成，可重试',
        'waiting_network' => '等待联网识别',
        _ => '草稿状态待确认',
      };
}

class _MealSection extends StatelessWidget {
  const _MealSection(
      {required this.mealType,
      required this.meals,
      required this.onAdd,
      required this.onEditItem,
      required this.knownCount,
      this.aggregate});
  final String mealType;
  final List<MealModel> meals;
  final NutritionTotals? aggregate;
  final int knownCount;
  final VoidCallback onAdd;
  final void Function(MealModel, MealItemModel) onEditItem;
  @override
  Widget build(BuildContext context) {
    final label = const {
      'breakfast': '早餐',
      'lunch': '午餐',
      'dinner': '晚餐',
      'snack': '加餐'
    }[mealType]!;
    final calories = aggregate?.calories ??
        meals.fold<double>(0, (sum, meal) => sum + meal.totals.calories);
    // Offline fallback pre-fills all four aggregates with zeros; existence
    // alone is not evidence that a meal has been recorded.
    final summary = aggregate;
    final hasRecord = meals.isNotEmpty ||
        knownCount > 0 ||
        (summary != null &&
            [
              summary.calories,
              summary.protein,
              summary.carbs,
              summary.fat,
              summary.fiber
            ].any((value) => value != 0));
    return AppSection(
        title:
            hasRecord ? '$label · ${AppFormat.number(calories)} kcal' : label,
        action: meals.isEmpty
            ? null
            : Semantics(
                label: '添加$label食物',
                child: TextButton(onPressed: onAdd, child: const Text('添加'))),
        child: meals.isEmpty
            ? EmptyState(
                title: hasRecord ? '餐食明细暂不可用' : '尚未记录',
                message: hasRecord ? '已有餐次汇总，刷新后再查看条目。' : '从这餐的第一项食物开始。',
                actionLabel: '记录$label',
                onAction: onAdd)
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final meal in meals) ...[
                  if (meal.pending)
                    Text('待同步 · 已保存在本机',
                        style: AppTypography.caption.copyWith(
                            color: AppColors.of(context).secondaryText)),
                  for (final item in meal.items)
                    ListRow(
                        title: item.foodName,
                        subtitle:
                            '${AppFormat.number(item.amount, decimals: 1)} ${item.unit} · ${AppFormat.number(item.nutrition.calories)} kcal\n蛋白质 ${AppFormat.number(item.nutrition.protein, decimals: 1)} g',
                        onTap: () => onEditItem(meal, item)),
                ],
              ]));
  }
}
