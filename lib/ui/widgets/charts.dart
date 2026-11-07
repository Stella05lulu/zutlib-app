import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// One bar: its label under the axis, its value, and the text a screen
/// reader hears.
class BarDatum {
  const BarDatum(this.label, this.value, {this.valueText});
  final String label;
  final double value;
  final String? valueText;
}

/// Vertical bars on a thin baseline, flat, in the accent colour. Each bar
/// shows its value above it, so nothing relies on reading the height alone.
class BarChart extends StatelessWidget {
  const BarChart({super.key, required this.data, this.maxValue, this.height = 160, this.semanticLabel, this.barWidth});
  final List<BarDatum> data;
  final double? maxValue;
  final double height;
  final String? semanticLabel;

  /// When set, each bar is this wide and the bars start at the left, so one
  /// or two bars do not stretch across the whole chart.
  final double? barWidth;

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    final top = maxValue ?? data.fold<double>(0, (m, d) => d.value > m ? d.value : m);
    final scale = top <= 0 ? 1.0 : top;
    return Semantics(
      label: semanticLabel ?? 'Bar chart',
      value: data.map((d) => '${d.label}: ${d.valueText ?? d.value.round()}').join(', '),
      excludeSemantics: true,
      child: SizedBox(
        height: height + 40,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final d in data)
              _slot(
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(d.valueText ?? '${d.value.round()}',
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          style: Mono.of(context, size: 11, color: c.inkSoft)),
                      const SizedBox(height: 2),
                      Container(
                        height: (d.value / scale * height).clamp(d.value > 0 ? 3.0 : 1.0, height),
                        decoration: BoxDecoration(
                          color: d.value > 0 ? c.accent : c.line,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                        ),
                      ),
                      Container(height: 1, color: c.lineStrong),
                      const SizedBox(height: 4),
                      Text(d.label,
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          style: Mono.of(context, size: 10.5, color: c.inkFaint)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _slot(Widget child) =>
      barWidth == null ? Expanded(child: child) : SizedBox(width: barWidth! + 6, child: child);
}

/// A labelled horizontal bar with its count, for breakdowns.
class CountBar extends StatelessWidget {
  const CountBar({super.key, required this.label, required this.count, required this.total, this.color});
  final String label;
  final int count;
  final int total;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    final t = Theme.of(context).textTheme;
    final share = total <= 0 ? 0.0 : count / total;
    return Semantics(
      label: '$label: $count',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Gap.hair + 1),
        child: Row(
          children: [
            SizedBox(width: 112, child: Text(label, style: t.bodyMedium?.copyWith(color: c.ink), maxLines: 1)),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Radii.tag),
                child: LinearProgressIndicator(
                  value: share,
                  minHeight: 8,
                  backgroundColor: c.sunken,
                  color: color ?? c.accent,
                ),
              ),
            ),
            const SizedBox(width: Gap.tight),
            SizedBox(
              width: 44,
              child: Text('$count',
                  textAlign: TextAlign.right,
                  style: Mono.of(context, size: 13, color: c.ink)
                      .copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
            ),
          ],
        ),
      ),
    );
  }
}

/// A thin line through daily values on a light grid, flat, in the accent
/// colour, with the last point marked. Day labels sit under the axis and
/// the values are read out to screen readers.
class LineChart extends StatelessWidget {
  const LineChart({super.key, required this.data, this.height = 160, this.semanticLabel});
  final List<BarDatum> data;
  final double height;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    final top = data.fold<double>(0, (m, d) => d.value > m ? d.value : m);
    // Round the top of the scale up to a tidy number so grid labels read well.
    final ceiling = top <= 4 ? 4.0 : (top / 5).ceil() * 5.0;
    return Semantics(
      label: semanticLabel ?? 'Line chart',
      value: data.map((d) => '${d.label}: ${d.valueText ?? d.value.round()}').join(', '),
      excludeSemantics: true,
      child: Column(
        children: [
          SizedBox(
            height: height,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 28,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final v in [ceiling, ceiling / 2, 0.0])
                        Text(v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1),
                            style: Mono.of(context, size: 10.5, color: c.inkFaint)),
                    ],
                  ),
                ),
                Expanded(
                  child: CustomPaint(
                    painter: _LinePainter(
                      values: [for (final d in data) d.value],
                      ceiling: ceiling,
                      line: c.accent,
                      fill: c.accentWash,
                      grid: c.line,
                      dotRing: c.surface,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Gap.tight),
          Row(children: [
            const SizedBox(width: 28),
            for (final d in data)
              Expanded(
                child: Text(d.label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: Mono.of(context, size: 10.5, color: c.inkFaint)),
              ),
          ]),
        ],
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.values,
    required this.ceiling,
    required this.line,
    required this.fill,
    required this.grid,
    required this.dotRing,
  });
  final List<double> values;
  final double ceiling;
  final Color line, fill, grid, dotRing;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final f in [0.0, 0.5, 1.0]) {
      final y = (size.height - 1) * f + 0.5;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    if (values.isEmpty) return;
    // One point in the middle of each day's column, so it lines up with the
    // labels underneath.
    final step = size.width / values.length;
    final pts = [
      for (var i = 0; i < values.length; i++)
        Offset(step * (i + 0.5), size.height - (values[i] / ceiling).clamp(0.0, 1.0) * (size.height - 4) - 2),
    ];
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    final area = Path.from(path)
      ..lineTo(pts.last.dx, size.height)
      ..lineTo(pts.first.dx, size.height)
      ..close();
    canvas.drawPath(area, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(pts.last, 5, Paint()..color = dotRing);
    canvas.drawCircle(pts.last, 3.5, Paint()..color = line);
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.values != values || old.ceiling != ceiling || old.line != line || old.fill != fill;
}
