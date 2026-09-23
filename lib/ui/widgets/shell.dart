import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../models/profile.dart';
import '../../state/providers.dart';
import 'glass.dart';

class NavTarget {
  const NavTarget(this.path, this.label, this.icon, this.activeIcon);
  final String path, label;
  final IconData icon, activeIcon;
}

const _studentNav = [
  NavTarget('/browse', 'Explore', Icons.explore_outlined, Icons.explore_rounded),
  NavTarget('/borrowing', 'My borrowing', Icons.auto_stories_outlined, Icons.auto_stories_rounded),
  NavTarget('/profile', 'Account', Icons.account_circle_outlined, Icons.account_circle_rounded),
];

const _staffNav = [
  NavTarget('/staff/requests', 'Requests', Icons.inbox_outlined, Icons.inbox_rounded),
  NavTarget('/staff/resources', 'Resources', Icons.folder_outlined, Icons.folder_rounded),
  NavTarget('/profile', 'Account', Icons.account_circle_outlined, Icons.account_circle_rounded),
];

const _adminNav = [
  NavTarget('/admin/roll', 'Student roll', Icons.badge_outlined, Icons.badge_rounded),
  NavTarget('/admin/users', 'Users', Icons.group_outlined, Icons.group_rounded),
  NavTarget('/staff/requests', 'Requests', Icons.inbox_outlined, Icons.inbox_rounded),
  NavTarget('/staff/resources', 'Resources', Icons.folder_outlined, Icons.folder_rounded),
  NavTarget('/profile', 'Account', Icons.account_circle_outlined, Icons.account_circle_rounded),
];

/// Below the breakpoint the destinations sit in a bottom bar; above it they
/// move to a rail with the institution's mark. Same widget, same routes.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).value;
    final targets = switch (profile?.role) {
      UserRole.admin => _adminNav,
      UserRole.librarian => _staffNav,
      _ => _studentNav,
    };

    final location = GoRouterState.of(context).uri.path;
    var index = targets.indexWhere((t) => location.startsWith(t.path));
    if (index < 0) index = 0;

    void go(int i) => context.go(targets[i].path);

    final wide = MediaQuery.sizeOf(context).width >= kWideBreakpoint;

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            _Rail(targets: targets, index: index, onSelect: go, profile: profile),
            const VerticalDivider(width: 1),
            Expanded(child: child),
          ],
        ),
      );
    }

    // The bar floats over the content, so pages scroll underneath the glass.
    return Scaffold(
      extendBody: true,
      body: child,
      bottomNavigationBar: GlassNavBar(
        index: index,
        onSelect: go,
        items: [
          for (final t in targets) GlassNavItem(t.label, t.icon, t.activeIcon),
        ],
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
  });

  final List<NavTarget> targets;
  final int index;
  final ValueChanged<int> onSelect;
  final Profile? profile;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Palette.surface,
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: MediaQuery.sizeOf(context).height,
          ),
          child: IntrinsicHeight(
            child: NavigationRail(
              extended: MediaQuery.sizeOf(context).width >= 1180,
              minExtendedWidth: 208,
              selectedIndex: index,
              onDestinationSelected: onSelect,
              leading: Padding(
                padding: const EdgeInsets.fromLTRB(0, Insets.lg, 0, Insets.lg),
                child: Column(
                  children: [
                    Container(
                      height: 38, width: 38,
                      decoration: BoxDecoration(
                        gradient: Palette.accentGradient,
                        borderRadius: BorderRadius.circular(Corners.field),
                      ),
                      alignment: Alignment.center,
                      child: Text('ZL',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            letterSpacing: -0.3,
                          )),
                    ),
                    if (profile != null &&
                        MediaQuery.sizeOf(context).width >= 1180) ...[
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
                    icon: Icon(t.icon),
                    selectedIcon: Icon(t.activeIcon),
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
