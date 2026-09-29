import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_health_os/features/dashboard/data/dashboard_model.dart';
import 'package:personal_health_os/features/dashboard/presentation/dashboard_screen.dart';

void main() {
  testWidgets('dashboard emphasizes next action and core metrics', (tester) async {
    final data = DashboardModel(
      date: DateTime(2026, 9, 29),
      todayWeightKg: 100,
      average7dKg: 100.4,
      weekChangeKg: -0.6,
      caloriesConsumed: 1680,
      caloriesTarget: 2200,
      proteinG: 92,
      proteinTargetG: 135,
      steps: 5340,
      stepsTarget: 8000,
      waterMl: 1250,
      trainingCompleted: false,
      morningWeightCompleted: true,
      aiNextAction: '晚餐优先选择现实可获得的优质蛋白质。',
    );

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: DashboardContent(data: data, onAddWeight: () {}))),
    );

    expect(find.text('下一步'), findsOneWidget);
    expect(find.textContaining('优质蛋白质'), findsOneWidget);
    expect(find.text('1680'), findsOneWidget);
    expect(find.text('92 g'), findsOneWidget);
  });
}

