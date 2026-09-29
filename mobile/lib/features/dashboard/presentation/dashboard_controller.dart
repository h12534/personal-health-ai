import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../data/dashboard_model.dart';

final dashboardProvider = FutureProvider<DashboardModel>((ref) {
  return ref.watch(apiClientProvider).fetchDashboard();
});

class WeightController {
  const WeightController(this.ref);

  final WidgetRef ref;

  Future<void> add(double value) async {
    await ref.read(apiClientProvider).addWeight(value, DateTime.now());
    ref.invalidate(dashboardProvider);
  }
}

