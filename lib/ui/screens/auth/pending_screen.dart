import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/profile.dart';
import '../../../state/providers.dart';
import '../../widgets/study_widgets.dart';
import 'auth_scaffold.dart';

/// The only screen a pending, rejected or suspended account can see. The
/// database shows such an account nothing else either: every policy needs
/// an active account (0012_accounts_roles_library.sql).
class PendingScreen extends ConsumerStatefulWidget {
  const PendingScreen({super.key});
  @override
  ConsumerState<PendingScreen> createState() => _PendingScreenState();
}

class _PendingScreenState extends ConsumerState<PendingScreen> {
  bool _checking = false;

  Future<void> _check() async {
    setState(() => _checking = true);
    ref.invalidate(profileProvider);
    try {
      await ref.read(profileProvider.future);
    } catch (_) {
      // The error is shown below.
    }
    if (mounted) setState(() => _checking = false);
  }

  Future<void> _signOut() async {
    await authRepo.signOut();
    ref.invalidate(profileProvider);
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(profileProvider);
    final profile = async.valueOrNull;
    final status = profile?.status ?? AccountStatus.pending;

    final (title, message) = switch (status) {
      AccountStatus.rejected => (
          'Account not approved',
          'An administrator did not approve this account. If you think this is a mistake, contact the library.'
        ),
      AccountStatus.removed => (
          'Account removed',
          'This account has been removed by an administrator. Contact the library if you think this is a mistake.'
        ),
      AccountStatus.suspended => (
          'Account suspended',
          'This account has been suspended by an administrator. Contact the library to have it reactivated.'
        ),
      _ => (
          'Waiting for approval',
          'Your email is verified. An administrator now needs to approve your account. '
              'You will be able to use ZutLib as soon as they do.'
        ),
    };

    return AuthScaffold(
      title: title,
      subtitle: message,
      children: [
        if (async.isLoading && profile == null)
          const Bone(height: 46, radius: Radii.control)
        else if (async.hasError)
          StudyErrorState(message: '${async.error}', onRetry: _check)
        else if (profile != null) ...[
          Text('Signed in as ${profile.email ?? profile.fullName}', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: Gap.page),
        ],
        if (status == AccountStatus.pending)
          FilledButton(
            onPressed: _checking ? null : _check,
            child: Text(_checking ? 'Checking' : 'Check again'),
          ),
        const SizedBox(height: Gap.tight),
        OutlinedButton(onPressed: _signOut, child: const Text('Sign out')),
      ],
    );
  }
}
