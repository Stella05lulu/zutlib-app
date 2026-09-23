import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/failure.dart';
import '../../../core/supabase.dart';
import '../../../core/theme.dart';
import '../../../state/providers.dart';
import '../../widgets/common.dart';
import 'auth_scaffold.dart';

class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key});
  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  bool _busy = false;

  Future<void> _recheck() async {
    setState(() => _busy = true);
    try {
      await auth.refreshSession();
      if (!mounted) return;
      if (isVerified) {
        ref.invalidate(profileProvider);
        context.go('/');
      } else {
        showMessage(context, 'Not verified yet. Open the link in the email first.');
      }
    } catch (_) {
      if (mounted) showMessage(context, 'Could not check just now. Try again.', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    final email = auth.currentUser?.email;
    if (email == null) return;
    try {
      await authRepo.resendVerification(email);
      if (mounted) showMessage(context, 'Sent again. It can take a minute to arrive.');
    } on Failure catch (f) {
      if (mounted) showMessage(context, f.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = auth.currentUser?.email ?? 'your address';
    return AuthScaffold(
      title: 'Verify your email',
      subtitle: 'We sent a link to $email. Open it, then come back here.',
      children: [
        const SizedBox(height: Insets.sm),
        FilledButton(
          onPressed: _busy ? null : _recheck,
          child: _busy
              ? SizedBox(
                  height: 19, width: 19,
                  child: CircularProgressIndicator(strokeWidth: 2.2, color: Palette.onAccent))
              : const Text("I've verified it"),
        ),
        const SizedBox(height: Insets.sm),
        OutlinedButton(onPressed: _resend, child: const Text('Send the link again')),
        const SizedBox(height: Insets.lg),
        Center(
          child: TextButton(
            onPressed: () async {
              await authRepo.signOut();
              if (context.mounted) context.go('/login');
            },
            child: const Text('Use a different account'),
          ),
        ),
      ],
    );
  }
}
