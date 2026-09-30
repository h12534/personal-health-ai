import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/local_database.dart';
import '../data/offline_workout_repository.dart';
import '../data/training_models.dart';
import 'training_controller.dart';

class TrainingScreen extends ConsumerStatefulWidget {
  const TrainingScreen({super.key});

  @override
  ConsumerState<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends ConsumerState<TrainingScreen> {
  int _section = 0;

  static const _labels = ['今日', '计划', '历史', '动作库', '进度'];

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(trainingHomeProvider);
    return Column(
      key: const Key('training-home'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '训练',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              IconButton(
                tooltip: 'AI 私教',
                onPressed: () => _showCoach(context),
                icon: const Icon(Icons.auto_awesome),
              ),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: List.generate(
              _labels.length,
              (index) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: ChoiceChip(
                  label: Text(_labels[index]),
                  selected: _section == index,
                  onSelected: (_) => setState(() => _section = index),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: data.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(
              child: FilledButton.tonal(
                onPressed: () => ref.invalidate(trainingHomeProvider),
                child: const Text('训练数据加载失败 · 重试'),
              ),
            ),
            data: (value) => switch (_section) {
              0 => _TodayTraining(data: value),
              1 => _PlanView(data: value),
              2 => _HistoryView(data: value),
              3 => _ExerciseLibrary(data: value),
              _ => _ProgressView(data: value),
            },
          ),
        ),
      ],
    );
  }

  Future<void> _showCoach(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => const FractionallySizedBox(
          heightFactor: 0.88,
          child: _TrainingCoachSheet(),
        ),
      );
}

class _TodayTraining extends ConsumerStatefulWidget {
  const _TodayTraining({required this.data});

  final TrainingHomeData data;

  @override
  ConsumerState<_TodayTraining> createState() => _TodayTrainingState();
}

class _TodayTrainingState extends ConsumerState<_TodayTraining> {
  LocalWorkoutRecord? _session;
  final Map<String, List<LocalWorkoutSetRecord>> _sets = {};
  Timer? _timer;
  int _restRemaining = 0;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final day = widget.data.nextDay;
    if (day == null) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Icon(Icons.fitness_center, size: 56),
          const SizedBox(height: 16),
          Text(
            '先建立第一套训练计划',
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            '默认生成每周 3 次全身力量训练，优先器械、哑铃和低冲击活动。',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => TrainingPlanController(ref).generateDefault(),
            child: const Text('生成初学者计划'),
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
      children: [
        Card(
          color: Theme.of(context).colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(day.name,
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text('${day.focus} · 约 ${day.estimatedDurationMin} 分钟'),
                const SizedBox(height: 8),
                const Text('今天状态：按计划；工作组默认保留 2–3 次余力。'),
                const SizedBox(height: 14),
                if (_session == null)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const Key('start-workout'),
                      onPressed: () => _start(day.id),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('开始训练'),
                    ),
                  )
                else
                  const Row(
                    children: [
                      Icon(Icons.offline_bolt_outlined),
                      SizedBox(width: 8),
                      Text('训练中 · 已先保存到本机'),
                    ],
                  ),
              ],
            ),
          ),
        ),
        if (_restRemaining > 0)
          Card(
            key: const Key('rest-timer'),
            child: ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: Text('组间休息  $_restRemaining 秒'),
              subtitle: const Text('计时完全在本机运行'),
              trailing: IconButton(
                onPressed: () {
                  _timer?.cancel();
                  setState(() => _restRemaining = 0);
                },
                icon: const Icon(Icons.close),
              ),
            ),
          ),
        const SizedBox(height: 6),
        for (final exercise in day.exercises)
          _ExerciseSetCard(
            item: exercise,
            enabled: _session != null,
            previous: _latestSet(exercise.exercise.id),
            completed: _sets[exercise.exercise.id] ?? const [],
            onRecord: (weight, reps, rir) => _record(
              exercise,
              weight,
              reps,
              rir,
            ),
          ),
        if (_session != null) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 52,
            child: FilledButton.tonalIcon(
              onPressed: _finish,
              icon: const Icon(Icons.flag_outlined),
              label: const Text('完成训练并查看总结'),
            ),
          ),
        ],
      ],
    );
  }

  WorkoutSetModel? _latestSet(String exerciseId) {
    for (final workout in widget.data.workouts) {
      for (final item in workout.sets.reversed) {
        if (item.exerciseId == exerciseId && item.setType != 'warmup') {
          return item;
        }
      }
    }
    return null;
  }

  Future<void> _start(String trainingDayId) async {
    final session = await ref
        .read(offlineWorkoutRepositoryProvider)
        .start(trainingDayId: trainingDayId);
    if (!mounted) return;
    setState(() => _session = session);
    unawaited(ref.read(workoutSyncTriggerProvider)());
  }

  Future<void> _record(
    TrainingExerciseModel exercise,
    double weight,
    int reps,
    double rir,
  ) async {
    final session = _session;
    if (session == null) return;
    final existing = _sets[exercise.exercise.id] ?? const [];
    final item = await ref.read(offlineWorkoutRepositoryProvider).recordSet(
          sessionLocalId: session.localId,
          exerciseId: exercise.exercise.id,
          setNumber: existing.length + 1,
          weightKg: weight,
          reps: reps,
          rir: rir,
          restSeconds: exercise.restSeconds,
        );
    if (!mounted) return;
    setState(() {
      _sets[exercise.exercise.id] = [...existing, item];
      _restRemaining = exercise.restSeconds;
    });
    _startTimer();
    unawaited(ref.read(workoutSyncTriggerProvider)());
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _restRemaining <= 1) {
        timer.cancel();
        if (mounted) setState(() => _restRemaining = 0);
        return;
      }
      setState(() => _restRemaining -= 1);
    });
  }

  Future<void> _finish() async {
    final session = _session;
    if (session == null) return;
    _timer?.cancel();
    await ref.read(offlineWorkoutRepositoryProvider).complete(session.localId);
    unawaited(ref.read(workoutSyncTriggerProvider)());
    final sets = _sets.values.expand((value) => value).toList();
    final volume = sets.fold<double>(
      0,
      (total, item) => total + item.weightKg * item.reps,
    );
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
            Text('训练完成', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            Text('有效组  ${sets.length}'),
            Text('训练容量  ${volume.toStringAsFixed(0)} kg'),
            const SizedBox(height: 8),
            const Text('服务器同步完成后会检测最大重量、次数、e1RM 和单组容量 PR。'),
          ],
        ),
      ),
    );
    ref.invalidate(trainingHomeProvider);
    if (mounted) {
      setState(() {
        _session = null;
        _sets.clear();
        _restRemaining = 0;
      });
    }
  }
}

class _ExerciseSetCard extends StatefulWidget {
  const _ExerciseSetCard({
    required this.item,
    required this.enabled,
    required this.completed,
    required this.onRecord,
    this.previous,
  });

  final TrainingExerciseModel item;
  final bool enabled;
  final WorkoutSetModel? previous;
  final List<LocalWorkoutSetRecord> completed;
  final void Function(double weight, int reps, double rir) onRecord;

  @override
  State<_ExerciseSetCard> createState() => _ExerciseSetCardState();
}

class _ExerciseSetCardState extends State<_ExerciseSetCard> {
  late final TextEditingController _weight;
  late final TextEditingController _reps;
  late final TextEditingController _rir;

  @override
  void initState() {
    super.initState();
    _weight = TextEditingController(
      text: widget.item.targetWeightKg?.toStringAsFixed(1) ??
          widget.previous?.weightKg.toStringAsFixed(1) ??
          '0',
    );
    _reps = TextEditingController(text: '${widget.item.repMin}');
    _rir =
        TextEditingController(text: '${widget.item.targetRir?.round() ?? 2}');
  }

  @override
  void dispose() {
    _weight.dispose();
    _reps.dispose();
    _rir.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.item.exercise.name,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                widget.previous == null
                    ? '上次：暂无记录'
                    : '上次：${widget.previous!.weightKg.toStringAsFixed(1)} kg × '
                        '${widget.previous!.reps}，RIR ${widget.previous!.rir?.toStringAsFixed(0) ?? "--"}',
              ),
              Text(
                '今天：${widget.item.targetSets} × '
                '${widget.item.repMin}–${widget.item.repMax} · '
                '休息 ${widget.item.restSeconds} 秒',
              ),
              if (widget.item.targetWeightKg case final weight?)
                Text('已应用建议重量：${weight.toStringAsFixed(1)} kg'),
              if (widget.completed.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: widget.completed
                      .map(
                        (item) => Chip(
                          label: Text(
                            '${item.weightKg.toStringAsFixed(1)}×${item.reps} RIR${item.rir?.toStringAsFixed(0)}',
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _numberField(_weight, 'kg', decimal: true)),
                  const SizedBox(width: 8),
                  Expanded(child: _numberField(_reps, '次数')),
                  const SizedBox(width: 8),
                  Expanded(child: _numberField(_rir, 'RIR')),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  key: const Key('record-set'),
                  onPressed: widget.enabled
                      ? () {
                          final weight = double.tryParse(_weight.text);
                          final reps = int.tryParse(_reps.text);
                          final rir = double.tryParse(_rir.text);
                          if (weight != null &&
                              reps != null &&
                              reps > 0 &&
                              rir != null &&
                              rir >= 0 &&
                              rir <= 9) {
                            widget.onRecord(weight, reps, rir);
                          }
                        }
                      : null,
                  icon: const Icon(Icons.check),
                  label: Text(
                    widget.enabled ? '完成这一组' : '开始训练后记录',
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _numberField(
    TextEditingController controller,
    String label, {
    bool decimal = false,
  }) =>
      TextField(
        controller: controller,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        decoration: InputDecoration(labelText: label, isDense: true),
      );
}

class _PlanView extends ConsumerWidget {
  const _PlanView({required this.data});

  final TrainingHomeData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (data.plans.isEmpty) {
      return Center(
        child: FilledButton(
          onPressed: () => TrainingPlanController(ref).generateDefault(),
          child: const Text('生成每周 3 次全身计划'),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        for (final plan in data.plans)
          Card(
            child: ExpansionTile(
              initiallyExpanded: plan.active,
              title: Text(plan.name),
              subtitle: Text(
                '每周 ${plan.sessionsPerWeek} 次 · ${plan.difficulty}',
              ),
              children: [
                for (final day in plan.days)
                  ListTile(
                    title: Text(day.name),
                    subtitle: Text(
                      day.exercises
                          .map((value) => value.exercise.name)
                          .join(' · '),
                    ),
                    trailing: Text('${day.estimatedDurationMin} 分'),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _HistoryView extends StatelessWidget {
  const _HistoryView({required this.data});

  final TrainingHomeData data;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(20),
        children: data.workouts.isEmpty
            ? [const Center(child: Text('完成训练后，历史会显示在这里。'))]
            : data.workouts
                .map(
                  (workout) => Card(
                    child: ListTile(
                      leading: const Icon(Icons.history),
                      title: Text(
                        workout.status == 'completed' ? '已完成训练' : '训练进行中',
                      ),
                      subtitle: Text(
                        '${workout.startedAt.month}月${workout.startedAt.day}日 · '
                        '${workout.sets.where((item) => item.setType != "warmup").length} 个有效组',
                      ),
                      trailing: workout.durationMin == null
                          ? null
                          : Text('${workout.durationMin} 分'),
                    ),
                  ),
                )
                .toList(),
      );
}

class _ExerciseLibrary extends StatefulWidget {
  const _ExerciseLibrary({required this.data});

  final TrainingHomeData data;

  @override
  State<_ExerciseLibrary> createState() => _ExerciseLibraryState();
}

class _ExerciseLibraryState extends State<_ExerciseLibrary> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final values = widget.data.exercises
        .where(
          (item) =>
              _query.isEmpty ||
              item.name.toLowerCase().contains(_query.toLowerCase()) ||
              item.primaryMuscles.any((value) => value.contains(_query)),
        )
        .toList();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        SearchBar(
          hintText: '搜索动作或肌群',
          leading: const Icon(Icons.search),
          onChanged: (value) => setState(() => _query = value),
        ),
        const SizedBox(height: 12),
        for (final exercise in values)
          Card(
            child: ExpansionTile(
              title: Text(exercise.name),
              subtitle: Text(
                '${exercise.movementPattern} · ${exercise.equipment.join("/")}',
              ),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(exercise.instructions),
                const SizedBox(height: 6),
                Text('提示：${exercise.executionCues.join("；")}'),
                if (exercise.safetyNotes.isNotEmpty)
                  Text('安全：${exercise.safetyNotes.join("；")}'),
              ],
            ),
          ),
      ],
    );
  }
}

class _ProgressView extends StatelessWidget {
  const _ProgressView({required this.data});

  final TrainingHomeData data;

  @override
  Widget build(BuildContext context) {
    final exercises = {for (final item in data.exercises) item.id: item.name};
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('个人纪录', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        if (data.records.isEmpty)
          const Card(
            child: ListTile(
              leading: Icon(Icons.emoji_events_outlined),
              title: Text('还没有 PR'),
              subtitle: Text('完成有效工作组后自动检测，不把热身组计入容量。'),
            ),
          ),
        for (final record in data.records)
          Card(
            key: const Key('personal-record'),
            child: ListTile(
              leading: const Icon(Icons.emoji_events, color: Colors.amber),
              title: Text(exercises[record.exerciseId] ?? '训练动作'),
              subtitle: Text(_prLabel(record.type, record.confidence)),
              trailing: Text(record.value.toStringAsFixed(1)),
            ),
          ),
        const SizedBox(height: 12),
        const Text('最近 4 周趋势由服务端按重量、次数、e1RM 与训练容量分别计算。'),
      ],
    );
  }

  String _prLabel(String type, String confidence) => switch (type) {
        'max_weight' => '最大重量 PR',
        'max_reps' => '最大次数 PR',
        'estimated_1rm' => '估算 1RM PR · 置信度 $confidence',
        _ => '单组容量 PR',
      };
}

class _TrainingCoachSheet extends ConsumerStatefulWidget {
  const _TrainingCoachSheet();

  @override
  ConsumerState<_TrainingCoachSheet> createState() =>
      _TrainingCoachSheetState();
}

class _TrainingCoachSheetState extends ConsumerState<_TrainingCoachSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(trainingChatProvider);
    final values = state.valueOrNull ?? const <TrainingChatMessage>[];
    return Scaffold(
      appBar: AppBar(title: const Text('AI 私人训练教练')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.shield_outlined),
                    title: Text('重量和进阶由程序规则计算'),
                    subtitle: Text('AI 负责解释；任何调整都需要你点击确认。'),
                  ),
                ),
                for (final message in values)
                  Align(
                    alignment: message.fromUser
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Card(
                      color: message.fromUser
                          ? Theme.of(context).colorScheme.primaryContainer
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(message.text),
                            if (message.safetyNotice case final notice?)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  notice,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ),
                            for (final action in message.actions.where(
                              (value) => value['type'] == 'apply_progression',
                            ))
                              Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: FilledButton.tonalIcon(
                                  key: const Key(
                                    'apply-training-suggestion',
                                  ),
                                  onPressed: () async {
                                    try {
                                      await ref
                                          .read(
                                            trainingChatProvider.notifier,
                                          )
                                          .applySuggestion(action);
                                      ref.invalidate(trainingHomeProvider);
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            '建议已应用到当前训练计划',
                                          ),
                                        ),
                                      );
                                    } on Object {
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            '应用失败，请稍后重试',
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                  icon: const Icon(Icons.check_circle_outline),
                                  label: Text(
                                    action['label'] as String? ?? '应用建议',
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (state.isLoading) const LinearProgressIndicator(),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: const InputDecoration(
                        hintText: '例如：明天还练吗？',
                      ),
                    ),
                  ),
                  IconButton.filled(
                    onPressed: () {
                      final value = _controller.text;
                      _controller.clear();
                      ref.read(trainingChatProvider.notifier).send(value);
                    },
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
