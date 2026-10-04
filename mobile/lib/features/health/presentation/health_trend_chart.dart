import 'package:flutter/material.dart';
import '../../../core/widgets/app_trend_chart.dart';
import '../data/health_models.dart';

/// Clinical presentation adapter. Filtering, raw precision and ranges stay here.
class LabTrendChart extends StatelessWidget {
  const LabTrendChart({super.key, required this.trend, this.detailKey = true});
  final LabTrendModel trend;
  final bool detailKey;
  @override
  Widget build(BuildContext context) {
    final all = trend.points;
    final points = all
        .where((p) =>
            p.value.isFinite && p.unit.trim() == trend.canonicalUnit.trim())
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    if (points.isEmpty) return const Text('暂无单位一致、可比较的历史记录');
    return Column(
        key: Key(detailKey ? 'lab-trend-chart' : 'overview-lab-trend-chart'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              points.length == 1
                  ? '仅 1 次记录，尚不能判断趋势'
                  : '${points.length} 次记录 · ${trend.canonicalUnit}',
              style: Theme.of(context).textTheme.bodySmall),
          if (points.length != all.length)
            Text('已排除单位不同或无效的记录', style: Theme.of(context).textTheme.bodySmall),
          AppTrendChart(
              label: trend.displayName,
              unit: trend.canonicalUnit,
              points: [
                for (final p in points)
                  AppTrendPoint(p.date, p.value,
                      valueText: p.value.toString(),
                      annotation: p.referenceMin != null ||
                              p.referenceMax != null
                          ? '该次报告范围：${p.referenceMin ?? '—'}–${p.referenceMax ?? '—'} ${p.unit}'
                          : null),
              ]),
        ]);
  }
}
