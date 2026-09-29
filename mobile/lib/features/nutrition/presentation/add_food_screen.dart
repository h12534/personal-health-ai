import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/nutrition_models.dart';
import 'nutrition_controller.dart';

class AddFoodScreen extends ConsumerStatefulWidget {
  const AddFoodScreen({super.key, required this.mealType, required this.food});

  final String mealType;
  final FoodModel food;

  @override
  ConsumerState<AddFoodScreen> createState() => _AddFoodScreenState();
}

class _AddFoodScreenState extends ConsumerState<AddFoodScreen> {
  late final TextEditingController _amountController;
  late String _unit;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _unit = 'g';
    _amountController = TextEditingController(text: '100');
    _amountController.addListener(_redraw);
  }

  @override
  void dispose() {
    _amountController
      ..removeListener(_redraw)
      ..dispose();
    super.dispose();
  }

  void _redraw() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final amount = double.tryParse(_amountController.text.trim()) ?? 0;
    final units = <String>{
      'g',
      if (widget.food.servingUnit != null) widget.food.servingUnit!,
    };
    NutritionTotals? preview;
    if (amount > 0) preview = widget.food.calculate(amount, _unit);
    return Scaffold(
      appBar: AppBar(title: Text(widget.food.name)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('记录份量', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text(widget.food.servingDescription ?? '营养基准：每 100g'),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: '数量'),
                ),
              ),
              const SizedBox(width: 12),
              DropdownButton<String>(
                value: _unit,
                items: units
                    .map(
                      (unit) => DropdownMenuItem(
                        value: unit,
                        child: Text(_unitLabel(unit)),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _unit = value;
                    _amountController.text = value == 'g' ? '100' : '1';
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: preview == null
                  ? const Text('请输入大于 0 的份量')
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '预计营养',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        Text('${preview.calories.toStringAsFixed(0)} kcal'),
                        Text('蛋白质 ${preview.protein.toStringAsFixed(1)} g'),
                        Text(
                          '碳水 ${preview.carbs.toStringAsFixed(1)} g · '
                          '脂肪 ${preview.fat.toStringAsFixed(1)} g',
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: preview == null || _saving ? null : () => _save(amount),
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: Text(_saving ? '保存中' : '加入${_mealLabel(widget.mealType)}'),
          ),
        ],
      ),
    );
  }

  Future<void> _save(double amount) async {
    setState(() => _saving = true);
    try {
      await ref.read(nutritionControllerProvider.notifier).addFood(
            mealType: widget.mealType,
            food: widget.food,
            amount: amount,
            unit: _unit,
          );
      if (mounted) Navigator.pop(context, true);
    } on Object catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  static String _unitLabel(String unit) =>
      const {
        'g': '克',
        'ml': '毫升',
        'piece': '个',
        'bowl': '碗',
        'cup': '杯',
        'serving': '份',
        'custom': '份',
      }[unit] ??
      unit;

  static String _mealLabel(String type) =>
      const {
        'breakfast': '早餐',
        'lunch': '午餐',
        'dinner': '晚餐',
        'snack': '加餐',
      }[type] ??
      '餐次';
}
