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
    // Master drawing on a 256 grid; the bookmark spans x 64..192, y 24..232.
    final s = size.height / 208;
    Offset p(double x, double y) => Offset((x - 64) * s, (y - 24) * s);

    final path = Path()..fillType = PathFillType.evenOdd;
    // The bookmark: a tall strip with a 30 degree notch at the foot.
    path
      ..moveTo(p(64, 24).dx, p(64, 24).dy)
      ..lineTo(p(192, 24).dx, p(192, 24).dy)
      ..lineTo(p(192, 232).dx, p(192, 232).dy)
      ..lineTo(p(128, 195).dx, p(128, 195).dy)
      ..lineTo(p(64, 232).dx, p(64, 232).dy)
      ..close();
    // The Z, cut out.
    const z = [
      [90.0, 62.0], [166.0, 62.0], [166.0, 88.0], [128.0, 126.0], [166.0, 126.0],
      [166.0, 152.0], [90.0, 152.0], [90.0, 126.0], [128.0, 88.0], [90.0, 88.0],
    ];
    path.moveTo(p(z[0][0], z[0][1]).dx, p(z[0][0], z[0][1]).dy);
    for (final pt in z.skip(1)) {
      final o = p(pt[0], pt[1]);
      path.lineTo(o.dx, o.dy);
    }
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
