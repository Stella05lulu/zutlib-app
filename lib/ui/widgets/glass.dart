import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme.dart';

/// Canvas with three soft glows placed on a clear diagonal rhythm (top
/// right, middle left, bottom right), sized from the screen so the layout
/// looks the same on every phone. A light wash down from the top gives it a
/// designed, tidy feel.
class GlassBackground extends StatelessWidget {
  const GlassBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Palette.isDark;
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      final h = box.maxHeight.isFinite ? box.maxHeight : 800.0;
      final d = (w * 0.95).clamp(280.0, 560.0);

      Widget orb(double cx, double cy, double size, Color color, double a) =>
          Positioned(
            left: cx - size / 2,
            top: cy - size / 2,
            width: size,
            height: size,
            child: _Orb(color: color, alpha: a),
          );

      return Stack(
        children: [
          Positioned.fill(child: ColoredBox(color: Palette.canvas)),
          // Light wash from the top edge.
          Positioned(
            left: 0, right: 0, top: 0, height: h * 0.45,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Palette.blue.withValues(alpha: dark ? 0.14 : 0.08),
                      Palette.blue.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          orb(w * 0.92, h * 0.08, d, Palette.blue, dark ? 0.42 : 0.30),
          orb(w * 0.04, h * 0.55, d * 0.8, Palette.violet, dark ? 0.30 : 0.18),
          orb(w * 0.96, h * 0.96, d * 0.7, Palette.teal, dark ? 0.24 : 0.16),
          Positioned.fill(child: child),
        ],
      );
    });
  }
}

class _Orb extends StatelessWidget {
  const _Orb({required this.color, required this.alpha});
  final Color color;
  final double alpha;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              stops: const [0.0, 0.45, 1.0],
              colors: [
                color.withValues(alpha: alpha),
                color.withValues(alpha: alpha * 0.45),
                color.withValues(alpha: 0.0),
              ],
            ),
          ),
        ),
      );
}

/// Frosted panel: blur what is behind, tint it (white in light mode, smoky
/// in dark mode), and edge it with a thin bright border and a soft shadow.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Insets.lg),
    this.radius = Corners.card,
    this.blur = 22,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double blur;

  @override
  Widget build(BuildContext context) {
    final dark = Palette.isDark;
    final r = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: [
          BoxShadow(
            color: (dark ? Colors.black : Palette.blueDeep)
                .withValues(alpha: dark ? 0.45 : 0.10),
            blurRadius: 32,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: r,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: r,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: dark
                    ? [
                        const Color(0xFF2A2A34).withValues(alpha: 0.62),
                        const Color(0xFF15151B).withValues(alpha: 0.48),
                      ]
                    : [
                        Colors.white.withValues(alpha: 0.78),
                        Colors.white.withValues(alpha: 0.52),
                      ],
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: dark ? 0.14 : 0.85),
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class GlassNavItem {
  const GlassNavItem(this.label, this.icon, this.activeIcon);
  final String label;
  final IconData icon, activeIcon;
}

/// Floating frosted pill with a sliding glass bubble behind the selected
/// icon. Icons only, like the reference app; the label shows as a tooltip
/// and is read out by screen readers.
class GlassNavBar extends StatelessWidget {
  const GlassNavBar({
    super.key,
    required this.items,
    required this.index,
    required this.onSelect,
  });

  final List<GlassNavItem> items;
  final int index;
  final ValueChanged<int> onSelect;

  static const double height = 68;

  @override
  Widget build(BuildContext context) {
    final dark = Palette.isDark;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: GlassCard(
          radius: height / 2,
          blur: 26,
          padding: const EdgeInsets.all(6),
          child: SizedBox(
            height: height - 12,
            child: LayoutBuilder(builder: (context, box) {
              final w = box.maxWidth / items.length;
              return Stack(
                children: [
                  // The sliding bubble.
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 420),
                    curve: Curves.easeOutBack,
                    left: w * index,
                    top: 0,
                    bottom: 0,
                    width: w,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(height / 2),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              const Color(0xFF3B82F6).withValues(alpha: dark ? 0.55 : 0.28),
                              const Color(0xFF1D4ED8).withValues(alpha: dark ? 0.30 : 0.12),
                            ],
                          ),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: dark ? 0.22 : 0.9),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Palette.blue.withValues(alpha: dark ? 0.35 : 0.22),
                              blurRadius: 18,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (var i = 0; i < items.length; i++)
                        Expanded(child: _NavButton(
                          item: items[i],
                          selected: i == index,
                          onTap: () {
                            if (i != index) HapticFeedback.selectionClick();
                            onSelect(i);
                          },
                        )),
                    ],
                  ),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.item, required this.selected, required this.onTap});
  final GlassNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: Tooltip(
        message: item.label,
        child: InkResponse(
          onTap: onTap,
          radius: 30,
          child: Center(
            child: AnimatedScale(
              scale: selected ? 1.12 : 1.0,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              child: Icon(
                selected ? item.activeIcon : item.icon,
                size: 26,
                color: selected
                    ? (Palette.isDark ? Colors.white : Palette.blueDeep)
                    : Palette.inkSoft,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
