import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:personal_health_os/core/database/local_database.dart';
import 'package:personal_health_os/core/theme/app_theme.dart';
import 'package:personal_health_os/core/widgets/app_components.dart';
import 'package:personal_health_os/features/coach/data/coach_models.dart';
import 'package:personal_health_os/features/coach/presentation/coach_controller.dart';
import 'package:personal_health_os/features/coach/presentation/coach_screen.dart';
import 'package:personal_health_os/features/health/presentation/health_controller.dart';
import 'package:personal_health_os/features/health/presentation/health_screen.dart';
import 'package:personal_health_os/features/nutrition/data/meal_photo_service.dart';
import 'package:personal_health_os/features/nutrition/data/nutrition_models.dart';
import 'package:personal_health_os/features/nutrition/data/sync_service.dart';
import 'package:personal_health_os/features/nutrition/presentation/nutrition_controller.dart';
import 'package:personal_health_os/features/nutrition/presentation/nutrition_screen.dart';
import 'package:personal_health_os/features/training/data/training_models.dart';
import 'package:personal_health_os/features/training/data/offline_workout_repository.dart';
import 'package:drift/native.dart';
import 'package:personal_health_os/features/training/presentation/training_controller.dart';
import 'package:personal_health_os/features/training/presentation/training_screen.dart';
import 'ui_redesign_golden_test.dart' show sampleReport, sampleTrend;
import 'ui_rollout_coach_test.dart' show rolloutCoachOverview;
import 'ui_rollout_fixtures.dart';
import 'ui_rollout_training_test.dart' show rolloutTraining, rolloutExercise;

class _Coach extends CoachChatController {
  final reply = Completer<void>();
  @override
  Future<List<CoachBubble>> build() async => List.generate(30,
      (i) => CoachBubble(text: '旧饮食消息 $i：${'合成阅读内容。' * 10}', fromUser: false));
  @override
  Future<void> send(String message) async {
    final before = state.requireValue;
    state = AsyncData([...before, CoachBubble(text: message, fromUser: true)]);
    await reply.future;
    state = AsyncData([
      ...state.requireValue,
      const CoachBubble(text: '新的饮食回复', fromUser: false)
    ]);
  }
}

class _Health extends HealthChatController {
  final reply = Completer<void>();
  @override
  Future<List<HealthChatMessage>> build() async => List.generate(
      30,
      (i) => HealthChatMessage(
          text: '旧健康消息 $i：${'合成阅读内容。' * 10}', fromUser: false));
  @override
  Future<void> send(String message) async {
    final before = state.requireValue;
    state = AsyncData(
        [...before, HealthChatMessage(text: message, fromUser: true)]);
    await reply.future;
    state = AsyncData([
      ...state.requireValue,
      const HealthChatMessage(text: '新的健康回复', fromUser: false)
    ]);
  }
}

class _NoLostPhoto extends MealPhotoService {
  _NoLostPhoto(LocalDatabase database) : super(database, ImagePicker());
  @override
  Future<VisionTaskRecord?> recoverLostImage(
          {required String mealType}) async =>
      null;
}

class _Nutrition extends NutritionController {
  final pending = Completer<void>();
  int deletes = 0;
  double? updated;
  bool fail = false;
  @override
  Future<NutritionViewState> build() async => rolloutNutrition;
  @override
  Future<void> deleteItem(MealModel meal, MealItemModel item) async {
    expect(meal.id, 'synthetic-meal');
    expect(item.id, 'synthetic-item');
    deletes++;
    await pending.future;
    if (fail) throw StateError('private diagnostic');
  }

  @override
  Future<void> updateItem(
      MealModel meal, MealItemModel item, double amount) async {
    updated = amount;
  }
}

class _TrainingChat extends TrainingChatController {
  @override
  Future<List<TrainingChatMessage>> build() async => const [];
}

class _LongTrainingChat extends TrainingChatController {
  final reply = Completer<void>();
  @override
  Future<List<TrainingChatMessage>> build() async => List.generate(
      30,
      (i) => TrainingChatMessage(
          text: '旧训练消息 $i：${'合成阅读内容。' * 10}', fromUser: false));
  @override
  Future<void> send(String message) async {
    final before = state.requireValue;
    state = AsyncData(
        [...before, TrainingChatMessage(text: message, fromUser: true)]);
    await reply.future;
    state = AsyncData([
      ...state.requireValue,
      const TrainingChatMessage(text: '新的训练回复', fromUser: false)
    ]);
  }
}

void main() {
  testWidgets(
      'offline workout start, two sets, rest and completion persist to real SQLite',
      (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = LocalDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repository = _ObservedWorkout(db);
    await tester.pumpWidget(ProviderScope(
        overrides: [
          trainingHomeProvider.overrideWith((ref) async => rolloutTraining),
          offlineWorkoutRepositoryProvider.overrideWithValue(repository),
          workoutSyncTriggerProvider.overrideWithValue(() async {})
        ],
        child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(body: TrainingScreen()))));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('start-workout')));
    await tester.tap(find.byKey(const Key('start-workout')));
    await tester.runAsync(() => repository.lastOperation);
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '22.55');
    await tester.enterText(fields.at(1), '10');
    await tester.enterText(fields.at(2), '2.5');
    for (var i = 0; i < 2; i++) {
      await tester.ensureVisible(find.byKey(const Key('record-set')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('record-set')).hitTestable(), findsOneWidget);
      await tester.tap(find.byKey(const Key('record-set')));
      await tester.runAsync(() => repository.lastOperation);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('rest-timer')), findsOneWidget);
    }
    final outbox = await db.pendingOutbox();
    expect(
        outbox.where((e) => e.operation == 'workout_set_create'), hasLength(2));
    final session = outbox
        .firstWhere((e) => e.operation == 'workout_create')
        .aggregateLocalId;
    final sets = await db.workoutSets(session);
    expect(sets.map((e) => e.setNumber), [1, 2]);
    expect(
        sets.every((e) => e.weightKg == 22.55 && e.reps == 10 && e.rir == 2.5),
        isTrue);
    await tester.ensureVisible(find.text('完成训练并查看总结'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成训练并查看总结'));
    await tester.runAsync(() => repository.lastOperation);
    await tester.pumpAndSettle();
    expect((await db.workoutByLocalId(session))!.status, 'completed');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  for (final size in [
    const Size(320, 568),
    const Size(393, 852),
    const Size(430, 932)
  ]) {
    for (final dark in [false, true]) {
      testWidgets('training coach keyboard $size dark=$dark 200%',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(ProviderScope(
            overrides: [
              trainingHomeProvider.overrideWith((ref) async => rolloutTraining),
              trainingChatProvider.overrideWith(_TrainingChat.new)
            ],
            child: MaterialApp(
                theme: dark ? AppTheme.dark : AppTheme.light,
                builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                        viewInsets: const EdgeInsets.only(bottom: 300),
                        textScaler: const TextScaler.linear(2),
                        disableAnimations: true),
                    child: child!),
                home:
                    const Scaffold(body: SafeArea(child: TrainingScreen())))));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('AI 私教'));
        await tester.pumpAndSettle();
        await tester.enterText(
            find.byType(TextField).last, '这是合成测试问题。\n第二行\n第三行\n第四行');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final send = find.byTooltip('发送问题');
        expect(send.hitTestable(), findsOneWidget);
        expect(
            tester.getRect(send).bottom, lessThanOrEqualTo(size.height - 300));
      });
    }
  }
  test('editor numbers preserve precision without changing summary rounding',
      () {
    for (final value in [1.25, 125.5, 22.55, 2.5, 1.234567]) {
      expect(double.parse(AppFormat.editableNumber(value)), value);
    }
    expect(AppFormat.editableNumber(20.0), '20');
    expect(AppFormat.number(22.55, decimals: 1), '22.6');
  });

  testWidgets('workout opens and records the original fractional defaults',
      (tester) async {
    double? weight, rir;
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
            body: SingleChildScrollView(
                child: WorkoutSetEditor(
                    item: const TrainingExerciseModel(
                        id: 'fractional',
                        exercise: rolloutExercise,
                        targetSets: 3,
                        repMin: 8,
                        repMax: 12,
                        targetRir: 2.5,
                        restSeconds: 120,
                        targetWeightKg: 22.55),
                    enabled: true,
                    completed: const [],
                    onRecord: (w, _, r) async {
                      weight = w;
                      rir = r;
                    })))));
    final fields = find.byType(TextFormField);
    expect(
        tester.widget<TextFormField>(fields.at(0)).controller!.text, '22.55');
    expect(tester.widget<TextFormField>(fields.at(2)).controller!.text, '2.5');
    await tester.ensureVisible(find.byKey(const Key('record-set')));
    await tester.tap(find.byKey(const Key('record-set')));
    await tester.pumpAndSettle();
    expect(weight, 22.55);
    expect(rir, 2.5);
  });

  for (final dark in [false, true]) {
    testWidgets('filled send and search follow shared roles dark=$dark',
        (tester) async {
      final theme = dark ? AppTheme.dark : AppTheme.light;
      await tester.pumpWidget(ProviderScope(
          overrides: [
            coachOverviewProvider
                .overrideWith((ref) async => rolloutCoachOverview),
            coachChatProvider.overrideWith(_Coach.new),
            trainingHomeProvider.overrideWith((ref) async => rolloutTraining)
          ],
          child: MaterialApp(
              theme: theme, home: const Scaffold(body: CoachScreen()))));
      await tester.pumpAndSettle();
      final icon = find.descendant(
          of: find.byTooltip('发送'), matching: find.byType(Icon));
      final foreground = IconTheme.of(tester.element(icon)).color!;
      expect(foreground, theme.colorScheme.onPrimary);
      final a = foreground.computeLuminance(),
          b = theme.colorScheme.primary.computeLuminance();
      expect((a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05)),
          greaterThanOrEqualTo(3));
      await tester.pumpWidget(ProviderScope(
          key: UniqueKey(),
          overrides: [
            trainingHomeProvider.overrideWith((ref) async => rolloutTraining)
          ],
          child: MaterialApp(
              theme: theme, home: const Scaffold(body: TrainingScreen()))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('动作库'));
      await tester.pumpAndSettle();
      final search = SearchBarTheme.of(tester.element(find.byType(SearchBar)));
      expect(search.elevation!.resolve({}), 0);
      expect(search.shape!.resolve({}), isA<RoundedRectangleBorder>());
      await tester.tap(find.byTooltip('AI 私教'));
      await tester.pumpAndSettle();
      final trainingIcon = find.descendant(
          of: find.byTooltip('发送问题'), matching: find.byType(Icon));
      expect(IconTheme.of(tester.element(trainingIcon)).color,
          theme.colorScheme.onPrimary);
    });
  }

  for (final kind in ['coach', 'health', 'training']) {
    final health = kind == 'health', training = kind == 'training';
    for (final readOld in [false, true]) {
      testWidgets('chat arrival kind=$kind preserveReading=$readOld',
          (tester) async {
        final coach = _Coach(), healthChat = _Health();
        final trainingChat = _LongTrainingChat();
        await tester.pumpWidget(ProviderScope(
            overrides: [
              coachOverviewProvider
                  .overrideWith((ref) async => rolloutCoachOverview),
              coachChatProvider.overrideWith(() => coach),
              healthReportsProvider.overrideWith((ref) async => [sampleReport]),
              labTrendProvider.overrideWith((ref, name) async => sampleTrend),
              healthChatProvider.overrideWith(() => healthChat),
              trainingHomeProvider.overrideWith((ref) async => rolloutTraining),
              trainingChatProvider.overrideWith(() => trainingChat)
            ],
            child: MaterialApp(
                theme: AppTheme.light,
                home: Scaffold(
                    body: training
                        ? const TrainingScreen()
                        : health
                            ? const HealthScreen()
                            : const CoachScreen()))));
        await tester.pumpAndSettle();
        if (health) {
          await tester.tap(find.text('健康 AI'));
          await tester.pumpAndSettle();
        }
        if (training) {
          await tester.tap(find.byTooltip('AI 私教'));
          await tester.pumpAndSettle();
        }
        await tester.enterText(find.byType(TextField).last, '新的合成问题');
        await tester.tap(find.byTooltip(training
            ? '发送问题'
            : health
                ? '发送健康问题'
                : '发送'));
        await tester.pumpAndSettle();
        final list = training
            ? find.byKey(const Key('training-chat-history'))
            : health
                ? find.byKey(const Key('health-chat-history'))
                : find.byType(ListView).first;
        final scroll = tester.widget<ListView>(list).controller!;
        if (readOld) {
          await tester.drag(list, const Offset(0, 500));
          await tester.pumpAndSettle();
        }
        final offset = scroll.offset;
        (training
                ? trainingChat.reply
                : health
                    ? healthChat.reply
                    : coach.reply)
            .complete();
        await tester.pumpAndSettle();
        if (readOld) {
          expect(scroll.offset, offset);
          expect(find.text('查看新回复').hitTestable(), findsOneWidget);
          await tester.tap(find.text('查看新回复'));
          await tester.pumpAndSettle();
        }
        expect(scroll.position.extentAfter, lessThan(1));
        expect(
            find
                .text(training
                    ? '新的训练回复'
                    : health
                        ? '新的健康回复'
                        : '新的饮食回复')
                .hitTestable(),
            findsOneWidget);
        expect(find.text('查看新回复'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final fail in [false, true]) {
    testWidgets('meal delete cancels, awaits once and retains failure=$fail',
        (tester) async {
      final db = LocalDatabase();
      addTearDown(db.close);
      final nutrition = _Nutrition()..fail = fail;
      await tester.pumpWidget(ProviderScope(
          overrides: [
            nutritionControllerProvider.overrideWith(() => nutrition),
            connectivitySyncProvider.overrideWith((ref) {}),
            mealPhotoServiceProvider.overrideWithValue(_NoLostPhoto(db)),
          ],
          child: MaterialApp(
              theme: AppTheme.light,
              home: const Scaffold(body: NutritionScreen()))));
      await tester.pumpAndSettle();
      Future<void> openDelete() async {
        await tester.scrollUntilVisible(
            find.text(rolloutNutrition.meals.first.items.first.foodName), 300,
            scrollable: find.byType(Scrollable).first);
        await tester.pumpAndSettle();
        await tester.ensureVisible(
            find.text(rolloutNutrition.meals.first.items.first.foodName));
        await tester
            .tap(find.text(rolloutNutrition.meals.first.items.first.foodName));
        await tester.pumpAndSettle();
        await tester.tap(find.text('删除条目'));
        await tester.pumpAndSettle();
        expect(find.textContaining('1 份'), findsOneWidget);
      }

      await openDelete();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(nutrition.deletes, 0);
      await openDelete();
      await tester.tap(find.text('确认删除'));
      await tester.pump();
      await tester.tap(find.text('正在删除…'));
      await tester.pump();
      expect(nutrition.deletes, 1);
      expect(
          tester.widget<FilledButton>(find.byType(FilledButton).last).onPressed,
          isNull);
      nutrition.pending.complete();
      await tester.pumpAndSettle();
      expect(find.byType(AwaitedEntryDialog),
          fail ? findsOneWidget : findsNothing);
      if (fail) expect(find.text('重试删除'), findsOneWidget);
      expect(find.textContaining('private diagnostic'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}

// Observe completion only; every write uses the unchanged production repository.
class _ObservedWorkout implements WorkoutRepository {
  _ObservedWorkout(LocalDatabase database)
      : inner = OfflineWorkoutRepository(database);
  final OfflineWorkoutRepository inner;
  Future<void> lastOperation = Future.value();
  @override
  Future<LocalWorkoutRecord> start({String? trainingDayId}) {
    final result = inner.start(trainingDayId: trainingDayId);
    lastOperation = result.then((_) {});
    return result;
  }

  @override
  Future<LocalWorkoutSetRecord> recordSet(
      {required String sessionLocalId,
      required String exerciseId,
      required int setNumber,
      required double weightKg,
      required int reps,
      required double rir,
      required int restSeconds,
      String setType = 'working'}) {
    final result = inner.recordSet(
        sessionLocalId: sessionLocalId,
        exerciseId: exerciseId,
        setNumber: setNumber,
        weightKg: weightKg,
        reps: reps,
        rir: rir,
        restSeconds: restSeconds,
        setType: setType);
    lastOperation = result.then((_) {});
    return result;
  }

  @override
  Future<void> complete(String sessionLocalId, {double? sessionRpe}) {
    final result = inner.complete(sessionLocalId, sessionRpe: sessionRpe);
    lastOperation = result;
    return result;
  }

  @override
  Future<List<LocalWorkoutSetRecord>> sets(String sessionLocalId) =>
      inner.sets(sessionLocalId);
}
