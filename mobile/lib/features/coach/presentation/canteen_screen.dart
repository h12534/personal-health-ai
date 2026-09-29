import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../dashboard/presentation/dashboard_controller.dart';
import '../../nutrition/presentation/nutrition_controller.dart';
import '../data/coach_models.dart';
import 'coach_controller.dart';

class CanteenScreen extends ConsumerWidget {
  const CanteenScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canteens = ref.watch(canteensProvider);
    final recommendations = ref.watch(canteenRecommendationsProvider);
    final savedMeals = ref.watch(savedMealsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('学校饮食')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editCanteen(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('新增食堂'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([
            ref.refresh(canteensProvider.future),
            ref.refresh(canteenRecommendationsProvider.future),
            ref.refresh(savedMealsProvider.future),
          ]);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            _SectionTitle(
              title: '常吃套餐',
              subtitle: '一键记录会生成新的餐次，不会复用旧 Meal ID。',
            ),
            _SavedMeals(
              value: savedMeals,
              onLog: (value) => _logSavedMeal(context, ref, value),
            ),
            const SizedBox(height: 18),
            _SectionTitle(
              title: '我的食堂',
              subtitle: '按食堂、档口和菜品逐步积累；无需一次录完整个食堂。',
            ),
            _CanteenTree(
              value: canteens,
              onEditCanteen: (value) => _editCanteen(context, ref, value),
              onAddStall: (value) => _editStall(context, ref, value),
              onEditStall: (canteen, stall) =>
                  _editStall(context, ref, canteen, stall),
              onAddDish: (stall) => _editDish(context, ref, stall),
              onEditDish: (stall, dish) => _editDish(context, ref, stall, dish),
              onToggleFavorite: (dish) => _toggleFavorite(context, ref, dish),
            ),
            const SizedBox(height: 18),
            _SectionTitle(
              title: '现在吃什么',
              subtitle: '按今天的热量和蛋白质缺口给出多个可执行选择，不做“健康评分”。',
            ),
            _Recommendations(value: recommendations),
          ],
        ),
      ),
    );
  }

  static Future<void> _logSavedMeal(
    BuildContext context,
    WidgetRef ref,
    SavedMealModel value,
  ) async {
    try {
      await ref.read(apiClientProvider).logSavedMeal(value);
      ref.invalidate(nutritionControllerProvider);
      ref.invalidate(nextMealProvider);
      ref.invalidate(coachOverviewProvider);
      ref.invalidate(dashboardProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已记录“${value.name}”')),
        );
      }
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  static Future<void> _editCanteen(
    BuildContext context,
    WidgetRef ref, [
    CanteenModel? value,
  ]) async {
    final name = TextEditingController(text: value?.name);
    final campus = TextEditingController(text: value?.campus);
    final location = TextEditingController(text: value?.location);
    final note = TextEditingController(text: value?.note);
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(value == null ? '新增食堂' : '编辑食堂'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: '名称 *'),
              ),
              TextField(
                controller: campus,
                decoration: const InputDecoration(labelText: '校区'),
              ),
              TextField(
                controller: location,
                decoration: const InputDecoration(labelText: '位置'),
              ),
              TextField(
                controller: note,
                decoration: const InputDecoration(labelText: '备注'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, name.text.trim().isNotEmpty),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (save == true) {
      await ref.read(apiClientProvider).saveCanteen(
            id: value?.id,
            name: name.text.trim(),
            campus: _optional(campus.text),
            location: _optional(location.text),
            note: _optional(note.text),
          );
      _refreshCanteens(ref);
    }
    name.dispose();
    campus.dispose();
    location.dispose();
    note.dispose();
  }

  static Future<void> _editStall(
    BuildContext context,
    WidgetRef ref,
    CanteenModel canteen, [
    CanteenStallModel? value,
  ]) async {
    final name = TextEditingController(text: value?.name);
    final cuisine = TextEditingController(text: value?.cuisine);
    final floor = TextEditingController(text: value?.floor);
    final location = TextEditingController(text: value?.locationNote);
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(value == null ? '新增档口' : '编辑档口'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: '档口名称 *'),
              ),
              TextField(
                controller: cuisine,
                decoration: const InputDecoration(labelText: '菜系'),
              ),
              TextField(
                controller: floor,
                decoration: const InputDecoration(labelText: '楼层'),
              ),
              TextField(
                controller: location,
                decoration: const InputDecoration(labelText: '位置备注'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, name.text.trim().isNotEmpty),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (save == true) {
      await ref.read(apiClientProvider).saveCanteenStall(
            id: value?.id,
            canteenId: canteen.id,
            name: name.text.trim(),
            cuisine: _optional(cuisine.text),
            floor: _optional(floor.text),
            locationNote: _optional(location.text),
          );
      _refreshCanteens(ref);
    }
    name.dispose();
    cuisine.dispose();
    floor.dispose();
    location.dispose();
  }

  static Future<void> _editDish(
    BuildContext context,
    WidgetRef ref,
    CanteenStallModel stall, [
    CanteenDishModel? value,
  ]) async {
    final name = TextEditingController(text: value?.name);
    final calories =
        TextEditingController(text: _displayNumber(value?.calories));
    final protein = TextEditingController(text: _displayNumber(value?.protein));
    final carbs = TextEditingController(text: _displayNumber(value?.carbs));
    final fat = TextEditingController(text: _displayNumber(value?.fat));
    final fiber = TextEditingController(text: _displayNumber(value?.fiber));
    final portion = TextEditingController(text: value?.portionDescription);
    final weight =
        TextEditingController(text: _displayNumber(value?.averageWeight));
    var favorite = value?.favorite ?? false;
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(value == null ? '新增菜品' : '编辑菜品'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: '菜品名称 *'),
                ),
                Row(
                  children: [
                    Expanded(child: _NumberField(calories, '热量 kcal *')),
                    const SizedBox(width: 10),
                    Expanded(child: _NumberField(protein, '蛋白质 g *')),
                  ],
                ),
                Row(
                  children: [
                    Expanded(child: _NumberField(carbs, '碳水 g')),
                    const SizedBox(width: 10),
                    Expanded(child: _NumberField(fat, '脂肪 g')),
                  ],
                ),
                _NumberField(fiber, '纤维 g'),
                TextField(
                  controller: portion,
                  decoration: const InputDecoration(labelText: '份量描述'),
                ),
                _NumberField(weight, '平均重量 g（可选）'),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('收藏菜品'),
                  value: favorite,
                  onChanged: (next) => setState(() => favorite = next),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final requiredNumbers = [calories, protein]
                    .map((controller) => double.tryParse(controller.text))
                    .toList();
                final valid = name.text.trim().isNotEmpty &&
                    requiredNumbers.every(
                      (number) => number != null && number >= 0,
                    );
                if (valid) Navigator.pop(context, true);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (save == true) {
      await ref.read(apiClientProvider).saveCanteenDish(
            id: value?.id,
            stallId: stall.id,
            name: name.text.trim(),
            calories: double.parse(calories.text),
            protein: double.parse(protein.text),
            carbs: double.tryParse(carbs.text) ?? 0,
            fat: double.tryParse(fat.text) ?? 0,
            fiber: double.tryParse(fiber.text) ?? 0,
            portionDescription: _optional(portion.text),
            averageWeight: double.tryParse(weight.text),
            confidence: value?.confidence ?? 0.5,
            favorite: favorite,
            source: value?.source ?? 'manual',
          );
      _refreshCanteens(ref);
    }
    for (final controller in [
      name,
      calories,
      protein,
      carbs,
      fat,
      fiber,
      portion,
      weight,
    ]) {
      controller.dispose();
    }
  }

  static Future<void> _toggleFavorite(
    BuildContext context,
    WidgetRef ref,
    CanteenDishModel value,
  ) async {
    try {
      await ref.read(apiClientProvider).saveCanteenDish(
            id: value.id,
            stallId: value.stallId,
            name: value.name,
            calories: value.calories,
            protein: value.protein,
            carbs: value.carbs,
            fat: value.fat,
            fiber: value.fiber,
            portionDescription: value.portionDescription,
            averageWeight: value.averageWeight,
            confidence: value.confidence,
            favorite: !value.favorite,
            source: value.source,
          );
      _refreshCanteens(ref);
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  static void _refreshCanteens(WidgetRef ref) {
    ref.invalidate(canteensProvider);
    ref.invalidate(canteenRecommendationsProvider);
  }

  static String? _optional(String value) {
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  static String _displayNumber(double? value) =>
      value == null ? '' : value.toStringAsFixed(value % 1 == 0 ? 0 : 1);
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 2),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
}

class _SavedMeals extends StatelessWidget {
  const _SavedMeals({required this.value, required this.onLog});

  final AsyncValue<List<SavedMealModel>> value;
  final Future<void> Function(SavedMealModel) onLog;

  @override
  Widget build(BuildContext context) => value.when(
        loading: () => const LinearProgressIndicator(),
        error: (error, stack) => const Text('常吃套餐暂时无法加载'),
        data: (values) => values.isEmpty
            ? const Card(
                child: ListTile(
                  leading: Icon(Icons.bookmark_border),
                  title: Text('还没有常吃套餐'),
                  subtitle: Text('可通过 Saved Meal API 保存早餐、食堂或便利店组合。'),
                ),
              )
            : Column(
                children: [
                  for (final item in values)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.bookmark_outline),
                        title: Text(item.name),
                        subtitle: Text(
                          '${item.itemCount} 项 · ${item.totalCalories.toStringAsFixed(0)} kcal',
                        ),
                        trailing: FilledButton.tonal(
                          onPressed: () => onLog(item),
                          child: const Text('一键记录'),
                        ),
                      ),
                    ),
                ],
              ),
      );
}

class _CanteenTree extends StatelessWidget {
  const _CanteenTree({
    required this.value,
    required this.onEditCanteen,
    required this.onAddStall,
    required this.onEditStall,
    required this.onAddDish,
    required this.onEditDish,
    required this.onToggleFavorite,
  });

  final AsyncValue<List<CanteenModel>> value;
  final void Function(CanteenModel) onEditCanteen;
  final void Function(CanteenModel) onAddStall;
  final void Function(CanteenModel, CanteenStallModel) onEditStall;
  final void Function(CanteenStallModel) onAddDish;
  final void Function(CanteenStallModel, CanteenDishModel) onEditDish;
  final void Function(CanteenDishModel) onToggleFavorite;

  @override
  Widget build(BuildContext context) => value.when(
        loading: () => const LinearProgressIndicator(),
        error: (error, stack) => const Text('食堂列表加载失败'),
        data: (values) => values.isEmpty
            ? const Card(
                child: ListTile(
                  leading: Icon(Icons.storefront_outlined),
                  title: Text('还没有食堂'),
                  subtitle: Text('点击右下角新增，之后再逐步添加档口和菜品。'),
                ),
              )
            : Column(
                children: [
                  for (final canteen in values)
                    Card(
                      child: ExpansionTile(
                        leading: const Icon(Icons.storefront_outlined),
                        title: Text(canteen.name),
                        subtitle: Text(
                          [canteen.campus, canteen.location]
                              .whereType<String>()
                              .where((value) => value.isNotEmpty)
                              .join(' · '),
                        ),
                        trailing: IconButton(
                          tooltip: '编辑食堂',
                          onPressed: () => onEditCanteen(canteen),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        children: [
                          if (canteen.stalls.isEmpty)
                            const ListTile(
                              title: Text('暂无档口'),
                              subtitle: Text('先添加一个经常购买的档口。'),
                            ),
                          for (final stall in canteen.stalls)
                            _StallTile(
                              stall: stall,
                              onEdit: () => onEditStall(canteen, stall),
                              onAddDish: () => onAddDish(stall),
                              onEditDish: (dish) => onEditDish(stall, dish),
                              onToggleFavorite: onToggleFavorite,
                            ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () => onAddStall(canteen),
                              icon: const Icon(Icons.add),
                              label: const Text('新增档口'),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
      );
}

class _StallTile extends StatelessWidget {
  const _StallTile({
    required this.stall,
    required this.onEdit,
    required this.onAddDish,
    required this.onEditDish,
    required this.onToggleFavorite,
  });

  final CanteenStallModel stall;
  final VoidCallback onEdit;
  final VoidCallback onAddDish;
  final void Function(CanteenDishModel) onEditDish;
  final void Function(CanteenDishModel) onToggleFavorite;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 16, right: 8),
        child: ExpansionTile(
          leading: const Icon(Icons.countertops_outlined),
          title: Text(stall.name),
          subtitle: Text(
            [stall.floor, stall.cuisine]
                .whereType<String>()
                .where((value) => value.isNotEmpty)
                .join(' · '),
          ),
          trailing: IconButton(
            tooltip: '编辑档口',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
          ),
          children: [
            if (stall.dishes.isEmpty)
              const ListTile(title: Text('暂无菜品，吃过后再慢慢添加。')),
            for (final dish in stall.dishes)
              ListTile(
                leading: IconButton(
                  tooltip: dish.favorite ? '取消收藏' : '收藏',
                  onPressed: () => onToggleFavorite(dish),
                  icon: Icon(
                    dish.favorite ? Icons.star : Icons.star_border,
                    color: dish.favorite ? Colors.amber.shade700 : null,
                  ),
                ),
                title: Text(dish.name),
                subtitle: Text(
                  '${dish.calories.toStringAsFixed(0)} kcal · '
                  '蛋白质 ${dish.protein.toStringAsFixed(0)} g',
                ),
                trailing: IconButton(
                  tooltip: '编辑菜品',
                  onPressed: () => onEditDish(dish),
                  icon: const Icon(Icons.edit_outlined),
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onAddDish,
                icon: const Icon(Icons.add),
                label: const Text('新增菜品'),
              ),
            ),
          ],
        ),
      );
}

class _Recommendations extends StatelessWidget {
  const _Recommendations({required this.value});

  final AsyncValue<List<CanteenRecommendationModel>> value;

  @override
  Widget build(BuildContext context) => value.when(
        loading: () => const LinearProgressIndicator(),
        error: (error, stack) => const Card(
          child: ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('还没有可推荐的菜品'),
            subtitle: Text('新增菜品后，系统会结合下一餐范围给出多个选项。'),
          ),
        ),
        data: (values) => values.isEmpty
            ? const Card(child: ListTile(title: Text('暂无可用菜品')))
            : Column(
                children: [
                  for (final item in values)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.restaurant_outlined),
                        title: Text(item.dishName),
                        subtitle: Text(
                          '${item.calories.toStringAsFixed(0)} kcal · '
                          '蛋白质 ${item.protein.toStringAsFixed(0)} g\n'
                          '${item.reasons.join('；')}',
                        ),
                        isThreeLine: true,
                      ),
                    ),
                ],
              ),
      );
}

class _NumberField extends StatelessWidget {
  const _NumberField(this.controller, this.label);

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label),
      );
}
