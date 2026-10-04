import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_tokens.dart';
import '../data/health_models.dart';

/// Date-positioned data with a readable, accessible point picker.
class LabTrendChart extends StatefulWidget {
  const LabTrendChart({super.key, required this.trend, this.detailKey = true});
  final LabTrendModel trend;
  final bool detailKey;
  @override
  State<LabTrendChart> createState() => _LabTrendChartState();
}

class _LabTrendChartState extends State<LabTrendChart> {
  int? _selected;
  @override
  void didUpdateWidget(covariant LabTrendChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trend != widget.trend) _selected = null;
  }

  @override
  Widget build(BuildContext context) {
    final all = widget.trend.points;
    final points = all
        .where((p) =>
            p.value.isFinite &&
            p.unit.trim() == widget.trend.canonicalUnit.trim())
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    if (points.isEmpty) {
      return const Center(child: Text('暂无单位一致、可比较的历史记录'));
    }
    final selected =
        (_selected ?? points.length - 1).clamp(0, points.length - 1);
    final point = points[selected];
    final minValue = math.min(0.0, points.map((p) => p.value).reduce(math.min));
    final maxValue =
        math.max(minValue + 1, points.map((p) => p.value).reduce(math.max));
    final top = maxValue + (maxValue - minValue) * .15;
    return Column(
      mainAxisSize: MainAxisSize.min,
      key: Key(
          widget.detailKey ? 'lab-trend-chart' : 'overview-lab-trend-chart'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
            points.length == 1
                ? '仅 1 次记录，尚不能判断趋势'
                : '${points.length} 次记录 · ${widget.trend.canonicalUnit}',
            style: text.bodySmall?.copyWith(color: colors.secondaryText)),
        if (points.length != all.length)
          Text('已排除单位不同或无效的记录', style: text.bodySmall),
        SizedBox(
          height: AppComponentSize.chart *
              MediaQuery.textScalerOf(context).scale(1),
          child: LayoutBuilder(builder: (context, constraints) {
            final positions = _positions(points);
            final axisInset =
                AppSpacing.xl * MediaQuery.textScalerOf(context).scale(1);
            return Semantics(
              label:
                  '${widget.trend.displayName}趋势图，纵轴 ${minValue.toStringAsFixed(1)} 至 ${top.toStringAsFixed(1)} ${widget.trend.canonicalUnit}；横轴按真实日期排列，可在下方选择记录读取数值。',
              child: GestureDetector(
                onTapDown: (details) {
                  final ratio = ((details.localPosition.dx - axisInset) /
                          math.max(1.0,
                              constraints.maxWidth - axisInset - AppSpacing.sm))
                      .clamp(0.0, 1.0);
                  var nearest = 0;
                  for (var i = 1; i < positions.length; i++) {
                    if ((positions[i] - ratio).abs() <
                        (positions[nearest] - ratio).abs()) {
                      nearest = i;
                    }
                  }
                  setState(() => _selected = nearest);
                },
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _TrendPainter(
                      points: points,
                      positions: positions,
                      selected: selected,
                      low: minValue,
                      high: top,
                      axisInset: axisInset,
                      color: colors.primary,
                      divider: colors.divider),
                  child: SizedBox.expand(
                      child: Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.sm),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(top.toStringAsFixed(1),
                                    style: text.bodySmall?.copyWith(
                                        color: colors.secondaryText)),
                                Text(minValue.toStringAsFixed(1),
                                    style: text.bodySmall?.copyWith(
                                        color: colors.secondaryText)),
                              ]))),
                ),
              ),
            );
          }),
        ),
        Row(children: [
          Expanded(
              child: Text(DateFormat('yy/MM/dd').format(points.first.date),
                  style: text.bodySmall)),
          if (points.length > 1)
            Text(DateFormat('yy/MM/dd').format(points.last.date),
                style: text.bodySmall),
        ]),
        DropdownButton<int>(
          isExpanded: true,
          value: selected,
          underline: const SizedBox.shrink(),
          itemHeight: null,
          onChanged: (value) => setState(() => _selected = value),
          items: [
            for (var i = 0; i < points.length; i++)
              DropdownMenuItem(
                  value: i,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                        minHeight: AppComponentSize.minTouch),
                    child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                            '${DateFormat('yyyy-MM-dd').format(points[i].date)}  ·  ${points[i].value} ${points[i].unit}',
                            style: text.bodySmall)),
                  )),
          ],
        ),
        if (point.referenceMin != null || point.referenceMax != null)
          Text(
              '该次报告范围：${point.referenceMin ?? '—'}–${point.referenceMax ?? '—'} ${point.unit}',
              style: text.bodySmall),
      ],
    );
  }

  static List<double> _positions(List<LabTrendPointModel> points) {
    final first = points.first.date.millisecondsSinceEpoch;
    final span = points.last.date.millisecondsSinceEpoch - first;
    return points
        .map((p) =>
            span == 0 ? .5 : (p.date.millisecondsSinceEpoch - first) / span)
        .toList();
  }
}

class _TrendPainter extends CustomPainter {
  const _TrendPainter(
      {required this.points,
      required this.positions,
      required this.selected,
      required this.low,
      required this.high,
      required this.axisInset,
      required this.color,
      required this.divider});
  final List<LabTrendPointModel> points;
  final List<double> positions;
  final int selected;
  final double low, high, axisInset;
  final Color color, divider;
  @override
  void paint(Canvas canvas, Size size) {
    final left = axisInset;
    const inset = AppSpacing.sm;
    final width = math.max(0.0, size.width - left - inset);
    final height = math.max(0.0, size.height - inset * 2);
    final grid = Paint()
      ..color = divider
      ..strokeWidth = 1;
    canvas.drawLine(
        Offset(left, inset), Offset(size.width - inset, inset), grid);
    canvas.drawLine(Offset(left, inset + height),
        Offset(size.width - inset, inset + height), grid);
    final pen = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final at = Offset(left + positions[i] * width,
          inset + height * (1 - (points[i].value - low) / (high - low)));
      if (i == 0) {
        path.moveTo(at.dx, at.dy);
      } else {
        path.lineTo(at.dx, at.dy);
      }
      canvas.drawCircle(at, i == selected ? 5 : 3, Paint()..color = color);
    }
    canvas.drawPath(path, pen);
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.selected != selected ||
      oldDelegate.color != color ||
      oldDelegate.divider != divider;
}
