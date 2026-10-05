import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_health_os/core/database/local_database.dart';
import 'package:personal_health_os/core/network/api_client.dart';
import 'package:personal_health_os/core/theme/app_theme.dart';
import 'package:personal_health_os/features/nutrition/data/meal_analysis_models.dart';
import 'package:personal_health_os/features/nutrition/data/nutrition_models.dart';
import 'package:personal_health_os/features/nutrition/presentation/meal_analysis_screen.dart';
import 'ui_polish_fixtures.dart';
import 'ui_rollout_fixtures.dart';

// Tests the production draft UI with synthetic service responses, not a camera
// or an AI provider. Native permission and image recognition remain device gates.
class _DraftApi extends PolishApi {
  double? editedWeight;
  int deleted = 0, confirmed = 0;
  final items = [
    for (final (id, name) in [('fractional', '合成鸡肉'), ('mistake', '误识别合成条目')])
      MealAnalysisItemModel.fromJson({
        'id': id,
        'detected_name': name,
        'matched_food_id': 'synthetic-food',
        'matched_food_name': name,
        'match_type': 'manual',
        'confidence_label': 'medium',
        'estimated_weight_g': 125.5,
        'min_weight_g': 100,
        'max_weight_g': 150,
      })
  ];
  MealAnalysisModel get analysis => MealAnalysisModel(
      id: 'synthetic-analysis',
      status: 'completed',
      provider: 'synthetic',
      model: 'synthetic',
      promptVersion: 'synthetic',
      warnings: const [],
      items: [...items],
      totals: rolloutDraft.totals,
      reanalysisCount: 0);
  @override
  Future<MealAnalysisModel> fetchMealAnalysis(String analysisId) async =>
      analysis;
  @override
  Future<MealAnalysisModel> updateMealAnalysisItem(
      {required String analysisId,
      required String itemId,
      double? weightG,
      double? minWeightG,
      double? maxWeightG,
      String? foodId}) async {
    expect(itemId, 'fractional');
    editedWeight = weightG;
    expect(minWeightG, 125.5 * .75);
    expect(maxWeightG, 125.5 * 1.25);
    return analysis;
  }

  @override
  Future<MealAnalysisModel> deleteMealAnalysisItem(
      String analysisId, String itemId) async {
    expect(itemId, 'mistake');
    deleted++;
    items.removeWhere((item) => item.id == itemId);
    return analysis;
  }

  @override
  Future<MealModel> confirmMealAnalysis(
      {required String analysisId,
      required String mealType,
      required DateTime eatenAt,
      required String idempotencyKey,
      String? note}) async {
    expect(analysisId, 'synthetic-analysis');
    expect(mealType, 'lunch');
    expect(idempotencyKey, 'confirm-rc-draft');
    confirmed++;
    return rolloutNutrition.meals.first;
  }
}

void main() {
  testWidgets(
      'restored draft keeps fractional grams, removes mistake and confirms once',
      (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const channel = MethodChannel('dev.fluttercommunity.plus/connectivity');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async => ['wifi']);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final db = LocalDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final api = _DraftApi();
    final now = DateTime(2026, 10, 5);
    final task = VisionTaskRecord(
        localId: 'rc-draft',
        imagePath: 'synthetic-not-present.jpg',
        mealType: 'lunch',
        locationContext: 'school_canteen',
        status: 'completed',
        uploadProgress: 1,
        createdAt: now,
        updatedAt: now,
        analysisId: 'synthetic-analysis');
    await tester.pumpWidget(ProviderScope(
        overrides: [
          localDatabaseProvider.overrideWithValue(db),
          apiClientProvider.overrideWithValue(api)
        ],
        child: MaterialApp(
            theme: AppTheme.light,
            home: Builder(
                builder: (context) => Scaffold(
                    body: TextButton(
                        onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                                builder: (_) =>
                                    MealAnalysisScreen(task: task))),
                        child: const Text('恢复合成草稿')))))));
    await tester.tap(find.text('恢复合成草稿'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => db.customSelect('SELECT 1').get());
    await tester.pumpAndSettle();
    expect(find.textContaining('尚未计入今日营养'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('直接输入').first, 250,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('直接输入').first);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        '125.5');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(api.editedWeight, 125.5);
    await tester.scrollUntilVisible(find.byTooltip('更多：误识别合成条目'), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('更多：误识别合成条目'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除条目'));
    await tester.pumpAndSettle();
    expect(api.deleted, 1);
    expect(find.text('误识别合成条目'), findsNothing);
    await tester.tap(find.text('确认并计入今日营养'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => db.customSelect('SELECT 1').get());
    await tester.pumpAndSettle();
    expect(api.confirmed, 1);
    expect(find.byType(MealAnalysisScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
