import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../models/profile.dart';
import '../../state/providers.dart';
import '../../data/offline_cache.dart';
import '../../services/reminders.dart';
import 'brand.dart';

class NavTarget {
  const NavTarget(this.path, this.label, this.icon, this.activeIcon);
  final String path, label;
  final IconData icon, activeIcon;
}

// Each role sees only its own areas. The router and the database enforce
// the same split; these lists only decide which tabs are drawn.
const _studentNav = [
  NavTarget('/browse', 'Explore', Icons.explore_outlined, Icons.explore_rounded),
  NavTarget('/borrowing', 'My borrowing', Icons.auto_stories_outlined, Icons.auto_stories_rounded),
  NavTarget('/study', 'Study', Icons.school_outlined, Icons.school_rounded),
  NavTarget('/plan', 'Plan', Icons.event_note_outlined, Icons.event_note_rounded),
  NavTarget('/profile', 'Account', Icons.account_circle_outlined, Icons.account_circle_rounded),
];

const _staffNav = [
  NavTarget('/staff/requests', 'Requests', Icons.inbox_outlined, Icons.inbox_rounded),
  NavTarget('/staff/library', 'Library', Icons.local_library_outlined, Icons.local_library_rounded),
  NavTarget('/browse', 'Catalogue', Icons.explore_outlined, Icons.explore_rounded),
  NavTarget('/profile', 'Account', Icons.account_circle_outlined, Icons.account_circle_rounded),
];

const _adminNav = [
  NavTarget('/admin', 'Dashboard', Icons.space_dashboard_outlined, Icons.space_dashboard_rounded),
  NavTarget('/admin/users', 'Users', Icons.group_outlined, Icons.group_rounded),
  NavTarget('/staff/requests', 'Requests', Icons.inbox_outlined, Icons.inbox_rounded),
  NavTarget('/staff/library', 'Library', Icons.local_library_outlined, Icons.local_library_rounded),
  NavTarget('/profile', 'Account', Icons.account_circle_outlined, Icons.account_circle_rounded),
];

/// Below the breakpoint the destinations sit in a bottom bar; above it they
/// move to a rail with the institution's mark. Same widget, same routes.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).valueOrNull;
    final roleTargets = switch (profile?.role) {
      UserRole.admin => _adminNav,
      UserRole.librarian => _staffNav,
      _ => _studentNav,
    };
    final targets = roleTargets;
    // Students: keep the phone's study and due-date reminders up to date.
    if (profile?.role == UserRole.student) ref.watch(remindersSyncProvider);

    // The tab whose path matches most of the location ("/admin/users"
    // picks Users, not Dashboard).
    final location = GoRouterState.of(context).uri.path;
    var index = 0;
    var best = -1;
    for (var i = 0; i < targets.length; i++) {
      final p = targets[i].path;
      if ((location == p || location.startsWith('$p/')) && p.length > best) {
        best = p.length;
        index = i;
      }
    }

    void go(int i) => context.go(targets[i].path);

    // Notifications live in the bell at the top of each screen, so the tabs
    // are plain icons.
    Widget icon(NavTarget t, {required bool selected}) => Icon(selected ? t.activeIcon : t.icon);
    String tooltip(NavTarget t) => t.label;

    // A thin strip while a screen shows its saved copy instead of fresh data.
    final page = ValueListenableBuilder<bool>(
      valueListenable: OfflineCache.offline,
      builder: (context, offline, _) => Column(
        children: [
          if (offline)
            Material(
              color: Palette.warnWash,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Insets.md, vertical: Insets.sm),
                  child: Row(
                    children: [
                      Icon(Icons.cloud_off_outlined, size: 18, color: Palette.warn),
                      const SizedBox(width: Insets.sm),
                      Expanded(
                        child: Text('Offline: showing your saved copy. Changes need a connection.',
                            style: TextStyle(color: Palette.warn, fontWeight: FontWeight.w600, fontSize: 13)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Expanded(child: child),
        ],
      ),
    );

    final wide = MediaQuery.sizeOf(context).width >= kWideBreakpoint;

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            _Rail(
              targets: targets,
              index: index,
              onSelect: go,
              profile: profile,
              icon: icon,
            ),
            const VerticalDivider(width: 1),
            Expanded(child: page),
          ],
        ),
      );
    }

    // A standard bottom bar with a label under every icon: nothing to
    // guess, and the page above it never hides behind it.
    return Scaffold(
      body: page,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: Palette.line))),
        child: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: go,
          destinations: [
            for (final t in targets)
              NavigationDestination(
                icon: icon(t, selected: false),
                selectedIcon: icon(t, selected: true),
                label: t.label,
                tooltip: tooltip(t),
              ),
          ],
        ),
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({
    required this.targets,
    required this.index,
    required this.onSelect,
    required this.profile,
    required this.icon,
  });

  final List<NavTarget> targets;
  final int index;
  final ValueChanged<int> onSelect;
  final Profile? profile;
  final Widget Function(NavTarget, {required bool selected}) icon;

  @override
  Widget build(BuildContext context) {
    final extended = MediaQuery.sizeOf(context).width >= 1180;
    return Container(
      color: Palette.surface,
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: MediaQuery.sizeOf(context).height,
          ),
          child: IntrinsicHeight(
            child: NavigationRail(
              extended: extended,
              minExtendedWidth: 216,
              selectedIndex: index,
              onDestinationSelected: onSelect,
              labelType: extended ? NavigationRailLabelType.none : NavigationRailLabelType.all,
              leading: Padding(
                padding: const EdgeInsets.fromLTRB(Insets.sm, Insets.lg, Insets.sm, Insets.lg),
                child: Column(
                  crossAxisAlignment:
                      extended ? CrossAxisAlignment.start : CrossAxisAlignment.center,
                  children: [
                    ZutLibLogo(height: 30, showName: extended),
                    if (profile != null && extended) ...[
                      const SizedBox(height: Insets.sm),
                      Text(profile!.role.label,
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
              destinations: [
                for (final t in targets)
                  NavigationRailDestination(
                    icon: icon(t, selected: false),
                    selectedIcon: icon(t, selected: true),
                    label: Text(t.label),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
