import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/supabase.dart';
import '../../../core/theme.dart';
import '../../../models/profile.dart';
import '../../../state/providers.dart';
import '../../../state/theme_mode.dart';
import '../../widgets/common.dart';
import '../../widgets/state_views.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(profileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: AsyncView<Profile?>(
        value: async,
        onRetry: () => ref.invalidate(profileProvider),
        data: (profile) {
          if (profile == null) {
            return const ErrorView(message: 'No profile is attached to this account.');
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
                Insets.md, Insets.md, Insets.md, kNavClearance),
            child: Readable(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        height: 60, width: 60,
                        decoration: BoxDecoration(
                            color: Palette.blueDeep, shape: BoxShape.circle),
                        alignment: Alignment.center,
                        child: Text(profile.initials,
                            style: TextStyle(
                              color: Palette.onAccent,
                              fontSize: 21,
                              fontWeight: FontWeight.w600,
                            )),
                      ),
                      const SizedBox(width: Insets.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(profile.fullName,
                                style: Theme.of(context).textTheme.titleLarge),
                            const SizedBox(height: 2),
                            Text(profile.role.label,
                                style: Theme.of(context).textTheme.bodyMedium),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SectionHeading('Verified details'),
                  Card(
                    child: Column(
                      children: [
                        _Row('Email', auth.currentUser?.email ?? ''),
                        if (profile.studentNumber != null) ...[
                          const Divider(height: 1),
                          _Row('Student number', profile.studentNumber!),
                        ],
                        if (profile.programme != null) ...[
                          const Divider(height: 1),
                          _Row('Programme', profile.programme!),
                        ],
                        if (profile.department != null) ...[
                          const Divider(height: 1),
                          _Row('Department', profile.department!),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: Insets.sm),
                  Text(
                    'These came from the institutional roll and cannot be '
                    'edited here. Contact the library if something is wrong.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SectionHeading('Appearance'),
                  const _AppearancePicker(),
                  const SectionHeading('Account'),
                  Card(
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.lock_reset_outlined),
                          title: const Text('Change password'),
                          subtitle: const Text('We will email you a link'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () async {
                            final email = auth.currentUser?.email;
                            if (email == null) return;
                            await authRepo.sendPasswordReset(email);
                            if (context.mounted) {
                              showMessage(context, 'Reset link sent to $email.');
                            }
                          },
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: Icon(Icons.logout, color: Palette.bad),
                          title: Text('Sign out',
                              style: TextStyle(color: Palette.bad)),
                          onTap: () async {
                            await authRepo.signOut();
                            ref.invalidate(profileProvider);
                            if (context.mounted) context.go('/login');
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Insets.xl),
                  Center(
                    child: Text('ZutLib  ·  Zambia University College of Technology',
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                  const SizedBox(height: Insets.lg),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);
  final String label, value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: Insets.md, vertical: 13),
        child: Row(
          children: [
            SizedBox(
                width: 140,
                child: Text(label,
                    style: Theme.of(context).textTheme.bodyMedium)),
            Expanded(
                child: Text(value,
                    style: const TextStyle(fontWeight: FontWeight.w600))),
          ],
        ),
      );
}

/// Automatic follows the phone's own light/dark setting.
class _AppearancePicker extends ConsumerWidget {
  const _AppearancePicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<ThemeMode>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(
            value: ThemeMode.system,
            icon: Icon(Icons.brightness_auto_rounded),
            label: Text('Automatic'),
          ),
          ButtonSegment(
            value: ThemeMode.light,
            icon: Icon(Icons.light_mode_rounded),
            label: Text('Light'),
          ),
          ButtonSegment(
            value: ThemeMode.dark,
            icon: Icon(Icons.dark_mode_rounded),
            label: Text('Dark'),
          ),
        ],
        selected: {mode},
        onSelectionChanged: (s) =>
            ref.read(themeModeProvider.notifier).set(s.first),
      ),
    );
  }
}
