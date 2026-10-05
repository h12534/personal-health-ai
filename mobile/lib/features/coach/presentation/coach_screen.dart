import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_components.dart';
import '../../../core/widgets/chat_arrival.dart';
import 'hunger_entry_dialog.dart';
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
  final _inputFocus = FocusNode();
  final _arrival = ChatArrivalController();
  bool _sending = false;
  bool _acting = false;
  List<CoachBubble> _retained = const [];
  List<CoachBubble> _historyPrefix = const [];
  final Set<CoachBubble> _hiddenFailedAttempts = {};

  @override
  void dispose() {
    _controller.dispose();
    _inputFocus.dispose();
    _arrival.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(coachChatProvider);
    if (chat.valueOrNull case final incoming?) {
      final includesPrefix = incoming.length >= _historyPrefix.length &&
          List.generate(
                  _historyPrefix.length,
                  (i) =>
                      incoming[i].text == _historyPrefix[i].text &&
                      incoming[i].fromUser == _historyPrefix[i].fromUser)
              .every((same) => same);
      if (includesPrefix) _historyPrefix = const [];
      _retained = [..._historyPrefix, ...incoming]
          .where((message) => !_hiddenFailedAttempts.contains(message))
          .toList();
    }
    return LayoutBuilder(
        builder: (context, space) => Column(
              children: [
                Expanded(
                  child: NotificationListener<ScrollNotification>(
                      onNotification: _arrival.onScroll,
                      child: ListView.builder(
                        controller: _arrival.scroll,
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                        itemCount: _retained.length + 1,
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (space.maxHeight >= 400)
                                    RootPageHeader(
                                        title: 'AI 饮食教练',
                                        subtitle:
                                            '你的私人教练。目标和趋势由程序计算，AI 负责把建议说清楚。',
                                        action: Navigator.canPop(context)
                                            ? IconButton(
                                                tooltip: '返回',
                                                onPressed: () =>
                                                    Navigator.maybePop(context),
                                                icon: const Icon(
                                                    Icons.arrow_back_ios_new))
                                            : null),
                                  if (space.maxHeight < 400)
                                    Row(children: [
                                      const Expanded(
                                          child: Text('AI 饮食教练',
                                              style: AppTypography.cardTitle)),
                                      if (Navigator.canPop(context))
                                        IconButton(
                                            tooltip: '返回',
                                            onPressed: () =>
                                                Navigator.maybePop(context),
                                            icon: const Icon(
                                                Icons.arrow_back_ios_new))
                                    ]),
                                  _OverviewCard(
                                      onDecision: _decideAdjustment,
                                      busy: _acting || _sending),
                                  AppSection(
                                      title: '问你的教练',
                                      child: _QuickPrompts(
                                          onSend: _send,
                                          busy: _sending || _acting)),
                                  if (_retained.isEmpty &&
                                      !chat.isLoading &&
                                      !chat.hasError)
                                    EmptyState(
                                        title: '从一个问题开始',
                                        message: '可以聊下一餐、蛋白质或本周趋势。不需要重新解释已有背景。',
                                        actionLabel: '写下你的问题',
                                        onAction: _inputFocus.requestFocus),
                                ]);
                          }
                          return _MessageBubble(_retained[index - 1],
                              onAction: _handleAction,
                              busy: _acting || _sending);
                        },
                      )),
                ),
                ChatArrivalNotice(controller: _arrival),
                Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_sending || chat.isLoading)
                            Semantics(
                                liveRegion: true,
                                child: const Text('教练正在整理回复…')),
                          if (chat.hasError)
                            Semantics(
                                liveRegion: true,
                                child: Text(
                                    '${UiFailure.title(chat.error!)}。问题已保留，请重试。',
                                    style: AppTypography.secondary.copyWith(
                                        color: AppColors.of(context).danger))),
                        ])),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 10, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            focusNode: _inputFocus,
                            enabled: !_sending,
                            minLines: 1,
                            maxLines: ((space.maxHeight - 120) /
                                    (MediaQuery.textScalerOf(context)
                                            .scale(17) *
                                        1.5))
                                .floor()
                                .clamp(1, 4),
                            textInputAction: TextInputAction.send,
                            decoration: const InputDecoration(
                                labelText: '写下你的问题',
                                hintText: '问下一餐、食堂选择或本周趋势',
                                hintMaxLines: 1),
                            onSubmitted: (_) => _send(),
                          ),
                        ),
                        IconButton.filled(
                          tooltip: '发送',
                          style: IconButton.styleFrom(
                              foregroundColor:
                                  Theme.of(context).colorScheme.onPrimary),
                          onPressed: _sending || _acting ? null : _send,
                          icon: const Icon(Icons.send_outlined),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ));
  }

  Future<void> _send([String? prompt]) async {
    final message = (prompt ?? _controller.text).trim();
    if (_sending || _acting || message.isEmpty) return;
    if (prompt != null) _controller.text = prompt;
    // Display history only; conversation ID and request context stay owned by
    // the existing controller, whose AsyncError no longer contains old values.
    if (ref.read(coachChatProvider).hasError) {
      _historyPrefix = [..._retained];
      if (_historyPrefix.isNotEmpty &&
          _historyPrefix.last.fromUser &&
          _historyPrefix.last.text == message) {
        _hiddenFailedAttempts.add(_historyPrefix.last);
        _historyPrefix = _historyPrefix.sublist(0, _historyPrefix.length - 1);
      }
    }
    setState(() => _sending = true);
    _arrival.beginSend();
    try {
      await ref.read(coachChatProvider.notifier).send(message);
      if (mounted && !ref.read(coachChatProvider).hasError) {
        _controller.clear();
        _arrival.replyArrived();
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _decideAdjustment(DietAdjustmentModel value, bool accept) async {
    if (_acting || _sending) return;
    setState(() => _acting = true);
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
          SnackBar(content: Text('${UiFailure.title(error)}。请重新检查建议后重试。')),
        );
      }
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _handleAction(CoachActionModel action) async {
    if (_acting || _sending) return;
    setState(() => _acting = true);
    try {
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
              isScrollControlled: true,
              builder: (context) => SafeArea(
                child: ConstrainedBox(
                    constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(context).height * .85),
                    child: SingleChildScrollView(
                        child: Padding(
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
                    ))),
              ),
            );
          } on Object catch (error) {
            _showMessage('${UiFailure.title(error)}。请重试。');
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
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _showHungerDialog() async {
    final save = await showDialog<bool>(
      context: context,
      builder: (_) => HungerEntryDialog(
          onSave: (hunger, craving, mealContext, note) => ref
              .read(apiClientProvider)
              .logHunger(
                  hungerLevel: hunger,
                  cravingLevel: craving,
                  context: mealContext,
                  note: note)),
    );
    if (save == true) {
      _showMessage('已记录，这会帮助判断计划是否过于激进。');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class _OverviewCard extends ConsumerWidget {
  const _OverviewCard({required this.onDecision, required this.busy});

  final Future<void> Function(DietAdjustmentModel, bool) onDecision;
  final bool busy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(coachOverviewProvider);
    return overview.when(
      loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text('正在读取本周背景…')),
      error: (error, stack) => EmptyState(
          title: '周趋势数据暂不可用',
          message: '${UiFailure.message(error)} 仍可继续与教练聊天。',
          actionLabel: '重新读取趋势',
          onAction: () => ref.invalidate(coachOverviewProvider)),
      data: (data) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('本周趋势', style: AppTypography.sectionTitle),
          const SizedBox(height: 8),
          Text(data.headline, style: AppTypography.cardTitle),
          const SizedBox(height: 6),
          Text(data.trend.note),
          if (data.trend.average7d case final average?)
            MetricRow(
                label: '7 日平均体重',
                value: AppFormat.number(average, decimals: 1),
                unit: 'kg'),
          if (data.trend.change14d case final change?)
            MetricRow(
                label: '14 日体重变化',
                value: AppFormat.number(change, decimals: 1),
                unit: 'kg'),
          if (data.nextActions.isNotEmpty)
            Padding(
                padding: const EdgeInsets.only(top: 12),
                child: InsightBlock(
                    title: '下一步', message: data.nextActions.first)),
          if (data.observations.isNotEmpty || data.nextActions.length > 1)
            ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('已知背景与依据'),
                children: [
                  for (final line in [
                    ...data.observations,
                    ...data.nextActions.skip(1)
                  ])
                    Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Align(
                            alignment: Alignment.centerLeft, child: Text(line)))
                ]),
          if (data.adjustment case final adjustment?) ...[
            const Divider(height: 24),
            Text(
              '${adjustment.previousCalories} → ${adjustment.proposedCalories} kcal',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(adjustment.reason),
            const SizedBox(height: 10),
            if (adjustment.status == 'pending')
              Wrap(
                spacing: 8,
                children: [
                  FilledButton(
                    onPressed: busy ? null : () => onDecision(adjustment, true),
                    child: const Text('接受调整'),
                  ),
                  TextButton(
                    onPressed:
                        busy ? null : () => onDecision(adjustment, false),
                    child: const Text('保持当前目标'),
                  ),
                ],
              )
            else
              Text(switch (adjustment.status) {
                'accepted' => '已接受 · 新目标明天生效',
                'declined' || 'rejected' => '已保持当前目标',
                _ => '建议状态待确认'
              }),
            if (busy) const Text('请稍候再调整目标。'),
          ],
        ],
      ),
    );
  }
}

class _QuickPrompts extends StatelessWidget {
  const _QuickPrompts({required this.onSend, required this.busy});
  final Future<void> Function(String) onSend;
  final bool busy;

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final prompt in const [
              '今天吃什么？',
              '今天蛋白质够吗？',
              '我的减脂速度怎么样？',
              '食堂怎么选？',
            ])
              TextButton(
                onPressed: busy ? null : () => onSend(prompt),
                child: Text(prompt),
              ),
          ],
        ),
        TextButton.icon(
          icon: const Icon(Icons.storefront_outlined, size: 18),
          label: const Text('打开食堂'),
          onPressed: busy
              ? null
              : () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const CanteenScreen()),
                  ),
        ),
      ]);
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble(this.message,
      {required this.onAction, required this.busy});

  final CoachBubble message;
  final Future<void> Function(CoachActionModel) onAction;
  final bool busy;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message.fromUser ? '你' : '私人教练',
                style: AppTypography.caption
                    .copyWith(color: AppColors.of(context).secondaryText)),
            const SizedBox(height: 8),
            SelectableText(message.text, style: AppTypography.body),
            if (message.safetyNotice case final notice?) ...[
              const SizedBox(height: 8),
              Text(notice,
                  style: AppTypography.secondary
                      .copyWith(color: AppColors.of(context).attention)),
            ],
            if (!message.fromUser && message.actions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final action in message.actions)
                    if (action.type != 'none')
                      TextButton(
                        onPressed: busy ? null : () => onAction(action),
                        child: Text(action.label),
                      ),
                ],
              ),
            ],
          ],
        ),
      );
}
