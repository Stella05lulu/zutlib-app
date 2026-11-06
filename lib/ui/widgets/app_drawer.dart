import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart' show kWideBreakpoint;
import '../../core/theme/app_theme.dart';
import '../../data/account_repository.dart';
import '../../data/governance_repository.dart' show AdminBadges;
import '../../models/profile.dart';
import '../../services/reminders.dart';
import '../../state/governance_providers.dart';
import '../../state/providers.dart';

/// The shell's Scaffold, so a menu button inside any screen can open the
/// drawer that belongs to the shell.
final shellScaffoldKey = GlobalKey<ScaffoldState>();

/// True while the shell has a drawer the menu button can open.
bool get shellHasDrawer => shellScaffoldKey.currentState?.hasDrawer ?? false;

/// The menu button for a screen's top bar. It shows only while the shell
/// has a drawer to open (on wide screens the menu is always visible).
/// True when the menu button should show: staff and administrators have the
/// drawer (students do not), except an administrator on a wide screen, who has it open beside
/// the page. Decided from the role and width, so the button is there on the
/// very first frame (it used to wait for the drawer and could be missing).
bool showsShellMenu(BuildContext context, UserRole? role) =>
    role != null &&
    role != UserRole.student && // students move around with the five tabs
    !(role.isAdmin && MediaQuery.sizeOf(context).width >= kWideBreakpoint);

class ShellMenuButton extends ConsumerWidget {
  const ShellMenuButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(profileProvider).valueOrNull?.role;
    if (!showsShellMenu(context, role)) return const SizedBox.shrink();
    // The icon's left edge lines up with the page content under it.
    return IconButton(
      tooltip: 'Menu',
      icon: const Icon(Icons.menu),
      padding: EdgeInsets.zero,
      alignment: Alignment.centerLeft,
      constraints: const BoxConstraints.tightFor(width: 48, height: 48),
      onPressed: () => shellScaffoldKey.currentState?.openDrawer(),
    );
  }
}

/// A circle with someone's initials.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar(this.initials, {super.key, this.size = 40});
  final String initials;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.ink, shape: BoxShape.circle),
      child: Text(
        initials,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(color: c.canvas, fontSize: size * 0.38),
      ),
    );
  }
}

class _Item {
  const _Item(this.label, this.icon, this.path, {this.badge = 0, this.onOpen});
  final String label;
  final IconData icon;
  final String path;
  final int badge;
  final void Function(WidgetRef ref)? onOpen;
}

/// The menu: a header with the person's initials, name and role, sections
/// of screens, and Account, Sign out and the app version at the foot. Only
/// screens that work for this role are listed; the router and the database
/// refuse the rest anyway.
class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key, this.permanent = false});

  /// True when shown beside the page on a wide screen.
  final bool permanent;

  List<(String, List<_Item>)> _sections(Profile p, AdminBadges b) {
    switch (p.role) {
      case UserRole.admin:
      case UserRole.superAdmin:
        return [
          ('Workspace', [
            const _Item('Overview', Icons.space_dashboard_outlined, '/admin'),
            _Item('Users', Icons.group_outlined, '/admin/users', badge: b.pendingUsers),
            _Item('Invitations', Icons.mail_outline, '/admin/invitations', badge: b.openInvitations),
          ]),
          ('Library', [
            _Item('Borrowing', Icons.inbox_outlined, '/staff/requests', badge: b.overdue),
            _Item('Books', Icons.menu_book_outlined, '/staff/library',
                onOpen: (ref) => ref.read(libraryTabProvider.notifier).state = 1),
            _Item('Past papers', Icons.description_outlined, '/staff/library',
                onOpen: (ref) => ref.read(libraryTabProvider.notifier).state = 0),
            const _Item('Announcements', Icons.campaign_outlined, '/admin/announcements'),
          ]),
          ('Governance', [
            const _Item('Audit log', Icons.fact_check_outlined, '/admin/audit'),
            if (p.role == UserRole.superAdmin) const _Item('Settings', Icons.tune, '/admin/settings'),
          ]),
        ];
      case UserRole.librarian:
        return [
          ('Library', const [
            _Item('Today', Icons.today_outlined, '/staff/today'),
            _Item('Requests', Icons.inbox_outlined, '/staff/requests'),
            _Item('Library', Icons.local_library_outlined, '/staff/library'),
            _Item('Catalogue', Icons.explore_outlined, '/browse'),
          ]),
          ('You', const [_Item('Updates', Icons.notifications_none, '/updates')]),
        ];
      case UserRole.student:
        return [
          ('Study', const [
            _Item('Plan', Icons.event_note_outlined, '/plan'),
            _Item('My progress', Icons.insights_outlined, '/progress'),
            _Item('Study kits', Icons.school_outlined, '/study'),
          ]),
          ('Library', const [
            _Item('Saved', Icons.bookmark_border, '/saved'),
            _Item('My borrowing', Icons.auto_stories_outlined, '/borrowing'),
            _Item('Updates', Icons.notifications_none, '/updates'),
          ]),
        ];
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = StudyColors.of(context);
    final t = Theme.of(context).textTheme;
    final profile = ref.watch(profileProvider).valueOrNull;
    if (profile == null) return const SizedBox.shrink();
    final badges = ref.watch(adminBadgesProvider).valueOrNull ?? const AdminBadges();
    final location = GoRouterState.of(context).uri.path;
    final libraryTab = ref.watch(libraryTabProvider);

    bool active(_Item i) {
      if (i.path == '/staff/library' && i.onOpen != null) {
        return location == i.path && ((i.label == 'Books') == (libraryTab == 1));
      }
      return location == i.path;
    }

    void open(_Item i) {
      final router = GoRouter.of(context);
      i.onOpen?.call(ref);
      if (!permanent) Navigator.of(context).pop();
      // Full-screen pages open on top; shell pages replace the current tab.
      const pushed = {'/updates'};
      if (pushed.contains(i.path)) {
        router.push(i.path);
      } else {
        router.go(i.path);
      }
    }

    Widget row(_Item i) {
      final on = active(i);
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: Gap.tight),
        child: Material(
          color: on ? c.accentWash : Colors.transparent,
          borderRadius: BorderRadius.circular(Radii.control),
          child: InkWell(
            borderRadius: BorderRadius.circular(Radii.control),
            onTap: () => open(i),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Gap.snug),
                child: Row(
                  children: [
                    Icon(i.icon, size: 20, color: on ? c.accent : c.inkSoft),
                    const SizedBox(width: Gap.snug),
                    Expanded(
                      child: Text(i.label,
                          style: t.bodyLarge?.copyWith(
                              color: on ? c.accent : c.ink, fontWeight: on ? FontWeight.w600 : FontWeight.w400)),
                    ),
                    if (i.badge > 0)
                      Semantics(
                        label: '${i.badge} waiting',
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(Radii.tag)),
                          child: Text('${i.badge}', style: Mono.of(context, size: 12, color: c.onAccent, weight: FontWeight.w600)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    final body = SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.page, Gap.page, Gap.page, Gap.snug),
            child: Row(
              children: [
                InitialsAvatar(profile.initials, size: 48),
                const SizedBox(width: Gap.snug),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(profile.fullName, style: t.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                      Text(profile.role.label, style: t.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: c.line),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: Gap.page),
              children: [
                for (final (title, items) in _sections(profile, badges))
                  if (items.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Gap.page, Gap.page, Gap.page, Gap.hair),
                      child: Text(title, style: t.titleSmall),
                    ),
                    for (final i in items) row(i),
                  ],
              ],
            ),
          ),
          Divider(height: 1, color: c.line),
          const SizedBox(height: Gap.hair),
          row(const _Item('Account', Icons.account_circle_outlined, '/profile')),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.tight),
            child: InkWell(
              borderRadius: BorderRadius.circular(Radii.control),
              onTap: () async {
                await Reminders.cancelAll();
                await authRepo.signOut();
                ref.invalidate(profileProvider);
                if (context.mounted) context.go('/login');
              },
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Gap.snug),
                  child: Row(children: [
                    Icon(Icons.logout, size: 20, color: c.danger),
                    const SizedBox(width: Gap.snug),
                    Text('Sign out', style: t.bodyLarge?.copyWith(color: c.danger)),
                  ]),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.page, Gap.tight, Gap.page, Gap.snug),
            child: Text('ZutLib ${AccountRepository.appVersion}', style: Mono.of(context, size: 12, color: c.inkFaint)),
          ),
        ],
      ),
    );

    if (permanent) {
      return Container(
        width: 272,
        decoration: BoxDecoration(color: c.surface, border: Border(right: BorderSide(color: c.line))),
        child: body,
      );
    }
    return Drawer(
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(),
      child: body,
    );
  }
}
