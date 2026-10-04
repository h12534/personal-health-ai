import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_components.dart';

import '../data/nutrition_models.dart';
import '../data/offline_meal_repository.dart';
import 'add_food_screen.dart';

class FoodSearchScreen extends ConsumerStatefulWidget {
  const FoodSearchScreen({super.key, required this.mealType});

  final String mealType;

  @override
  ConsumerState<FoodSearchScreen> createState() => _FoodSearchScreenState();
}

class _FoodSearchScreenState extends ConsumerState<FoodSearchScreen> {
  final _queryController = TextEditingController();
  List<FoodModel> _foods = const [];
  String _mode = 'recent';
  bool _loading = true;
  Object? _error;
  int _request = 0;
  final _searchFocus = FocusNode();
  final _favoritesBusy = <String>{};

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(() => _load());
  }

  @override
  void dispose() {
    _queryController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _load({String? mode}) async {
    if (!mounted) return;
    final request = ++_request;
    final nextMode = mode ?? _mode;
    setState(() {
      _mode = nextMode;
      _loading = true;
      _error = null;
    });
    try {
      final foods = await ref
          .read(offlineMealRepositoryProvider)
          .searchFoods(_queryController.text.trim(), mode: nextMode);
      if (!mounted || request != _request) return;
      setState(() {
        _foods = foods;
        _loading = false;
      });
    } on Object catch (error) {
      if (mounted && request == _request) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: DetailPageHeader(label: '选择食物'),
        body: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
                child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: TextField(
                  controller: _queryController,
                  focusNode: _searchFocus,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _load(mode: 'search'),
                  decoration: InputDecoration(
                    hintText: '搜索米饭、鸡蛋、牛奶…',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      tooltip: '搜索食物',
                      onPressed: () => _load(mode: 'search'),
                      icon: const Icon(Icons.arrow_forward),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('最近'),
                      selected: _mode == 'recent',
                      onSelected: (_) => _load(mode: 'recent'),
                    ),
                    ChoiceChip(
                      label: const Text('收藏'),
                      selected: _mode == 'favorites',
                      onSelected: (_) => _load(mode: 'favorites'),
                    ),
                    ChoiceChip(
                      label: const Text('常见'),
                      selected: _mode == 'common',
                      onSelected: (_) => _load(mode: 'common'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ])),
            _loading
                ? const SliverToBoxAdapter(
                    child: Padding(
                        padding: AppSpacing.pageInsets,
                        child: LoadingState(label: '正在查找食物', inline: true)))
                : _error != null
                    ? SliverToBoxAdapter(
                        child: Padding(
                            padding: AppSpacing.pageInsets,
                            child: ErrorState(
                                error: _error!, onRetry: _load, inline: true)))
                    : _foods.isEmpty
                        ? SliverToBoxAdapter(
                            child: Padding(
                                padding: AppSpacing.pageInsets,
                                child: EmptyState(
                                    title: _mode == 'favorites'
                                        ? '还没有收藏食物'
                                        : '没有找到食物',
                                    message: '试试其他关键词，或查看常见食物。',
                                    actionLabel: '修改搜索词',
                                    onAction: () =>
                                        _searchFocus.requestFocus())))
                        : SliverList.separated(
                            itemCount: _foods.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final food = _foods[index];
                              return ListTile(
                                title: Text(food.name),
                                subtitle: Text(
                                  '${food.caloriesPer100g.toStringAsFixed(0)} kcal / 100g'
                                  '${food.servingDescription == null ? '' : ' · ${food.servingDescription}'}',
                                ),
                                trailing: IconButton(
                                  tooltip: food.isFavorite ? '取消收藏' : '收藏',
                                  icon: Icon(
                                    food.isFavorite
                                        ? Icons.star
                                        : Icons.star_border,
                                    color: food.isFavorite
                                        ? AppColors.of(context).accent
                                        : null,
                                  ),
                                  onPressed: _favoritesBusy.contains(food.id)
                                      ? null
                                      : () async {
                                          setState(() =>
                                              _favoritesBusy.add(food.id));
                                          try {
                                            await ref
                                                .read(
                                                    offlineMealRepositoryProvider)
                                                .setFavorite(
                                                    food, !food.isFavorite);
                                            await _load();
                                          } on Object catch (error) {
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(SnackBar(
                                                      content: Text(
                                                          UiFailure.message(
                                                              error))));
                                            }
                                          } finally {
                                            if (mounted) {
                                              setState(() => _favoritesBusy
                                                  .remove(food.id));
                                            }
                                          }
                                        },
                                ),
                                onTap: () async {
                                  final added =
                                      await Navigator.of(context).push<bool>(
                                    MaterialPageRoute(
                                      builder: (_) => AddFoodScreen(
                                        mealType: widget.mealType,
                                        food: food,
                                      ),
                                    ),
                                  );
                                  if (added == true && context.mounted) {
                                    Navigator.pop(context, true);
                                  }
                                },
                              );
                            },
                          ),
          ],
        ),
      );
}
