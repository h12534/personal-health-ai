import 'package:flutter_test/flutter_test.dart';
import 'package:personal_health_os/features/dashboard/data/dashboard_model.dart';

void main() {
  test('dashboard model accepts incomplete Phase 1 nutrition data', () {
    final model = DashboardModel.fromJson({
      'date': '2026-09-29',
      'today_weight_kg': 100.0,
      'average_7d_kg': 100.4,
      'week_change_kg': -0.6,
      'morning_weight_completed': true,
      'ai_next_action': '保持当前策略',
    });

    expect(model.todayWeightKg, 100.0);
    expect(model.caloriesConsumed, 0);
    expect(model.stepsTarget, 8000);
  });
}
