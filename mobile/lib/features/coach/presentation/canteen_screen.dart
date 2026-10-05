import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_components.dart';
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
      appBar: DetailPageHeader(label: '学校饮食'),
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([
            ref.refresh(canteensProvider.future),
            ref.refresh(canteenRecommendationsProvider.future),
            ref.refresh(savedMealsProvider.future),
          ]);
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
                padding: AppSpacing.pageInsets,
                sliver: SliverMainAxisGroup(slivers: [
                  SliverToBoxAdapter(
                      child: _SectionTitle(
                    title: '常吃套餐',
                    subtitle: '从已经保存的组合开始，记录一餐。',
                  )),
                  _SavedMeals(
                    value: savedMeals,
                    onLog: (value) => _logSavedMeal(context, ref, value),
                    onReload: () => ref.invalidate(savedMealsProvider),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 18)),
                  SliverToBoxAdapter(
                      child: _SectionTitle(
                    title: '我的食堂',
                    subtitle: '按食堂、档口和菜品逐步积累；无需一次录完整个食堂。',
                  )),
                  _CanteenTree(
                    value: canteens,
                    onReload: () => ref.invalidate(canteensProvider),
                    onAddCanteen: () => _editCanteen(context, ref),
                    onEditCanteen: (value) => _editCanteen(context, ref, value),
                    onAddStall: (value) => _editStall(context, ref, value),
                    onEditStall: (canteen, stall) =>
                        _editStall(context, ref, canteen, stall),
                    onAddDish: (stall) => _editDish(context, ref, stall),
                    onEditDish: (stall, dish) =>
                        _editDish(context, ref, stall, dish),
                    onToggleFavorite: (dish) =>
                        _toggleFavorite(context, ref, dish),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 18)),
                  SliverToBoxAdapter(
                      child: _SectionTitle(
                    title: '现在吃什么',
                    subtitle: '按今天的热量和蛋白质缺口给出多个可执行选择，不做“健康评分”。',
                  )),
                  _Recommendations(
                      value: recommendations,
                      onReload: () =>
                          ref.invalidate(canteenRecommendationsProvider),
                      onAddCanteen: () => _editCanteen(context, ref)),
                ]))
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
            .showSnackBar(SnackBar(content: Text(UiFailure.message(error))));
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
    await showDialog<bool>(
      context: context,
      builder: (context) => AwaitedEntryDialog(
        title: value == null ? '新增食堂' : '编辑食堂',
        content: Column(
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
        validate: () => name.text.trim().isEmpty ? '请填写食堂名称' : null,
        onSave: () async {
          await ref.read(apiClientProvider).saveCanteen(
                id: value?.id,
                name: name.text.trim(),
                campus: _optional(campus.text),
                location: _optional(location.text),
                note: _optional(note.text),
              );
          _refreshCanteens(ref);
        },
      ),
    );
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
    await showDialog<bool>(
      context: context,
      builder: (context) => AwaitedEntryDialog(
        title: value == null ? '新增档口' : '编辑档口',
        content: Column(
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
        validate: () => name.text.trim().isEmpty ? '请填写档口名称' : null,
        onSave: () async {
          await ref.read(apiClientProvider).saveCanteenStall(
                id: value?.id,
                canteenId: canteen.id,
                name: name.text.trim(),
                cuisine: _optional(cuisine.text),
                floor: _optional(floor.text),
                locationNote: _optional(location.text),
              );
          _refreshCanteens(ref);
        },
      ),
    );
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
    await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AwaitedEntryDialog(
          title: value == null ? '新增菜品' : '编辑菜品',
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: '菜品名称 *'),
              ),
              _NumberField(calories, '热量 kcal *'),
              _NumberField(protein, '蛋白质 g *'),
              _NumberField(carbs, '碳水 g'),
              _NumberField(fat, '脂肪 g'),
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
          validate: () {
            if (name.text.trim().isEmpty) return '请填写菜品名称';
            for (final input in [
              calories,
              protein,
              carbs,
              fat,
              fiber,
              weight
            ]) {
              if (input.text.trim().isEmpty &&
                  input != calories &&
                  input != protein) {
                continue;
              }
              final number = double.tryParse(input.text.trim());
              if (number == null || !number.isFinite || number < 0) {
                return '营养数值请填写有效的非负数字';
              }
            }
            return null;
          },
          onSave: () async {
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
          },
        ),
      ),
    );
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
            .showSnackBar(SnackBar(content: Text(UiFailure.message(error))));
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
      value == null ? '' : AppFormat.editableNumber(value);
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
  const _SavedMeals(
      {required this.value, required this.onLog, required this.onReload});

  final AsyncValue<List<SavedMealModel>> value;
  final Future<void> Function(SavedMealModel) onLog;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) => value.when(
        loading: () => const SliverToBoxAdapter(
            child: LoadingState(inline: true, label: '正在读取套餐')),
        error: (error, stack) => SliverToBoxAdapter(
            child: ErrorState(error: error, onRetry: onReload, inline: true)),
        data: (values) => values.isEmpty
            ? SliverToBoxAdapter(
                child: EmptyState(
                    title: '还没有常吃套餐',
                    message: '这里显示已经保存的组合。也可以返回饮食页，逐项记录这一餐。',
                    actionLabel: '重新读取',
                    onAction: onReload))
            : SliverList.builder(
                itemCount: values.length,
                findChildIndexCallback: (key) {
                  final index =
                      values.indexWhere((item) => ValueKey(item.id) == key);
                  return index < 0 ? null : index;
                },
                itemBuilder: (context, index) {
                  final item = values[index];
                  return _PendingActionRow(
                      key: ValueKey(item.id),
                      onAction: () => onLog(item),
                      builder: (run) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.name,
                                      style: AppTypography.cardTitle),
                                  Text(
                                      '${item.itemCount} 项 · ${item.totalCalories.toStringAsFixed(0)} kcal'),
                                  AsyncActionButton(
                                      onPressed: run, label: '一键记录'),
                                ]),
                          ));
                }),
      );
}

// Recycle idle rows, but never reset an in-flight action by scrolling it away.
class _PendingActionRow extends StatefulWidget {
  const _PendingActionRow(
      {super.key, required this.onAction, required this.builder});
  final Future<void> Function() onAction;
  final Widget Function(Future<void> Function()) builder;

  @override
  State<_PendingActionRow> createState() => _PendingActionRowState();
}

class _PendingActionRowState extends State<_PendingActionRow>
    with AutomaticKeepAliveClientMixin {
  bool _pending = false;
  @override
  bool get wantKeepAlive => _pending;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.builder(_run);
  }

  Future<void> _run() async {
    if (_pending) return;
    _pending = true;
    updateKeepAlive();
    try {
      await widget.onAction();
    } finally {
      if (mounted) {
        _pending = false;
        updateKeepAlive();
      }
    }
  }
}

enum _TreeRowKind {
  canteen,
  stall,
  dish,
  emptyStall,
  emptyDish,
  addStall,
  addDish
}

class _TreeRow {
  const _TreeRow(this.kind, this.canteen, {this.stall, this.dish});
  final _TreeRowKind kind;
  final CanteenModel canteen;
  final CanteenStallModel? stall;
  final CanteenDishModel? dish;
  String get identity =>
      '${kind.name}:${canteen.id}:${stall?.id ?? ''}:${dish?.id ?? ''}';
}

// One viewport owns the whole hierarchy. Expansion changes row descriptors,
// not nested shrink-wrapped lists or a Column containing every dish widget.
class _CanteenTree extends StatefulWidget {
  const _CanteenTree({
    required this.value,
    required this.onEditCanteen,
    required this.onAddStall,
    required this.onEditStall,
    required this.onAddDish,
    required this.onEditDish,
    required this.onToggleFavorite,
    required this.onReload,
    required this.onAddCanteen,
  });

  final AsyncValue<List<CanteenModel>> value;
  final void Function(CanteenModel) onEditCanteen;
  final void Function(CanteenModel) onAddStall;
  final void Function(CanteenModel, CanteenStallModel) onEditStall;
  final void Function(CanteenStallModel) onAddDish;
  final void Function(CanteenStallModel, CanteenDishModel) onEditDish;
  final Future<void> Function(CanteenDishModel) onToggleFavorite;
  final VoidCallback onReload, onAddCanteen;

  @override
  State<_CanteenTree> createState() => _CanteenTreeState();
}

class _CanteenTreeState extends State<_CanteenTree> {
  final _canteens = <String>{}, _stalls = <String>{};
  final _pendingDishes = <String>{};

  Future<void> _toggleDish(CanteenDishModel dish) async {
    if (_pendingDishes.contains(dish.id)) return;
    setState(() => _pendingDishes.add(dish.id));
    try {
      await widget.onToggleFavorite(dish);
    } finally {
      if (mounted) setState(() => _pendingDishes.remove(dish.id));
    }
  }

  void _expand(Set<String> values, String id, bool expanded) => setState(() {
        expanded ? values.add(id) : values.remove(id);
      });

  List<_TreeRow> _rows(List<CanteenModel> values) {
    final rows = <_TreeRow>[];
    for (final canteen in values) {
      rows.add(_TreeRow(_TreeRowKind.canteen, canteen));
      if (!_canteens.contains(canteen.id)) continue;
      if (canteen.stalls.isEmpty) {
        rows.add(_TreeRow(_TreeRowKind.emptyStall, canteen));
      }
      for (final stall in canteen.stalls) {
        rows.add(_TreeRow(_TreeRowKind.stall, canteen, stall: stall));
        if (!_stalls.contains(stall.id)) continue;
        if (stall.dishes.isEmpty) {
          rows.add(_TreeRow(_TreeRowKind.emptyDish, canteen, stall: stall));
        }
        for (final dish in stall.dishes) {
          rows.add(
              _TreeRow(_TreeRowKind.dish, canteen, stall: stall, dish: dish));
        }
        rows.add(_TreeRow(_TreeRowKind.addDish, canteen, stall: stall));
      }
      rows.add(_TreeRow(_TreeRowKind.addStall, canteen));
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) => widget.value.when(
        loading: () => const SliverToBoxAdapter(
            child: LoadingState(inline: true, label: '正在读取食堂')),
        error: (error, stack) => SliverToBoxAdapter(
            child: ErrorState(
                error: error, onRetry: widget.onReload, inline: true)),
        data: (values) {
          if (values.isEmpty) {
            return SliverToBoxAdapter(
                child: EmptyState(
                    title: '还没有食堂',
                    message: '先记住一个常去的地方，再逐步添加档口和菜品。',
                    actionLabel: '新增食堂',
                    onAction: widget.onAddCanteen));
          }
          final rows = _rows(values);
          final indices = {
            for (var i = 0; i < rows.length; i++) ValueKey(rows[i].identity): i
          };
          return SliverMainAxisGroup(slivers: [
            SliverToBoxAdapter(
                child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                        onPressed: widget.onAddCanteen,
                        icon: const Icon(Icons.add),
                        label: const Text('新增食堂')))),
            SliverList.builder(
                itemCount: rows.length,
                findChildIndexCallback: (key) => indices[key],
                itemBuilder: (context, index) => KeyedSubtree(
                    key: ValueKey(rows[index].identity),
                    child: _row(rows[index]))),
          ]);
        },
      );

  Widget _row(_TreeRow row) {
    final canteen = row.canteen, stall = row.stall;
    switch (row.kind) {
      case _TreeRowKind.canteen:
        return ExpansionTile(
            initiallyExpanded: _canteens.contains(canteen.id),
            onExpansionChanged: (expanded) =>
                _expand(_canteens, canteen.id, expanded),
            leading: const Icon(Icons.storefront_outlined),
            title: Text(canteen.name),
            subtitle: Text([canteen.campus, canteen.location]
                .whereType<String>()
                .where((value) => value.isNotEmpty)
                .join(' · ')),
            trailing: IconButton(
                tooltip: '编辑食堂',
                onPressed: () => widget.onEditCanteen(canteen),
                icon: const Icon(Icons.edit_outlined)));
      case _TreeRowKind.stall:
        return Padding(
            padding: const EdgeInsets.only(left: 16, right: 8),
            child: ExpansionTile(
                initiallyExpanded: _stalls.contains(stall!.id),
                onExpansionChanged: (expanded) =>
                    _expand(_stalls, stall.id, expanded),
                leading: const Icon(Icons.countertops_outlined),
                title: Text(stall.name),
                subtitle: Text([stall.floor, stall.cuisine]
                    .whereType<String>()
                    .where((value) => value.isNotEmpty)
                    .join(' · ')),
                trailing: IconButton(
                    tooltip: '编辑档口',
                    onPressed: () => widget.onEditStall(canteen, stall),
                    icon: const Icon(Icons.edit_outlined))));
      case _TreeRowKind.dish:
        final dish = row.dish!;
        return Padding(
            padding: const EdgeInsets.only(left: 16, right: 8),
            child: _PendingActionRow(
                onAction: () => _toggleDish(dish),
                builder: (run) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ListTile(
                              title: Text(dish.name),
                              subtitle: Text(
                                  '${dish.calories.toStringAsFixed(0)} kcal · '
                                  '蛋白质 ${dish.protein.toStringAsFixed(0)} g'),
                              trailing: IconButton(
                                  tooltip: '编辑菜品',
                                  onPressed: () =>
                                      widget.onEditDish(stall!, dish),
                                  icon: const Icon(Icons.edit_outlined))),
                          AsyncActionButton(
                              busy: _pendingDishes.contains(dish.id),
                              label: dish.favorite ? '取消收藏' : '收藏',
                              icon: dish.favorite
                                  ? Icons.star
                                  : Icons.star_border,
                              onPressed: run),
                        ])));
      case _TreeRowKind.emptyStall:
        return const ListTile(
            title: Text('暂无档口'), subtitle: Text('先添加一个经常购买的档口。'));
      case _TreeRowKind.emptyDish:
        return const Padding(
            padding: EdgeInsets.only(left: 16, right: 8),
            child: ListTile(title: Text('暂无菜品，吃过后再慢慢添加。')));
      case _TreeRowKind.addStall:
        return Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
                onPressed: () => widget.onAddStall(canteen),
                icon: const Icon(Icons.add),
                label: const Text('新增档口')));
      case _TreeRowKind.addDish:
        return Padding(
            padding: const EdgeInsets.only(left: 16, right: 8),
            child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                    onPressed: () => widget.onAddDish(stall!),
                    icon: const Icon(Icons.add),
                    label: const Text('新增菜品'))));
    }
  }
}

class _Recommendations extends StatelessWidget {
  const _Recommendations(
      {required this.value,
      required this.onReload,
      required this.onAddCanteen});

  final AsyncValue<List<CanteenRecommendationModel>> value;
  final VoidCallback onReload, onAddCanteen;

  @override
  Widget build(BuildContext context) => value.when(
        loading: () => const SliverToBoxAdapter(
            child: LoadingState(inline: true, label: '正在读取饮食建议')),
        error: (error, stack) => SliverToBoxAdapter(
            child: ErrorState(error: error, onRetry: onReload, inline: true)),
        data: (values) => values.isEmpty
            ? SliverToBoxAdapter(
                child: EmptyState(
                    title: '还没有可推荐的菜品',
                    message: '记录食堂菜品后，可以查看下一餐的现有建议。',
                    actionLabel: '新增食堂',
                    onAction: onAddCanteen))
            : SliverList.builder(
                itemCount: values.length,
                itemBuilder: (context, index) {
                  final item = values[index];
                  return ListTile(
                      leading: const Icon(Icons.restaurant_outlined),
                      title: Text(item.dishName),
                      subtitle:
                          Text('${item.calories.toStringAsFixed(0)} kcal · '
                              '蛋白质 ${item.protein.toStringAsFixed(0)} g\n'
                              '${item.reasons.join('；')}'));
                }),
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
