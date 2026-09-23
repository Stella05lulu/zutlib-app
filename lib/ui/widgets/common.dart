import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../models/borrow_request.dart';
import '../../models/resource.dart';

final dateFmt = DateFormat('d MMM yyyy');
final dateTimeFmt = DateFormat('d MMM yyyy, HH:mm');

/// State reads as a small bold badge, not an icon a person has to decode —
/// the same small-caps tag treatment as a catalogue's "Bestseller" label.
class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key, this.dense = false});
  final BorrowStatus status;
  final bool dense;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(
            horizontal: dense ? 8 : 11, vertical: dense ? 3 : 5),
        decoration: BoxDecoration(
          color: status.bg,
          borderRadius: BorderRadius.circular(Corners.chip),
        ),
        child: Text(status.label.toUpperCase(),
            style: TextStyle(
              color: status.fg,
              fontWeight: FontWeight.w800,
              fontSize: dense ? 11 : 12,
              letterSpacing: 0.3,
            )),
      );
}

class MetaLine extends StatelessWidget {
  const MetaLine(this.parts, {super.key});
  final List<String> parts;

  @override
  Widget build(BuildContext context) => Text(
        parts.where((p) => p.trim().isNotEmpty).join('  ·  '),
        style: Theme.of(context).textTheme.bodySmall,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
}

IconData resourceTypeIcon(ResourceType type) => switch (type) {
      ResourceType.pastPaper => Icons.assignment_outlined,
      ResourceType.testPaper => Icons.quiz_outlined,
      ResourceType.lectureNotes => Icons.description_outlined,
      ResourceType.bookLink => Icons.menu_book_outlined,
    };

class TypeBadge extends StatelessWidget {
  const TypeBadge(this.type, {super.key});
  final ResourceType type;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42, width: 42,
      decoration: BoxDecoration(
        color: Palette.blueWash,
        borderRadius: BorderRadius.circular(Corners.field),
      ),
      child: Icon(resourceTypeIcon(type), size: 21, color: Palette.blueDeep),
    );
  }
}

/// Mirrors a catalogue's own responsive grid: one column on a phone, more
/// as the viewport widens, never so many that a tile gets too cramped to
/// read.
int catalogGridColumns(double width) {
  if (width >= 1300) return 4;
  if (width >= 980) return 3;
  if (width >= 680) return 2;
  return 1;
}

/// Blue-family gradient per resource type, standing in for course cover art.
List<Color> resourceTypeGradient(ResourceType type) => switch (type) {
      ResourceType.pastPaper => const [Color(0xFF3B82F6), Color(0xFF1E3A8A)],
      ResourceType.testPaper => const [Color(0xFF0EA5E9), Color(0xFF0C4A6E)],
      ResourceType.lectureNotes => const [Color(0xFF6366F1), Color(0xFF312E81)],
      ResourceType.bookLink => const [Color(0xFF14B8A6), Color(0xFF1E40AF)],
    };

/// Udemy-style tile: a rounded gradient "cover" with the course code as a
/// big watermark, then a bold title, meta and availability on the page
/// background with no card border. `overlayAction` sits in the cover's top
/// right corner for a management action (e.g. remove).
class ResourceGridCard extends StatelessWidget {
  const ResourceGridCard({
    super.key,
    required this.resource,
    required this.onTap,
    this.overlayAction,
    this.coverHeight = 118,
  });

  final Resource resource;
  final VoidCallback onTap;
  final Widget? overlayAction;
  final double coverHeight;

  @override
  Widget build(BuildContext context) {
    final available = !resource.isPhysical || resource.availableCopies > 0;
    final colors = resourceTypeGradient(resource.type);

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                height: coverHeight,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: colors,
                          ),
                        ),
                      ),
                    ),
                    // Soft light spot for depth.
                    Positioned(
                      top: -40, left: -30,
                      child: Container(
                        width: 140, height: 140,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(colors: [
                            Colors.white.withValues(alpha: 0.28),
                            Colors.white.withValues(alpha: 0.0),
                          ]),
                        ),
                      ),
                    ),
                    Positioned(
                      right: -4, bottom: -12,
                      child: Text(
                        resource.courseCode,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 46,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1.5,
                          color: Colors.white.withValues(alpha: 0.16),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 12, top: 12,
                      child: Container(
                        height: 36, width: 36,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.35)),
                        ),
                        child: Icon(resourceTypeIcon(resource.type),
                            size: 19, color: Colors.white),
                      ),
                    ),
                    Positioned(
                      left: 12, bottom: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.28),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(resource.type.label.toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                            )),
                      ),
                    ),
                    if (overlayAction != null)
                      Positioned(right: 6, top: 6, child: overlayAction!),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(resource.title,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          height: 1.25,
                          letterSpacing: -0.1,
                          color: Palette.ink,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    MetaLine([
                      resource.department,
                      '${resource.academicYear}',
                      if (resource.semester != null) 'Sem ${resource.semester}',
                    ]),
                    const Spacer(),
                    Row(
                      children: [
                        if (resource.isPhysical && available) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: Palette.highlight,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text('In library',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: Palette.onHighlight,
                                )),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Icon(
                          available
                              ? Icons.check_circle_rounded
                              : Icons.schedule_rounded,
                          size: 14,
                          color: available ? Palette.good : Palette.warn,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            resource.isPhysical
                                ? resource.availabilityLabel
                                : 'Digital copy',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: available ? Palette.good : Palette.warn,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small circular button meant to overlay a [ResourceGridCard]'s
/// thumbnail — a light scrim behind the icon keeps it legible regardless
/// of the thumbnail colour under it.
class CardOverlayButton extends StatelessWidget {
  const CardOverlayButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.color,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Palette.surface.withValues(alpha: 0.88),
          shape: BoxShape.circle,
        ),
        child: IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          icon: Icon(icon, size: 18, color: color ?? Palette.ink),
          padding: const EdgeInsets.all(6),
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          visualDensity: VisualDensity.compact,
        ),
      );
}

/// Constrains reading width on large screens. Long measure is the fastest
/// way to make a desktop layout feel unconsidered.
class Readable extends StatelessWidget {
  const Readable({super.key, required this.child, this.maxWidth = 780});
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      );
}

class SectionHeading extends StatelessWidget {
  const SectionHeading(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Insets.sm, top: Insets.lg),
        child: Row(
          children: [
            Expanded(
                child: Text(text,
                    style: Theme.of(context).textTheme.titleMedium)),
            if (trailing != null) trailing!,
          ],
        ),
      );
}

void showMessage(BuildContext context, String message, {bool isError = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: isError ? Palette.bad : Palette.ink,
      duration: Duration(seconds: isError ? 5 : 3),
    ));
}
