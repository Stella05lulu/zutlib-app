import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/failure.dart';
import '../../../core/theme.dart';
import '../../../models/profile.dart';
import '../../../state/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/state_views.dart';

class UsersScreen extends ConsumerWidget {
  const UsersScreen({super.key});

  Future<void> _change(
      BuildContext context, WidgetRef ref, Profile p) async {
    final role = await showDialog<UserRole>(
      context: context,
      builder: (_) => SimpleDialog(
        title: Text('Role for ${p.fullName}'),
        children: [
          for (final r in UserRole.values)
            RadioListTile<UserRole>(
              value: r,
              groupValue: p.role,
              title: Text(r.label),
              subtitle: Text(switch (r) {
                UserRole.student => 'Search, read and apply to borrow',
                UserRole.librarian => 'Decide requests and manage resources',
                UserRole.admin => 'Everything, plus the roll and roles',
              }),
              onChanged: (v) => Navigator.pop(context, v),
            ),
        ],
      ),
    );
    if (role == null || role == p.role) return;
    try {
      await adminRepo.setRole(p.id, role);
      ref.invalidate(usersProvider);
      if (context.mounted) {
        showMessage(context, '${p.fullName} is now a ${role.label.toLowerCase()}.');
      }
    } on Failure catch (f) {
      if (context.mounted) showMessage(context, f.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(usersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Users and roles')),
      body: AsyncView<List<Profile>>(
        value: async,
        onRetry: () => ref.invalidate(usersProvider),
        data: (users) {
          if (users.isEmpty) {
            return const EmptyView(
              icon: Icons.group_outlined,
              headline: 'No accounts yet',
              body: 'Accounts appear here once students register against '
                  'the roll.',
            );
          }
          final columns = catalogGridColumns(MediaQuery.sizeOf(context).width);
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(
                Insets.md, Insets.md, Insets.md, kNavClearance),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: Insets.md,
              crossAxisSpacing: Insets.md,
              mainAxisExtent: 224,
            ),
            itemCount: users.length,
            itemBuilder: (_, i) {
              final p = users[i];
              return UserCard(profile: p, onTap: () => _change(context, ref, p));
            },
          );
        },
      ),
    );
  }
}

/// A directory tile: an initials avatar in place of a photo, the role
/// overlaid on the banner as a tag, then the account's name and roll
/// details below. Tapping it opens the same role-change dialog the row
/// used to open from its trailing chip.
class UserCard extends StatelessWidget {
  const UserCard({super.key, required this.profile, required this.onTap});
  final Profile profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              children: [
                Container(
                  height: 92,
                  width: double.infinity,
                  color: Palette.canvas,
                  alignment: Alignment.center,
                  child: Container(
                    height: 52, width: 52,
                    decoration: BoxDecoration(
                        color: Palette.blueWash, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: Text(profile.initials,
                        style: TextStyle(
                          color: Palette.blueDeep,
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                        )),
                  ),
                ),
                Positioned(
                  left: 8, bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: (profile.role.isStaff ? Palette.blueDeep : Palette.ink)
                          .withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(Corners.chip),
                    ),
                    child: Text(
                      profile.role.label.toUpperCase(),
                      style: TextStyle(
                        color: Palette.onAccent,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Insets.sm, Insets.sm, Insets.sm, 7),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(profile.fullName,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              height: 1.25,
                              color: Palette.ink,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 3),
                        MetaLine([
                          profile.studentNumber ?? 'Staff account',
                          profile.programme ?? '',
                        ]),
                      ],
                    ),
                    Row(
                      children: [
                        Icon(Icons.edit_outlined,
                            size: 14, color: Palette.inkFaint),
                        SizedBox(width: 4),
                        Text(
                          'Tap to change role',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Palette.inkFaint,
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
