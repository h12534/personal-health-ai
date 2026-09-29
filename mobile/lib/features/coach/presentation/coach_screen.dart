import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../data/coach_models.dart';
import 'canteen_screen.dart';
import 'coach_controller.dart';

class CoachScreen extends ConsumerStatefulWidget {
  const CoachScreen({super.key});

  @override
  ConsumerState<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends ConsumerState<CoachScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(coachChatProvider);
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            children: [
              Text('AI 饮食教练',
                  style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 4),
              const Text('目标和趋势由程序计算，AI 负责把建议说清楚。'),
              const SizedBox(height: 14),
              _OverviewCard(onDecision: _decideAdjustment),
              const SizedBox(height: 14),
              const _QuickPrompts(),
              const SizedBox(height: 14),
              ...switch (chat) {
                AsyncData(:final value) => value.map(
                    (message) => _MessageBubble(
                      message,
                      onAction: _handleAction,
                    ),
                  ),
                AsyncError(:final error) => [
                    Text('发送失败：$error'),
                    const SizedBox(height: 8),
                  ],
                _ => [const LinearProgressIndicator()],
              },
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 10, 10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    textInputAction: TextInputAction.send,
                    decoration:
                        const InputDecoration(hintText: '问下一餐、食堂选择或本周趋势'),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                IconButton.filled(
                  tooltip: '发送',
                  onPressed: _send,
                  icon: const Icon(Icons.send_outlined),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _send([String? prompt]) {
    final message = prompt ?? _controller.text;
    _controller.clear();
    ref.read(coachChatProvider.notifier).send(message);
  }

  Future<void> _decideAdjustment(DietAdjustmentModel value, bool accept) async {
    try {
      await AdjustmentController(ref).decide(value.id, accept);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(accept ? '新目标将在明天生效' : '已保留当前目标')),
        );
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    }
  }

  Future<void> _handleAction(CoachActionModel action) async {
    switch (action.type) {
      case 'open_canteen':
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CanteenScreen()),
        );
        return;
      case 'open_next_meal':
        try {
          final plan = await ref.read(apiClientProvider).fetchNextMeal();
          if (!mounted) return;
          await showModalBottomSheet<void>(
            context: context,
            showDragHandle: true,
            builder: (context) => Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${plan.mealLabel}建议',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${plan.target.caloriesMin}–${plan.target.caloriesMax} kcal · '
                    '蛋白质至少 ${plan.target.proteinMin.toStringAsFixed(0)} g',
                  ),
                  const SizedBox(height: 8),
                  for (final line in plan.strategy)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('• $line'),
                    ),
                ],
              ),
            ),
          );
        } on Object catch (error) {
          _showMessage(error.toString());
        }
        return;
      case 'log_hunger':
        await _showHungerDialog();
        return;
      case 'review_adjustment':
        ref.invalidate(coachOverviewProvider);
        _showMessage('已刷新本周趋势与调整建议。');
        return;
      case 'log_weight':
        _showMessage('请回到首页的体重卡片记录晨重。');
        return;
      case 'none':
        return;
      default:
        _showMessage('该操作暂不可用。');
        return;
    }
  }

  Future<void> _showHungerDialog() async {
    var hunger = 3.0;
    var craving = 2.0;
    var mealContext = 'before_dinner';
    final note = TextEditingController();
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('记录饥饿感'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('饥饿程度：${hunger.round()} / 5'),
                Slider(
                  value: hunger,
                  min: 1,
                  max: 5,
                  divisions: 4,
                  onChanged: (value) => setState(() => hunger = value),
                ),
                Text('想吃特定食物：${craving.round()} / 5'),
                Slider(
                  value: craving,
                  min: 1,
                  max: 5,
                  divisions: 4,
                  onChanged: (value) => setState(() => craving = value),
                ),
                DropdownButtonFormField<String>(
                  initialValue: mealContext,
                  decoration: const InputDecoration(labelText: '时间'),
                  items: const [
                    DropdownMenuItem(
                      value: 'before_breakfast',
                      child: Text('早餐前'),
                    ),
                    DropdownMenuItem(
                      value: 'before_lunch',
                      child: Text('午餐前'),
                    ),
                    DropdownMenuItem(
                      value: 'before_dinner',
                      child: Text('晚餐前'),
                    ),
                    DropdownMenuItem(
                      value: 'before_bed',
                      child: Text('睡前'),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => mealContext = value ?? mealContext),
                ),
                TextField(
                  controller: note,
                  decoration: const InputDecoration(
                    labelText: '备注（压力、食堂选择、训练后等）',
                  ),
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
              onPressed: () => Navigator.pop(context, true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (save == true) {
      try {
        await ref.read(apiClientProvider).logHunger(
              hungerLevel: hunger.round(),
              cravingLevel: craving.round(),
              context: mealContext,
              note: note.text.trim().isEmpty ? null : note.text.trim(),
            );
        _showMessage('已记录，这会帮助判断计划是否过于激进。');
      } on Object catch (error) {
        _showMessage(error.toString());
      }
    }
    note.dispose();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class _OverviewCard extends ConsumerWidget {
  const _OverviewCard({required this.onDecision});

  final Future<void> Function(DietAdjustmentModel, bool) onDecision;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(coachOverviewProvider);
    return overview.when(
      loading: () => const Card(child: LinearProgressIndicator()),
      error: (error, stack) => Card(
        child: ListTile(
          leading: const Icon(Icons.insights_outlined),
          title: const Text('周趋势数据暂不可用'),
          subtitle: const Text('仍可继续与教练聊天。'),
          trailing: IconButton(
            onPressed: () => ref.invalidate(coachOverviewProvider),
            icon: const Icon(Icons.refresh),
          ),
        ),
      ),
      data: (data) => Card(
        color: Theme.of(context).colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.insights_outlined),
                  const SizedBox(width: 8),
                  Text('本周趋势', style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
              const SizedBox(height: 8),
              Text(data.headline),
              const SizedBox(height: 6),
              Text(data.trend.note),
              if (data.adjustment case final adjustment?) ...[
                const Divider(height: 24),
                Text(
                  '${adjustment.previousCalories} → ${adjustment.proposedCalories} kcal',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(adjustment.reason),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton(
                      onPressed: () => onDecision(adjustment, true),
                      child: const Text('接受调整'),
                    ),
                    TextButton(
                      onPressed: () => onDecision(adjustment, false),
                      child: const Text('保持当前目标'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickPrompts extends ConsumerWidget {
  const _QuickPrompts();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final prompt in const [
            '今天吃什么？',
            '晚餐怎么吃？',
            '今天蛋白质够吗？',
            '我的减脂速度怎么样？',
            '食堂怎么选？',
          ])
            ActionChip(
              label: Text(prompt),
              onPressed: () =>
                  ref.read(coachChatProvider.notifier).send(prompt),
            ),
          ActionChip(
            avatar: const Icon(Icons.storefront_outlined, size: 18),
            label: const Text('打开食堂'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CanteenScreen()),
            ),
          ),
        ],
      );
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble(this.message, {required this.onAction});

  final CoachBubble message;
  final Future<void> Function(CoachActionModel) onAction;

  @override
  Widget build(BuildContext context) => Align(
        alignment:
            message.fromUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: message.fromUser
                ? Theme.of(context).colorScheme.primaryContainer
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message.text),
              if (message.safetyNotice case final notice?) ...[
                const SizedBox(height: 8),
                Text(notice, style: Theme.of(context).textTheme.bodySmall),
              ],
              if (!message.fromUser && message.actions.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final action in message.actions)
                      if (action.type != 'none')
                        ActionChip(
                          label: Text(action.label),
                          onPressed: () => onAction(action),
                        ),
                  ],
                ),
              ],
            ],
          ),
        ),
      );
}
