import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_components.dart';

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
  Object? _error;

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
    if (amount.isFinite && amount > 0) {
      preview = widget.food.calculate(amount, _unit);
    }
    return PopScope(
        canPop: !_saving,
        child: Scaffold(
          appBar: DetailPageHeader(label: widget.food.name),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text('记录份量', style: AppTypography.sectionTitle),
              const SizedBox(height: 6),
              Text(widget.food.servingDescription ?? '营养基准：每 100g'),
              const SizedBox(height: 20),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _amountController,
                    enabled: !_saving,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: '数量'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _unit,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '单位'),
                    items: units
                        .map(
                          (unit) => DropdownMenuItem(
                            value: unit,
                            child: Text(_unitLabel(unit)),
                          ),
                        )
                        .toList(),
                    onChanged: _saving
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() {
                              _unit = value;
                              _amountController.text =
                                  value == 'g' ? '100' : '1';
                            });
                          },
                  ),
                ],
              ),
              const SizedBox(height: 20),
              preview == null
                  ? const Text('请输入大于 0 的份量')
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        MetricHero(
                            label: '预计热量',
                            value: AppFormat.number(preview.calories),
                            unit: 'kcal'),
                        MetricRow(
                            label: '蛋白质',
                            value:
                                AppFormat.number(preview.protein, decimals: 1),
                            unit: 'g'),
                        MetricRow(
                            label: '碳水',
                            value: AppFormat.number(preview.carbs, decimals: 1),
                            unit: 'g'),
                        MetricRow(
                            label: '脂肪',
                            value: AppFormat.number(preview.fat, decimals: 1),
                            unit: 'g'),
                      ],
                    ),
              if (_error != null)
                Semantics(
                    liveRegion: true,
                    child: Text('${UiFailure.title(_error!)}。份量已保留，请检查记录后重试。',
                        style: AppTypography.secondary
                            .copyWith(color: AppColors.of(context).danger))),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed:
                    preview == null || _saving ? null : () => _save(amount),
                icon: const Icon(Icons.check),
                label:
                    Text(_saving ? '保存中' : '加入${_mealLabel(widget.mealType)}'),
              ),
            ],
          ),
        ));
  }

  Future<void> _save(double amount) async {
    if (_saving || !amount.isFinite || amount <= 0) return;
    setState(() {
      _saving = true;
      _error = null;
    });
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
        setState(() {
          _saving = false;
          _error = error;
        });
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
