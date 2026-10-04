import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import 'app_components.dart';

/// A display point, not a derived health metric or prediction.
class AppTrendPoint {
  const AppTrendPoint(this.date, this.value);
  final DateTime date;
  final double value;
}

class AppTrendChart extends StatefulWidget {
  const AppTrendChart({super.key, required this.points, required this.unit});
  final List<AppTrendPoint> points;
  final String unit;
  @override
  State<AppTrendChart> createState() => _AppTrendChartState();
}

class _AppTrendChartState extends State<AppTrendChart> {
  DateTime? _selectedDate;
  @override
  Widget build(BuildContext context) {
    final points = widget.points.where((p) => p.value.isFinite).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    if (points.isEmpty) return const Text('暂无可比较的已保存记录');
    final found = points.indexWhere((p) => p.date == _selectedDate);
    final selected = found < 0 ? points.length - 1 : found;
    final colors = AppColors.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Semantics(
          label: '历史趋势，共 ${points.length} 个记录点。下方可选择每次记录的日期和数值。',
          child: ExcludeSemantics(
              child: SizedBox(
                  height: 132 * MediaQuery.textScalerOf(context).scale(1),
                  width: double.infinity,
                  child: CustomPaint(
                      painter: _HistoryPainter(
                          points, colors.primary, colors.divider, selected))))),
      Wrap(spacing: 20, children: [
        Text(AppFormat.date(points.first.date), style: AppTypography.caption),
        if (points.length > 1)
          Text(AppFormat.date(points.last.date), style: AppTypography.caption),
      ]),
      DropdownButton<int>(
          isExpanded: true,
          itemHeight: null,
          value: selected,
          underline: const SizedBox.shrink(),
          onChanged: (value) {
            if (value != null) {
              setState(() => _selectedDate = points[value].date);
            }
          },
          items: [
            for (var i = 0; i < points.length; i++)
              DropdownMenuItem(
                  value: i,
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 44),
                      child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                              '${points[i].date.year}年${AppFormat.date(points[i].date)} · ${AppFormat.number(points[i].value, decimals: 1)} ${widget.unit}',
                              style: AppTypography.secondary)))),
          ]),
      if (points.length == 1)
        const Text('目前只有一次记录，暂不能判断趋势。', style: AppTypography.caption),
    ]);
  }
}

class _HistoryPainter extends CustomPainter {
  const _HistoryPainter(this.points, this.color, this.divider, this.selected);
  final List<AppTrendPoint> points;
  final Color color, divider;
  final int selected;
  @override
  void paint(Canvas canvas, Size size) {
    const inset = 8.0;
    final low = math.min(0.0, points.map((p) => p.value).reduce(math.min));
    final top =
        math.max(low + 1, points.map((p) => p.value).reduce(math.max) * 1.15);
    final first = points.first.date.millisecondsSinceEpoch;
    final span = points.last.date.millisecondsSinceEpoch - first;
    final width = math.max(0.0, size.width - 2 * inset);
    final height = math.max(0.0, size.height - 2 * inset);
    final grid = Paint()..color = divider;
    for (final y in [inset, inset + height]) {
      canvas.drawLine(Offset(inset, y), Offset(inset + width, y), grid);
    }
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = span == 0
          ? .5
          : (points[i].date.millisecondsSinceEpoch - first) / span;
      final at = Offset(inset + x * width,
          inset + height * (1 - (points[i].value - low) / (top - low)));
      if (i == 0) {
        path.moveTo(at.dx, at.dy);
      } else {
        path.lineTo(at.dx, at.dy);
      }
      canvas.drawCircle(at, i == selected ? 5 : 3, Paint()..color = color);
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(covariant _HistoryPainter oldDelegate) => true;
}
