import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../models/resource.dart';
import 'common.dart' show ResourceGridCard;

/// A section heading with an optional "See all" link, in the Home style:
/// a serif heading on the left, the link in the accent colour on the right.
class ShelfHeading extends StatelessWidget {
  const ShelfHeading(this.title, {super.key, this.onSeeAll, this.top = Gap.section});
  final String title;
  final VoidCallback? onSeeAll;
  final double top;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(top: top, bottom: Gap.snug),
      child: Row(
        children: [
          Expanded(child: Text(title, style: t.titleLarge)),
          if (onSeeAll != null)
            TextButton(
              onPressed: onSeeAll,
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              child: const Text('See all'),
            ),
        ],
      ),
    );
  }
}

/// A horizontal row of resource cards with typographic covers.
class ResourceShelf extends StatelessWidget {
  const ResourceShelf({super.key, required this.items, this.reasons = const {}});
  final List<Resource> items;

  /// Why an item is shown, by resource id ("Because you take EEE 2011").
  final Map<String, String> reasons;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: reasons.isEmpty ? 232 : 252,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: Gap.snug),
        itemBuilder: (context, i) => SizedBox(
          width: 172,
          child: ResourceGridCard(
            resource: items[i],
            coverHeight: 104,
            reason: reasons[items[i].id],
            onTap: () => context.push('/resource/${items[i].id}'),
          ),
        ),
      ),
    );
  }
}

/// A bordered panel: one number with its label, for the row of figures at
/// the top of Home, Overview and Today.
/// The colour family of a tile's icon: a tinted square with the icon in
/// the matching strong colour.
enum Tone { accent, success, warn, sky, danger }

/// (wash, strong) colours for a tone, from the theme tokens.
(Color, Color) toneColors(StudyColors c, Tone tone) => switch (tone) {
      Tone.accent => (c.accentWash, c.accent),
      Tone.success => (c.successWash, c.success),
      Tone.warn => (c.warnWash, c.warn),
      Tone.sky => (c.skyWash, c.sky),
      Tone.danger => (c.dangerWash, c.danger),
    };

/// A rounded square tinted in a tone, holding an icon.
class IconChip extends StatelessWidget {
  const IconChip(this.icon, {super.key, this.tone = Tone.accent, this.size = 36});
  final IconData icon;
  final Tone tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (wash, strong) = toneColors(StudyColors.of(context), tone);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: wash, borderRadius: BorderRadius.circular(size * 0.28)),
      child: Icon(icon, size: size * 0.52, color: strong),
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.value,
    required this.label,
    this.detail,
    this.onTap,
    this.alert = false,
    this.icon,
    this.tone = Tone.accent,
  });
  final String value;
  final String label;
  final String? detail;
  final VoidCallback? onTap;

  /// Shown in a tinted square above the number, when given.
  final IconData? icon;
  final Tone tone;

  /// Shows a small marker and the detail in the warning colour (with text,
  /// never colour alone).
  final bool alert;

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    final t = Theme.of(context).textTheme;
    return Semantics(
      button: onTap != null,
      label: '$label: $value${detail == null ? '' : ', $detail'}',
      excludeSemantics: true,
      child: Material(
        color: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.panel),
          side: BorderSide(color: c.line),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Radii.panel),
          child: Padding(
            padding: const EdgeInsets.all(Gap.snug),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[IconChip(icon!, tone: tone, size: 32), const SizedBox(height: Gap.tight)],
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Mono.of(context, size: 22, weight: FontWeight.w600, color: c.ink)
                        .copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                const SizedBox(height: 2),
                Text(label, style: t.bodySmall?.copyWith(color: c.inkSoft), maxLines: 2),
                if (detail != null) ...[
                  const SizedBox(height: 2),
                  Row(children: [
                    if (alert) ...[
                      Container(width: 6, height: 6, decoration: BoxDecoration(color: c.warn, shape: BoxShape.circle)),
                      const SizedBox(width: 4),
                    ],
                    Flexible(
                      child: Text(detail!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.bodySmall?.copyWith(color: alert ? c.warn : c.inkFaint)),
                    ),
                  ]),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Lays tiles out in a row on wide screens and two per row on phones.
class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final perRow = box.maxWidth >= 640 ? children.length : (box.maxWidth >= 380 ? 3 : 2);
      final width = (box.maxWidth - Gap.tight * (perRow - 1)) / perRow;
      return Wrap(
        spacing: Gap.tight,
        runSpacing: Gap.tight,
        children: [for (final w in children) SizedBox(width: width, child: w)],
      );
    });
  }
}

/// A bordered panel used for one block of content (an announcement, a
/// chart).
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(Gap.page - 4)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.panel),
        border: Border.all(color: c.line),
      ),
      child: child,
    );
  }
}

/// "today", "yesterday", "3 days ago".
String daysAgo(DateTime when, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final d = DateTime(n.year, n.month, n.day).difference(DateTime(when.year, when.month, when.day)).inDays;
  if (d <= 0) return 'today';
  if (d == 1) return 'yesterday';
  return '$d days ago';
}
