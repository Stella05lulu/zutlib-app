import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import 'notification_bell.dart';

/// One part of a tab: Study has Kits, Plan and Progress; Explore has
/// Browse and Saved. Each part is its own page, so links and the back
/// button work, and the tab stays lit on all of them.
class SectionTab {
  const SectionTab(this.label, this.path, this.icon);
  final String label, path;
  final IconData icon;
}

const studySections = [
  SectionTab('Kits', '/study', Icons.school_outlined),
  SectionTab('Plan', '/plan', Icons.event_note_outlined),
  SectionTab('Progress', '/progress', Icons.insights_outlined),
];

const exploreSections = [
  SectionTab('Browse', '/browse', Icons.explore_outlined),
  SectionTab('Saved', '/saved', Icons.bookmark_border),
];

/// The top of a tab's page: its name and the bell, then the switch between
/// its parts.
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.sections = const []});
  final String title;
  final List<SectionTab> sections;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [
          Expanded(child: Text(title, style: t.headlineSmall?.copyWith(fontSize: 28, fontWeight: FontWeight.w700))),
          const NotificationBell(),
        ]),
        if (sections.isNotEmpty) ...[
          const SizedBox(height: Gap.snug),
          SectionSwitch(sections),
        ],
      ],
    );
  }
}

/// A row of pill buttons, one per part; the current one is filled.
class SectionSwitch extends StatelessWidget {
  const SectionSwitch(this.sections, {super.key});
  final List<SectionTab> sections;

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    final t = Theme.of(context).textTheme;
    final location = GoRouterState.of(context).uri.path;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.sunken,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.line),
      ),
      child: Row(children: [
        for (final s in sections)
          Expanded(
            child: Builder(builder: (context) {
              final on = location == s.path;
              return Semantics(
                button: true,
                selected: on,
                label: s.label,
                excludeSemantics: true,
                child: Material(
                  color: on ? c.surface : Colors.transparent,
                  elevation: on ? 1 : 0,
                  shadowColor: c.line,
                  borderRadius: BorderRadius.circular(999),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: on ? null : () => context.go(s.path),
                    child: SizedBox(
                      height: 40,
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(s.icon, size: 18, color: on ? c.accent : c.inkSoft),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(s.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.labelLarge?.copyWith(
                                  color: on ? c.ink : c.inkSoft, fontWeight: on ? FontWeight.w700 : FontWeight.w500)),
                        ),
                      ]),
                    ),
                  ),
                ),
              );
            }),
          ),
      ]),
    );
  }
}
