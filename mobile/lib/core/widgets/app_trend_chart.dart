import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import 'app_components.dart';

/// Actual display points. Labels/annotations retain domain precision.
class AppTrendPoint {
  const AppTrendPoint(this.date, this.value, {this.valueText, this.annotation});
  final DateTime date;
  final double value;
  final String? valueText, annotation;
}

bool _samePoints(List<AppTrendPoint> a, List<AppTrendPoint> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].date != b[i].date ||
        a[i].value != b[i].value ||
        a[i].valueText != b[i].valueText ||
        a[i].annotation != b[i].annotation) {
      return false;
    }
  }
  return true;
}

/// Shared geometry, accessible picker and tap selection; no prediction.
class AppTrendChart extends StatefulWidget {
  const AppTrendChart(
      {super.key,
      required this.points,
      required this.unit,
      this.label = '历史趋势'});
  final List<AppTrendPoint> points;
  final String unit, label;
  @override
  State<AppTrendChart> createState() => _AppTrendChartState();
}

class _AppTrendChartState extends State<AppTrendChart> {
  int? _selected;
  @override
  void didUpdateWidget(covariant AppTrendChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_samePoints(oldWidget.points, widget.points)) _selected = null;
  }

  @override
  Widget build(BuildContext context) {
    final points = widget.points.where((p) => p.value.isFinite).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    if (points.isEmpty) return const Text('暂无可比较的已保存记录');
    final selected =
        (_selected ?? points.length - 1).clamp(0, points.length - 1);
    final colors = AppColors.of(context);
    final low = math.min(0.0, points.map((p) => p.value).reduce(math.min));
    final maximum =
        math.max(low + 1, points.map((p) => p.value).reduce(math.max));
    final high = maximum + (maximum - low) * .15;
    final first = points.first.date.millisecondsSinceEpoch;
    final span = points.last.date.millisecondsSinceEpoch - first;
    final positions = points
        .map((p) =>
            span == 0 ? .5 : (p.date.millisecondsSinceEpoch - first) / span)
        .toList();
    final scaler = MediaQuery.textScalerOf(context);
    final axisStyle =
        AppTypography.caption.copyWith(color: colors.secondaryText);
    double labelWidth(String value) {
      final painter = TextPainter(
          text: TextSpan(text: value, style: axisStyle),
          textDirection: Directionality.of(context),
          textScaler: scaler)
        ..layout();
      return painter.width;
    }

    final axisInset = math.max(
        32.0,
        math.max(labelWidth(low.toStringAsFixed(1)),
                labelWidth(high.toStringAsFixed(1))) +
            12);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
          height: AppComponentSize.chart * scaler.scale(1),
          child: LayoutBuilder(
              builder: (context, constraints) => Semantics(
                  label:
                      '${widget.label}趋势图，纵轴 ${low.toStringAsFixed(1)} 至 ${high.toStringAsFixed(1)} ${widget.unit}；横轴按真实日期排列，下方可选择每次记录读取数值。',
                  child: GestureDetector(
                      onTapDown: (details) {
                        final ratio = ((details.localPosition.dx - axisInset) /
                                math.max(
                                    1.0, constraints.maxWidth - axisInset - 8))
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
                      child: ExcludeSemantics(
                          child: CustomPaint(
                              painter: _HistoryPainter(
                                  points,
                                  positions,
                                  colors.primary,
                                  colors.divider,
                                  selected,
                                  low,
                                  high,
                                  axisInset),
                              child: SizedBox.expand(
                                  child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 8),
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(high.toStringAsFixed(1),
                                                style: axisStyle),
                                            Text(low.toStringAsFixed(1),
                                                style: axisStyle),
                                          ]))))))))),
      Wrap(spacing: 20, children: [
        Text(AppFormat.fullDate(points.first.date), style: axisStyle),
        if (points.length > 1)
          Text(AppFormat.fullDate(points.last.date), style: axisStyle),
      ]),
      DropdownButton<int>(
          isExpanded: true,
          itemHeight: null,
          value: selected,
          underline: const SizedBox.shrink(),
          onChanged: (value) {
            if (value != null) setState(() => _selected = value);
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
                              '${AppFormat.fullDate(points[i].date)}  ·  ${points[i].valueText ?? AppFormat.number(points[i].value, decimals: 1)} ${widget.unit}',
                              style: AppTypography.secondary))))
          ]),
      if (points[selected].annotation case final annotation?)
        Text(annotation, style: AppTypography.caption),
      if (points.length == 1)
        const Text('目前只有一次记录，暂不能判断趋势。', style: AppTypography.caption),
    ]);
  }
}

class _HistoryPainter extends CustomPainter {
  const _HistoryPainter(this.points, this.positions, this.color, this.divider,
      this.selected, this.low, this.high, this.axisInset);
  final List<AppTrendPoint> points;
  final List<double> positions;
  final Color color, divider;
  final int selected;
  final double low, high, axisInset;
  @override
  void paint(Canvas canvas, Size size) {
    const inset = 8.0;
    final width = math.max(0.0, size.width - axisInset - inset);
    final height = math.max(0.0, size.height - 2 * inset);
    final grid = Paint()
      ..color = divider
      ..strokeWidth = 1;
    for (final y in [inset, inset + height]) {
      canvas.drawLine(Offset(axisInset, y), Offset(axisInset + width, y), grid);
    }
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final at = Offset(axisInset + positions[i] * width,
          inset + height * (1 - (points[i].value - low) / (high - low)));
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
  bool shouldRepaint(covariant _HistoryPainter oldDelegate) =>
      !_samePoints(oldDelegate.points, points) ||
      oldDelegate.selected != selected ||
      oldDelegate.color != color ||
      oldDelegate.divider != divider ||
      oldDelegate.axisInset != axisInset ||
      oldDelegate.low != low ||
      oldDelegate.high != high;
}
