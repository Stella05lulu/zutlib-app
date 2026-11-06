import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// The ZutLib mark: a bookmark with a Z cut through it ("ZutLib keeps your
/// place"). Drawn from the same geometry as the master SVG in
/// docs/brand/zutlib-symbol.svg, so it stays sharp at every size and
/// needs no image package.
class ZutLibMark extends StatelessWidget {
  const ZutLibMark({super.key, this.height = 32, this.color});

  /// Height of the bookmark. The width follows (the mark is 128 by 208).
  final double height;

  /// Fill colour; the app's blue by default.
  final Color? color;

  static const double _aspect = 128 / 208;

  @override
  Widget build(BuildContext context) {
    final fill = color ?? StudyColors.of(context).accent;
    return Semantics(
      label: 'ZutLib',
      image: true,
      child: SizedBox(
        width: height * _aspect,
        height: height,
        child: CustomPaint(painter: _MarkPainter(fill)),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Master drawing on a 256 grid, every point on an 8 px grid (made by
    // docs/brand/build_brand.py). The bookmark spans x 64..192, y 24..232.
    final s = size.height / 208;
    Offset p(double x, double y) => Offset((x - 64) * s, (y - 24) * s);
    final r = Radius.circular(6 * s);
    final path = Path()..fillType = PathFillType.evenOdd;
    void to(double x, double y) => path.lineTo(p(x, y).dx, p(x, y).dy);
    void arc(double x, double y) => path.arcToPoint(p(x, y), radius: r);

    // The bookmark: rounded top corners, a sharp notch 24 deep at the foot
    // (the same as the Z's stroke).
    path.moveTo(p(70, 24).dx, p(70, 24).dy);
    to(186, 24);
    arc(192, 30);
    to(192, 232);
    to(128, 208);
    to(64, 232);
    to(64, 30);
    arc(70, 24);
    path.close();

    // The Z, cut out: three 24 px strokes, outer corners rounded, set a
    // little above centre so it looks centred despite the notch.
    path.moveTo(p(94, 56).dx, p(94, 56).dy);
    to(162, 56);
    arc(168, 62);
    to(168, 80);
    to(120, 136);
    to(168, 136);
    to(168, 154);
    arc(162, 160);
    to(94, 160);
    arc(88, 154);
    to(88, 136);
    to(136, 80);
    to(88, 80);
    to(88, 62);
    arc(94, 56);
    path.close();

    canvas.drawPath(path, Paint()..color = color..isAntiAlias = true);
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.color != color;
}

/// The mark with the name beside it, for the sign-in screens and the side
/// rail.
class ZutLibLogo extends StatelessWidget {
  const ZutLibLogo({super.key, this.height = 30, this.showName = true});

  final double height;
  final bool showName;

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    final t = Theme.of(context).textTheme;
    if (!showName) return ZutLibMark(height: height);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ZutLibMark(height: height),
        SizedBox(width: height * 0.36),
        Text(
          'ZutLib',
          style: t.titleLarge?.copyWith(
            fontSize: height * 0.66,
            fontWeight: FontWeight.w600,
            color: c.ink,
            height: 1,
          ),
        ),
      ],
    );
  }
}
