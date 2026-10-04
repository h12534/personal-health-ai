import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_health_os/core/database/local_database.dart';
import 'package:personal_health_os/app.dart';
import 'package:personal_health_os/core/network/api_client.dart';
import 'package:personal_health_os/core/theme/app_theme.dart';
import 'package:personal_health_os/core/theme/app_tokens.dart';
import 'package:personal_health_os/core/widgets/app_components.dart';
import 'package:personal_health_os/features/auth/presentation/auth_controller.dart';
import 'package:personal_health_os/features/auth/presentation/login_screen.dart';
import 'package:personal_health_os/features/coach/presentation/canteen_screen.dart';
import 'package:personal_health_os/features/coach/presentation/coach_controller.dart';
import 'package:personal_health_os/features/nutrition/data/offline_meal_repository.dart';
import 'package:personal_health_os/features/nutrition/presentation/add_food_screen.dart';
import 'package:personal_health_os/features/nutrition/presentation/food_search_screen.dart';
import 'package:personal_health_os/features/nutrition/presentation/nutrition_controller.dart';
import 'ui_polish_fixtures.dart';

void main() {
  for (final startupFailure in [false, true]) {
    testWidgets(
        'production App keeps login state through slow failure startup=$startupFailure',
        (tester) async {
      final auth = PolishAuth(startupFailure: startupFailure);
      await tester.pumpWidget(ProviderScope(
          overrides: [authControllerProvider.overrideWith(() => auth)],
          child: const HealthOsApp()));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byType(TextFormField).at(0), 'synthetic@example.invalid');
      await tester.enterText(
          find.byType(TextFormField).at(1), 'synthetic-only');
      final emailController = tester
          .widget<TextFormField>(find.byType(TextFormField).at(0))
          .controller;
      final passwordController = tester
          .widget<TextFormField>(find.byType(TextFormField).at(1))
          .controller;
      await tester.tap(find.text('登录'));
      await tester.pump();
      expect(auth.calls, 1);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(
          tester
              .widget<TextFormField>(find.byType(TextFormField).at(0))
              .controller,
          same(emailController));
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull);
      auth.pending.complete();
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<TextFormField>(find.byType(TextFormField).at(1))
              .controller,
          same(passwordController));
      expect(emailController!.text, 'synthetic@example.invalid');
      expect(passwordController!.text, 'synthetic-only');
      expect(find.text('请检查邮箱和密码后重试。'), findsOneWidget);
      expect(find.textContaining('private raw'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  for (final width in [320.0, 393.0, 430.0]) {
    for (final dark in [false, true]) {
      testWidgets('auxiliary rollout $width dark=$dark 200%', (tester) async {
        tester.view.physicalSize = Size(width, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        final db = LocalDatabase();
        addTearDown(db.close);
        for (final screen in [
          const LoginScreen(initialError: 'private raw startup error'),
          const FoodSearchScreen(mealType: 'lunch'),
          const AddFoodScreen(mealType: 'lunch', food: polishFood),
          const CanteenScreen()
        ]) {
          await tester.pumpWidget(ProviderScope(
              key: UniqueKey(),
              overrides: [
                authControllerProvider.overrideWith(PolishAuth.new),
                offlineMealRepositoryProvider
                    .overrideWithValue(PolishFoods(db)),
                canteensProvider.overrideWith((ref) async => []),
                savedMealsProvider.overrideWith((ref) async => []),
                canteenRecommendationsProvider.overrideWith((ref) async => []),
              ],
              child: MaterialApp(
                  theme: dark ? AppTheme.dark : AppTheme.light,
                  builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                          textScaler: const TextScaler.linear(2),
                          disableAnimations: true),
                      child: child!),
                  home: screen)));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.textContaining('private raw'), findsNothing);
          if (screen is FoodSearchScreen) {
            tester.view.viewInsets = const FakeViewPadding(bottom: 300);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(find.byType(TextField).hitTestable(), findsOneWidget);
            tester.view.resetViewInsets();
            await tester.pumpAndSettle();
          }
          final scrolls = find.byType(Scrollable);
          if (scrolls.evaluate().isNotEmpty) {
            for (var i = 0; i < 8; i++) {
              await tester.drag(scrolls.last, const Offset(0, -180));
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
            }
          }
        }
      });
    }
  }
  testWidgets('login awaits once and keeps safe failed credentials',
      (tester) async {
    final auth = PolishAuth();
    await tester.pumpWidget(ProviderScope(
        overrides: [authControllerProvider.overrideWith(() => auth)],
        child: MaterialApp(theme: AppTheme.light, home: const LoginScreen())));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextFormField).at(0), 'synthetic@example.invalid');
    await tester.enterText(find.byType(TextFormField).at(1), 'synthetic-only');
    await tester.tap(find.text('登录'));
    await tester.pump();
    expect(auth.calls, 1);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    auth.pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('请检查邮箱和密码后重试。'), findsOneWidget);
    expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).at(1))
            .controller!
            .text,
        'synthetic-only');
    expect(find.textContaining('private raw'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'manual food finite validation, awaited exact payload and retained failure',
      (tester) async {
    final nutrition = PolishNutrition();
    await tester.pumpWidget(ProviderScope(
        overrides: [nutritionControllerProvider.overrideWith(() => nutrition)],
        child: MaterialApp(
            theme: AppTheme.light,
            home: const AddFoodScreen(mealType: 'lunch', food: polishFood))));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Infinity');
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    await tester.enterText(find.byType(TextField), '125.5');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('加入午餐'));
    await tester.tap(find.text('加入午餐'));
    await tester.pump();
    expect(nutrition.calls, 1);
    expect(nutrition.savedAmount, 125.5);
    expect(nutrition.savedUnit, 'g');
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    nutrition.pending.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '125.5');
    expect(find.textContaining('份量已保留'), findsOneWidget);
    expect(find.textContaining('private raw'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'canteen error differs from empty; editor waits and preserves original payload',
      (tester) async {
    final api = PolishApi();
    await tester.pumpWidget(ProviderScope(overrides: [
      apiClientProvider.overrideWithValue(api),
      canteensProvider.overrideWith((ref) async => []),
      savedMealsProvider.overrideWith((ref) async => []),
      canteenRecommendationsProvider
          .overrideWith((ref) async => throw StateError('private raw error')),
    ], child: MaterialApp(theme: AppTheme.light, home: const CanteenScreen())));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byType(ErrorState), 250,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('还没有可推荐的菜品'), findsNothing);
    expect(find.byType(ErrorState), findsOneWidget);
    final add = find.text('新增食堂').first;
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(api.saves, 0);
    expect(find.text('请填写食堂名称'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), ' 合成食堂 ');
    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(api.saves, 1);
    expect(find.byType(AwaitedEntryDialog), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    expect(api.lastSave, {
      'id': null,
      'name': '合成食堂',
      'campus': null,
      'location': null,
      'note': null
    });
    api.pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('重试保存'), findsOneWidget);
    expect(
        tester.widget<TextField>(find.byType(TextField).at(0)).controller!.text,
        ' 合成食堂 ');
    expect(find.textContaining('private raw'), findsNothing);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'shared protected editor retains input and rejects duplicate saves',
      (tester) async {
    final input = TextEditingController(text: 'synthetic');
    addTearDown(input.dispose);
    final pending = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
            body: AwaitedEntryDialog(
                title: '合成编辑',
                content: TextField(controller: input),
                validate: () => null,
                onSave: () async {
                  calls++;
                  await pending.future;
                  throw StateError('private raw error');
                }))));
    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(calls, 1);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    pending.complete();
    await tester.pumpAndSettle();
    expect(input.text, 'synthetic');
    expect(find.text('重试保存'), findsOneWidget);
    expect(find.textContaining('private raw'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  test('all data-bearing shared type roles request tabular figures', () {
    for (final role in [
      AppTypography.heroMetric,
      AppTypography.metric,
      AppTypography.metricLabel,
      AppTypography.cardTitle,
      AppTypography.body,
      AppTypography.secondary,
      AppTypography.caption
    ]) {
      expect(role.fontFeatures, contains(const FontFeature.tabularFigures()));
    }
  });
}
