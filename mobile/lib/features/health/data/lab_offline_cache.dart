import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/local_database.dart';
import 'health_models.dart';

final labOfflineCacheProvider = Provider<LabOfflineCache>((ref) {
  return LabOfflineCache(ref.watch(localDatabaseProvider));
});

class LabOfflineCache {
  const LabOfflineCache(this.database);

  final LocalDatabase database;

  Future<void> saveReports(List<LabReportModel> reports) =>
      database.cacheLabReports(reports.map((item) => item.toJson()).toList());

  Future<List<LabReportModel>> loadReports() async {
    final values = await database.cachedLabReports();
    return values.map(LabReportModel.fromJson).toList();
  }

  Future<void> saveTrend(LabTrendModel trend) =>
      database.cacheLabTrend(trend.normalizedName, trend.toJson());

  Future<LabTrendModel?> loadTrend(String normalizedName) async {
    final value = await database.cachedLabTrend(normalizedName);
    return value == null ? null : LabTrendModel.fromJson(value);
  }
}
