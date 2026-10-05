import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/local_database.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_components.dart';
import '../../../core/widgets/app_trend_chart.dart';
import '../../../core/widgets/chat_arrival.dart';
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
          child: RootPageHeader(
              title: '训练',
              action: IconButton(
                tooltip: 'AI 私教',
                onPressed: () => _showCoach(context),
                icon: const Icon(Icons.chat_bubble_outline),
              )),
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
            loading: () => const LoadingState(label: '正在读取训练记录'),
            error: (error, _) => ErrorState(
                error: error,
                onRetry: () => ref.invalidate(trainingHomeProvider)),
            data: (value) => IndexedStack(index: _section, children: [
              TickerMode(
                  enabled: _section == 0, child: _TodayTraining(data: value)),
              _PlanView(data: value),
              _HistoryView(
                  data: value, onToday: () => setState(() => _section = 0)),
              _ExerciseLibrary(data: value),
              _ProgressView(data: value),
            ]),
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
  String? _restExercise;
  bool _operating = false;

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
          EmptyState(
              title: '先建立第一套训练计划',
              message: '每周 3 次全身力量训练，优先器械、哑铃和低冲击活动。',
              actionLabel: _operating ? '正在生成…' : '生成初学者计划',
              onAction: _operating ? null : _generate),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(day.name, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text('${day.focus} · 约 ${day.estimatedDurationMin} 分钟'),
              const SizedBox(height: 8),
              const Text('按下方计划逐组记录。建议重量和余力以各动作目标为准。'),
              const SizedBox(height: 14),
              if (_session == null)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const Key('start-workout'),
                    onPressed: _operating ? null : () => _start(day.id),
                    icon: const Icon(Icons.play_arrow),
                    label: Text(_operating ? '正在保存…' : '开始训练'),
                  ),
                )
              else
                const Text('训练中 · 已先保存到本机'),
            ],
          ),
        ),
        if (_restRemaining > 0)
          InsightBlock(
            key: const Key('rest-timer'),
            title: '组间休息 · ${_restExercise ?? "当前动作"}',
            message:
                '${(_restRemaining ~/ 60).toString().padLeft(2, "0")}:${(_restRemaining % 60).toString().padLeft(2, "0")} · 前台本机计时',
            action: TextButton(
              onPressed: () {
                _timer?.cancel();
                setState(() => _restRemaining = 0);
              },
              child: const Text('结束休息'),
            ),
          ),
        const SizedBox(height: 6),
        for (final exercise in day.exercises)
          WorkoutSetEditor(
            key: ValueKey(exercise.id),
            item: exercise,
            enabled: _session != null && !_operating,
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
          FilledButton.tonalIcon(
            onPressed: _operating ? null : _finish,
            icon: const Icon(Icons.flag_outlined),
            label: Text(_operating ? '正在保存…' : '完成训练并查看总结'),
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
    if (_operating) return;
    setState(() => _operating = true);
    try {
      final session = await ref
          .read(offlineWorkoutRepositoryProvider)
          .start(trainingDayId: trainingDayId);
      if (!mounted) return;
      setState(() => _session = session);
      unawaited(ref.read(workoutSyncTriggerProvider)());
    } on Object catch (error) {
      _showFailure(error);
    } finally {
      if (mounted) setState(() => _operating = false);
    }
  }

  Future<void> _generate() async {
    if (_operating) return;
    setState(() => _operating = true);
    try {
      await TrainingPlanController(ref).generateDefault();
    } on Object catch (error) {
      _showFailure(error);
    } finally {
      if (mounted) setState(() => _operating = false);
    }
  }

  void _showFailure(Object error) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${UiFailure.title(error)}。请检查记录后重试。')));
    }
  }

  Future<void> _record(
    TrainingExerciseModel exercise,
    double weight,
    int reps,
    double rir,
  ) async {
    final session = _session;
    if (session == null || _operating) {
      throw StateError('operation unavailable');
    }
    setState(() => _operating = true);
    try {
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
        _restExercise = exercise.exercise.name;
      });
      _startTimer();
      unawaited(ref.read(workoutSyncTriggerProvider)());
    } finally {
      if (mounted) setState(() => _operating = false);
    }
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
    if (session == null || _operating) return;
    setState(() => _operating = true);
    try {
      await ref
          .read(offlineWorkoutRepositoryProvider)
          .complete(session.localId);
      _timer?.cancel();
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
        useSafeArea: true,
        isScrollControlled: true,
        builder: (context) => SingleChildScrollView(
            child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('训练完成', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 12),
              Text('有效组  ${sets.length}'),
              Text('训练容量  ${AppFormat.number(volume, grouped: true)} kg × 次'),
              const SizedBox(height: 8),
              const Text('服务器同步完成后会检测最大重量、次数、e1RM 和单组容量 PR。'),
            ],
          ),
        )),
      );
      ref.invalidate(trainingHomeProvider);
      if (mounted) {
        setState(() {
          _session = null;
          _sets.clear();
          _restRemaining = 0;
        });
      }
    } on Object catch (error) {
      _showFailure(error);
    } finally {
      if (mounted) setState(() => _operating = false);
    }
  }
}

class WorkoutSetEditor extends StatefulWidget {
  const WorkoutSetEditor({
    super.key,
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
  final Future<void> Function(double weight, int reps, double rir) onRecord;

  @override
  State<WorkoutSetEditor> createState() => _WorkoutSetEditorState();
}

class _WorkoutSetEditorState extends State<WorkoutSetEditor> {
  final _form = GlobalKey<FormState>();
  bool _saving = false;
  Object? _error;
  late final TextEditingController _weight;
  late final TextEditingController _reps;
  late final TextEditingController _rir;

  @override
  void initState() {
    super.initState();
    _weight = TextEditingController(
      text: AppFormat.editableNumber(
          widget.item.targetWeightKg ?? widget.previous?.weightKg ?? 0),
    );
    _reps = TextEditingController(text: '${widget.item.repMin}');
    _rir = TextEditingController(
        text: AppFormat.editableNumber(widget.item.targetRir ?? 2));
  }

  @override
  void dispose() {
    _weight.dispose();
    _reps.dispose();
    _rir.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.item.exercise.name,
                  style: AppTypography.sectionTitle,
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
                if (widget.item.targetRir case final target?)
                  Text('目标余力 ${AppFormat.number(target, decimals: 1)} 次'),
                if (widget.completed.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    children: widget.completed
                        .map(
                          (item) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                '${item.weightKg.toStringAsFixed(1)}×${item.reps} RIR${item.rir?.toStringAsFixed(0)}',
                              )),
                        )
                        .toList(),
                  ),
                ],
                const SizedBox(height: 10),
                LayoutBuilder(builder: (context, box) {
                  final fields = [
                    _numberField(_weight, '重量 kg', max: 1000, decimal: true),
                    _numberField(_reps, '次数', min: 1, max: 500),
                    _numberField(_rir, '余力 RIR', max: 9, decimal: true),
                  ];
                  if (MediaQuery.textScalerOf(context).scale(17) > 25 ||
                      box.maxWidth < 280) {
                    return Column(children: [
                      for (final field in fields)
                        Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: field)
                    ]);
                  }
                  return Row(children: [
                    for (var i = 0; i < fields.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(flex: i == 0 ? 14 : 10, child: fields[i]),
                    ]
                  ]);
                }),
                Text('RIR 是这一组结束后，估计还能完成的次数。',
                    style: AppTypography.caption
                        .copyWith(color: AppColors.of(context).secondaryText)),
                if (_error != null)
                  Semantics(
                      liveRegion: true,
                      child: Text('${UiFailure.title(_error!)}。输入已保留，请重试。',
                          style: AppTypography.secondary
                              .copyWith(color: AppColors.of(context).danger))),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const Key('record-set'),
                    onPressed: widget.enabled && !_saving ? _save : null,
                    icon: const Icon(Icons.check),
                    label: Text(
                      _saving
                          ? '正在保存这一组…'
                          : _error != null
                              ? '重试保存这一组'
                              : widget.enabled || widget.completed.isNotEmpty
                                  ? '完成这一组'
                                  : '开始训练后记录',
                    ),
                  ),
                ),
              ],
            )),
      );

  Widget _numberField(
    TextEditingController controller,
    String label, {
    bool decimal = false,
    double min = 0,
    required double max,
  }) =>
      TextFormField(
        controller: controller,
        enabled: widget.enabled && !_saving,
        style: AppTypography.metric.copyWith(fontSize: 26),
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        decoration: InputDecoration(labelText: label),
        validator: (text) {
          final value = double.tryParse(text?.trim() ?? '');
          if (value == null ||
              !value.isFinite ||
              value < min ||
              value > max ||
              (!decimal && int.tryParse(text?.trim() ?? '') == null)) {
            return '请输入 ${min.toInt()}–${max.toInt()} 的${decimal ? "数值" : "整数"}';
          }
          return null;
        },
      );

  Future<void> _save() async {
    if (_saving || !widget.enabled || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onRecord(double.parse(_weight.text.trim()),
          int.parse(_reps.text.trim()), double.parse(_rir.text.trim()));
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

String _trainingTerm(String value) =>
    const {
      'beginner': '入门',
      'novice': '初级',
      'intermediate': '中级',
      'advanced': '进阶',
      'squat': '蹲类',
      'hinge': '髋铰链',
      'isolation': '单关节',
      'horizontal_push': '水平推',
      'vertical_push': '垂直推',
      'horizontal_pull': '水平拉',
      'vertical_pull': '垂直拉',
      'core': '核心',
      'carry': '负重行走',
      'cardio': '有氧',
      'barbell': '杠铃',
      'dumbbell': '哑铃',
      'bodyweight': '徒手',
      'machine': '器械',
      'smith_machine': '史密斯机',
      'cable': '绳索',
      'resistance_band': '弹力带',
      'cardio_machine': '有氧器械',
      'other': '其他',
    }[value] ??
    value;

class _PlanView extends ConsumerWidget {
  const _PlanView({required this.data});

  final TrainingHomeData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (data.plans.isEmpty) {
      return Center(
        child: AsyncActionButton(
          onPressed: () => TrainingPlanController(ref).generateDefault(),
          label: '生成每周 3 次全身计划',
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        for (final plan in data.plans)
          ExpansionTile(
            initiallyExpanded: plan.active,
            title: Text(plan.name),
            subtitle: Text(
              '每周 ${plan.sessionsPerWeek} 次 · ${_trainingTerm(plan.difficulty)}',
            ),
            children: [
              for (final day in plan.days)
                ListTile(
                  title: Text(day.name),
                  subtitle: Text(
                    '${day.estimatedDurationMin} 分钟 · ${day.exercises.map((value) => value.exercise.name).join(' · ')}',
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _HistoryView extends StatelessWidget {
  const _HistoryView({required this.data, required this.onToday});

  final TrainingHomeData data;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    if (data.workouts.isEmpty) {
      return ListView(padding: AppSpacing.pageInsets, children: [
        EmptyState(
            title: '训练历史还未开始',
            message: '完成并同步训练后，可以在这里回看。',
            actionLabel: '回到今日训练',
            onAction: onToday)
      ]);
    }
    return ListView.builder(
        padding: AppSpacing.pageInsets,
        itemCount: data.workouts.length,
        itemBuilder: (context, index) {
          final workout = data.workouts[index];
          return ListRow(
              title: switch (workout.status) {
                'completed' => '已完成训练',
                'in_progress' => '训练进行中',
                _ => '训练状态待确认'
              },
              subtitle:
                  '${workout.startedAt.year}年${AppFormat.date(workout.startedAt)} · ${workout.sets.where((item) => item.setType != "warmup").length} 个有效组${workout.durationMin == null ? "" : " · ${workout.durationMin} 分钟"}',
              icon: Icons.history_outlined);
        });
  }
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
          ExpansionTile(
            title: Text(exercise.name),
            subtitle: Text(
              '${_trainingTerm(exercise.movementPattern)} · ${exercise.equipment.map(_trainingTerm).join(" / ")}',
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
    final completed =
        data.workouts.where((w) => w.status == 'completed').toList();
    final weeks = <DateTime, int>{};
    for (final workout in completed) {
      final d = workout.startedAt;
      final monday = DateTime(d.year, d.month, d.day)
          .subtract(Duration(days: d.weekday - 1));
      weeks[monday] = (weeks[monday] ?? 0) + 1;
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('个人纪录', style: AppTypography.sectionTitle),
        const SizedBox(height: 8),
        if (data.records.isEmpty)
          const EmptyState(
              title: '还没有个人纪录', message: '完成并同步工作组后，服务器会检测个人纪录。热身组不计入。'),
        for (final record in data.records)
          Padding(
            key: const Key('personal-record'),
            padding: const EdgeInsets.symmetric(vertical: 12),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              MetricRow(
                  label: exercises[record.exerciseId] ?? '训练动作',
                  value: AppFormat.number(record.value,
                      decimals: record.type == 'max_reps' ? 0 : 1),
                  unit: switch (record.type) {
                    'max_weight' || 'estimated_1rm' => 'kg',
                    'max_reps' => '次',
                    'volume' || 'max_volume' => 'kg × 次',
                    _ => '（单位待确认）'
                  },
                  detail:
                      '${record.achievedAt.year}年${AppFormat.date(record.achievedAt)}'),
              Text(_prLabel(record.type, record.confidence),
                  style: AppTypography.caption),
            ]),
          ),
        const SizedBox(height: 12),
        const Text('下方仅展示已加载的历史，不代表完整训练档案。', style: AppTypography.caption),
        AppSection(
            title: '训练频率',
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (weeks.isEmpty) const Text('暂无已完成并同步的训练'),
              for (final week
                  in weeks.entries.toList()
                    ..sort((a, b) => b.key.compareTo(a.key)))
                MetricRow(
                    label: '${AppFormat.date(week.key)}这一周',
                    value: '${week.value}',
                    unit: '次'),
            ])),
        for (final exercise in data.exercises.where((e) => completed.any((w) =>
            w.sets.any((s) => s.exerciseId == e.id && s.setType != 'warmup'))))
          AppSection(
              title: '${exercise.name} · 单次最高工作组重量',
              child: AppTrendChart(unit: 'kg', points: [
                for (final workout in completed)
                  if (workout.sets.any((s) =>
                      s.exerciseId == exercise.id && s.setType != 'warmup'))
                    AppTrendPoint(
                        workout.startedAt,
                        workout.sets
                            .where((s) =>
                                s.exerciseId == exercise.id &&
                                s.setType != 'warmup')
                            .map((s) => s.weightKg)
                            .reduce((a, b) => a > b ? a : b)),
              ])),
      ],
    );
  }

  String _prLabel(String type, String confidence) => switch (type) {
        'max_weight' => '最大重量 PR',
        'max_reps' => '最大次数 PR',
        'estimated_1rm' => '估算 1RM PR · 置信度 $confidence',
        'volume' || 'max_volume' => '单组容量 PR',
        _ => '纪录类型待确认',
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
  final _arrival = ChatArrivalController();
  bool _sending = false;
  List<TrainingChatMessage> _retained = const [];

  @override
  void dispose() {
    _controller.dispose();
    _arrival.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(trainingChatProvider);
    if (state.valueOrNull != null) _retained = state.valueOrNull!;
    final values = _retained;
    return Scaffold(
      appBar: DetailPageHeader(label: 'AI 私人训练教练'),
      body: LayoutBuilder(
          builder: (context, space) => Column(
                children: [
                  Expanded(
                    child: NotificationListener<ScrollNotification>(
                        onNotification: _arrival.onScroll,
                        child: ListView(
                          key: const Key('training-chat-history'),
                          controller: _arrival.scroll,
                          padding: const EdgeInsets.all(16),
                          children: [
                            const InsightBlock(
                                title: '重量和进阶由程序规则计算',
                                message: 'AI 负责解释；任何调整都需要你点击确认。'),
                            for (final message in values)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(message.fromUser ? '你' : '私人教练',
                                        style: AppTypography.caption),
                                    const SizedBox(height: 8),
                                    Text(message.text),
                                    if (message.safetyNotice case final notice?)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: Text(
                                          notice,
                                          style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .error,
                                          ),
                                        ),
                                      ),
                                    for (final action in message.actions.where(
                                      (value) =>
                                          value['type'] == 'apply_progression',
                                    ))
                                      Padding(
                                        padding: const EdgeInsets.only(top: 10),
                                        child: FilledButton.tonalIcon(
                                          key: const Key(
                                            'apply-training-suggestion',
                                          ),
                                          onPressed: _sending
                                              ? null
                                              : () async {
                                                  setState(
                                                      () => _sending = true);
                                                  try {
                                                    await ref
                                                        .read(
                                                          trainingChatProvider
                                                              .notifier,
                                                        )
                                                        .applySuggestion(
                                                            action);
                                                    ref.invalidate(
                                                        trainingHomeProvider);
                                                    if (!context.mounted) {
                                                      return;
                                                    }
                                                    ScaffoldMessenger.of(
                                                            context)
                                                        .showSnackBar(
                                                      const SnackBar(
                                                        content: Text(
                                                          '建议已应用到当前训练计划',
                                                        ),
                                                      ),
                                                    );
                                                  } on Object {
                                                    if (!context.mounted) {
                                                      return;
                                                    }
                                                    ScaffoldMessenger.of(
                                                            context)
                                                        .showSnackBar(
                                                      const SnackBar(
                                                        content: Text(
                                                          '应用失败，请稍后重试',
                                                        ),
                                                      ),
                                                    );
                                                  } finally {
                                                    if (mounted) {
                                                      setState(() =>
                                                          _sending = false);
                                                    }
                                                  }
                                                },
                                          icon: const Icon(
                                              Icons.check_circle_outline),
                                          label: Text(
                                            action['label'] as String? ??
                                                '应用建议',
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            if (_sending || state.isLoading)
                              const Text('教练正在整理回复…'),
                            if (state.hasError)
                              Text(
                                  '${UiFailure.title(state.error!)}。问题已保留，请重试。'),
                          ],
                        )),
                  ),
                  ChatArrivalNotice(controller: _arrival),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              enabled: !_sending,
                              minLines: 1,
                              maxLines: ((space.maxHeight - 140) /
                                      (MediaQuery.textScalerOf(context)
                                              .scale(17) *
                                          1.5))
                                  .floor()
                                  .clamp(1, 4),
                              decoration: InputDecoration(
                                isDense: space.maxHeight < 250,
                                hintMaxLines: 1,
                                labelText: '问私人教练',
                                hintText: '例如：明天还练吗？',
                              ),
                            ),
                          ),
                          IconButton.filled(
                            tooltip: '发送问题',
                            style: IconButton.styleFrom(
                                foregroundColor:
                                    Theme.of(context).colorScheme.onPrimary),
                            onPressed: _sending ? null : _send,
                            icon: const Icon(Icons.send),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              )),
    );
  }

  Future<void> _send() async {
    final value = _controller.text.trim();
    if (_sending || value.isEmpty) return;
    setState(() => _sending = true);
    _arrival.beginSend();
    try {
      await ref.read(trainingChatProvider.notifier).send(value);
      if (mounted && !ref.read(trainingChatProvider).hasError) {
        _controller.clear();
        _arrival.replyArrived();
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}
