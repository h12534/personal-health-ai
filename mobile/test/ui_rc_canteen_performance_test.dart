import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_health_os/core/theme/app_theme.dart';
import 'package:personal_health_os/core/widgets/app_components.dart';
import 'package:personal_health_os/core/network/api_client.dart';
import 'ui_polish_fixtures.dart';
import 'package:personal_health_os/core/database/local_database.dart';
import 'package:personal_health_os/features/nutrition/data/offline_meal_repository.dart';
import 'package:personal_health_os/features/nutrition/data/nutrition_models.dart';
import 'package:personal_health_os/features/nutrition/presentation/food_search_screen.dart';
import 'package:personal_health_os/features/coach/data/coach_models.dart';
import 'package:personal_health_os/features/coach/presentation/canteen_screen.dart';
import 'package:personal_health_os/features/coach/presentation/coach_controller.dart';

// Synthetic stress data only: 10 canteens, 50 stalls, 1,000 dishes.
final rcCanteens = List.generate(
    10,
    (canteen) => CanteenModel(
        id: 'rc-canteen-$canteen',
        name: '合成食堂 $canteen',
        stalls: List.generate(
            5,
            (stall) => CanteenStallModel(
                id: 'rc-stall-$canteen-$stall',
                canteenId: 'rc-canteen-$canteen',
                name: '合成档口 $canteen-$stall',
                dishes: List.generate(
                    20,
                    (dish) => CanteenDishModel(
                        id: 'rc-dish-$canteen-$stall-$dish',
                        stallId: 'rc-stall-$canteen-$stall',
                        name: '合成菜品 $canteen-$stall-$dish',
                        calories: 320,
                        protein: 25,
                        carbs: 30,
                        fat: 10,
                        fiber: 3,
                        confidence: .5,
                        favorite: false,
                        source: 'manual'))))));

List<SavedMealModel> rcSavedMeals(int count) => List.generate(
    count,
    (index) => SavedMealModel(
        id: 'rc-meal-$index',
        name: '合成套餐 $index',
        mealType: 'lunch',
        itemCount: 3,
        totalCalories: 550));

Future<void> pumpRcCanteen(WidgetTester tester,
    {int meals = 0,
    bool dark = false,
    double scale = 1,
    List<CanteenModel>? canteens,
    ApiClient? api}) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
      overrides: [
        if (api != null) apiClientProvider.overrideWithValue(api),
        canteensProvider.overrideWith((ref) async => canteens ?? rcCanteens),
        savedMealsProvider.overrideWith((ref) async => rcSavedMeals(meals)),
        canteenRecommendationsProvider.overrideWith((ref) async => []),
      ],
      child: MaterialApp(
          theme: dark ? AppTheme.dark : AppTheme.light,
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(scale),
                  disableAnimations: true),
              child: child!),
          home: const CanteenScreen())));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'pending dish favorite survives collapse and reopen without duplicate write',
      (tester) async {
    final api = _PendingDishApi();
    await pumpRcCanteen(tester, api: api);
    await tester.tap(find.text('合成食堂 0'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('合成档口 0-0'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('收藏').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('收藏').first);
    await tester.pumpAndSettle();
    expect(api.calls, 1);
    await tester.scrollUntilVisible(find.text('合成档口 0-0'), -300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('合成档口 0-0'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('合成档口 0-0'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('合成菜品 0-0-0'));
    await tester.pumpAndSettle();
    expect(find.text('正在处理…'), findsOneWidget);
    await tester.tap(find.text('正在处理…'));
    await tester.pump();
    expect(api.calls, 1);
    api.pending.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      '1000-food catalogue scrolls and submitted search filters without per-keystroke requests',
      (tester) async {
    final db = LocalDatabase();
    addTearDown(db.close);
    final foods = _LargeFoods(db);
    await tester.pumpWidget(ProviderScope(
        overrides: [offlineMealRepositoryProvider.overrideWithValue(foods)],
        child: MaterialApp(
            theme: AppTheme.light,
            home: const FoodSearchScreen(mealType: 'lunch'))));
    await tester.pumpAndSettle();
    final mounted = find.byWidgetPredicate(
        (w) => w is Text && (w.data?.startsWith('合成食物 ') ?? false));
    expect(mounted.evaluate().length, lessThan(30));
    await tester.scrollUntilVisible(find.text('合成食物 999'), 1000,
        scrollable: find.byType(Scrollable).first, maxScrolls: 200);
    await tester.pumpAndSettle();
    expect(find.text('合成食物 999').hitTestable(), findsOneWidget);
    await tester.scrollUntilVisible(find.byType(TextField), -1000,
        scrollable: find.byType(Scrollable).first, maxScrolls: 200);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '合成食物 999');
    await tester.pumpAndSettle();
    expect(foods.queries, ['']);
    await tester.tap(find.byTooltip('搜索食物'));
    await tester.pumpAndSettle();
    expect(foods.queries, ['', '合成食物 999']);
    expect(find.byWidgetPredicate((w) => w is Text && w.data == '合成食物 999'),
        findsOneWidget);
    expect(find.text('合成食物 0'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  for (final dark in [false, true]) {
    testWidgets('1000 dishes expand, collapse, deep scroll dark=$dark 200%',
        (tester) async {
      await pumpRcCanteen(tester, dark: dark, scale: 2);
      await tester.scrollUntilVisible(find.text('合成食堂 9'), 500,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('合成食堂 9'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('合成档口 9-4'), 400,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('合成档口 9-4'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('合成菜品 9-4-19'), 500,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(find.text('合成菜品 9-4-19').hitTestable(), findsOneWidget);
      await tester.scrollUntilVisible(find.text('合成档口 9-4'), -500,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('合成档口 9-4'));
      await tester.pumpAndSettle();
      expect(find.text('合成菜品 9-4-19'), findsNothing);
      await tester.tap(find.text('合成档口 9-4'));
      await tester.pumpAndSettle();
      expect(find.text('合成菜品 9-4-0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('one expanded 1000-dish stall still builds only visible rows',
      (tester) async {
    final dishes =
        rcCanteens.expand((c) => c.stalls).expand((s) => s.dishes).toList();
    await pumpRcCanteen(tester, canteens: [
      CanteenModel(id: 'wide', name: '大食堂', stalls: [
        CanteenStallModel(
            id: 'wide-stall', canteenId: 'wide', name: '大档口', dishes: dishes)
      ])
    ]);
    await tester.tap(find.text('大食堂'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('大档口'));
    await tester.pumpAndSettle();
    final mounted = find.byWidgetPredicate(
        (w) => w is Text && (w.data?.startsWith('合成菜品 ') ?? false));
    debugPrint(
        'UI_RC_PROFILE dishes=1000 mounted=${mounted.evaluate().length}');
    expect(mounted.evaluate().length, lessThan(30));
    await tester.scrollUntilVisible(find.text('合成菜品 9-4-19'), 1000,
        scrollable: find.byType(Scrollable).first, maxScrolls: 350);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('合成菜品 9-4-19'));
    await tester.pumpAndSettle();
    expect(find.text('合成菜品 9-4-19').hitTestable(), findsOneWidget);
    expect(mounted.evaluate().length, lessThan(30));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'pending meal action survives lazy recycling without duplicate write',
      (tester) async {
    final api = _PendingMealApi();
    await pumpRcCanteen(tester, meals: 1000, api: api);
    await tester.tap(find.text('一键记录').first);
    await tester.pump();
    expect(api.calls, 1);
    final rowState = tester.state(find.byType(AsyncActionButton).first);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -4000));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('合成套餐 0'), -1000,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(AsyncActionButton).first), same(rowState));
    expect(
        tester.widget<FilledButton>(find.byType(FilledButton).first).onPressed,
        isNull);
    api.pending.complete();
    await tester.pumpAndSettle();
    expect(api.calls, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('RC large saved-meal list builds only viewport rows',
      (tester) async {
    final timer = Stopwatch()..start();
    await pumpRcCanteen(tester, meals: 1000);
    final mounted = find.byWidgetPredicate((widget) =>
        widget is Text && (widget.data?.startsWith('合成套餐 ') ?? false));
    debugPrint(
        'UI_RC_PROFILE savedMeals=1000 mounted=${mounted.evaluate().length} '
        'debugPumpMs=${timer.elapsedMilliseconds}');
    expect(tester.takeException(), isNull);
    expect(mounted.evaluate().length, lessThan(30),
        reason:
            'Saved-meal widgets must be bounded by the viewport, not collection size');
    expect(find.text('合成套餐 999'), findsNothing);
    await tester.scrollUntilVisible(find.text('合成套餐 999'), 1000,
        scrollable: find.byType(Scrollable).first, maxScrolls: 250);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('合成套餐 999'));
    await tester.pumpAndSettle();
    expect(find.text('合成套餐 999').hitTestable(), findsOneWidget);
    expect(mounted.evaluate().length, lessThan(30));
    expect(tester.takeException(), isNull);
  });
}

class _PendingMealApi extends PolishApi {
  int calls = 0;
  @override
  Future<void> logSavedMeal(SavedMealModel value) async {
    calls++;
    await pending.future;
  }
}

class _LargeFoods extends PolishFoods {
  _LargeFoods(super.database);
  final queries = <String>[];
  final foods = List.generate(
      1000,
      (i) => FoodModel(
          id: 'rc-food-$i',
          name: '合成食物 $i',
          category: 'grain',
          caloriesPer100g: 137,
          proteinPer100g: 2.6,
          carbsPer100g: 28,
          fatPer100g: .8,
          fiberPer100g: .3,
          isFavorite: false));
  @override
  Future<List<FoodModel>> searchFoods(String query,
      {String mode = 'search'}) async {
    queries.add(query);
    return foods.where((food) => food.name.contains(query)).toList();
  }
}

class _PendingDishApi extends PolishApi {
  int calls = 0;
  @override
  Future<void> saveCanteenDish(
      {String? id,
      required String stallId,
      required String name,
      required double calories,
      required double protein,
      required double carbs,
      required double fat,
      required double fiber,
      String? portionDescription,
      double? averageWeight,
      double confidence = .5,
      bool favorite = false,
      String source = 'manual'}) async {
    expect(id, 'rc-dish-0-0-0');
    expect(favorite, isTrue);
    calls++;
    await pending.future;
  }
}
