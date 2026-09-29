import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(() => _load());
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _load({String? mode}) async {
    final nextMode = mode ?? _mode;
    setState(() {
      _mode = nextMode;
      _loading = true;
    });
    final foods = await ref
        .read(offlineMealRepositoryProvider)
        .searchFoods(_queryController.text.trim(), mode: nextMode);
    if (!mounted) return;
    setState(() {
      _foods = foods;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('选择食物')),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: TextField(
                controller: _queryController,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _load(mode: 'search'),
                decoration: InputDecoration(
                  hintText: '搜索米饭、鸡蛋、牛奶…',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    onPressed: () => _load(mode: 'search'),
                    icon: const Icon(Icons.arrow_forward),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('最近'),
                    selected: _mode == 'recent',
                    onSelected: (_) => _load(mode: 'recent'),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('收藏'),
                    selected: _mode == 'favorites',
                    onSelected: (_) => _load(mode: 'favorites'),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('常见'),
                    selected: _mode == 'common',
                    onSelected: (_) => _load(mode: 'common'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _foods.isEmpty
                      ? const Center(child: Text('没有找到食物，可尝试其他关键词'))
                      : ListView.separated(
                          itemCount: _foods.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
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
                                  color: food.isFavorite ? Colors.amber : null,
                                ),
                                onPressed: () async {
                                  await ref
                                      .read(offlineMealRepositoryProvider)
                                      .setFavorite(food, !food.isFavorite);
                                  await _load();
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
            ),
          ],
        ),
      );
}
