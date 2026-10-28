import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/supabase.dart';
import '../../../core/theme/app_theme.dart';
import '../../../state/providers.dart';
import '../../widgets/countdown_button.dart';
import '../../widgets/study_widgets.dart';
import 'auth_scaffold.dart';

/// Shown to someone who signed up but has not opened the verification link.
/// Resending is limited by Supabase to one email a minute per address, so
/// the button counts down instead of failing.
class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key});
  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  bool _busy = false;
  String? _message;
  bool _isError = false;

  void _show(String message, bool isError) {
    if (mounted) {
      setState(() {
        _message = message;
        _isError = isError;
      });
    }
  }

  Future<void> _recheck() async {
    setState(() => _busy = true);
    try {
      await auth.refreshSession();
      if (!mounted) return;
      if (isVerified) {
        ref.invalidate(profileProvider);
        context.go('/');
      } else {
        _show('Not verified yet. Open the link in the email first.', true);
      }
    } catch (_) {
      _show('Could not check just now. Try again.', true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = auth.currentUser?.email ?? 'your address';
    return AuthScaffold(
      title: 'Verify your email',
      subtitle: 'We sent a link to $email. Open it, then come back here. '
          'Check the spam folder if it is not in your inbox.',
      children: [
        if (_message != null) ...[
          InlineNotice(_message!, error: _isError),
          const SizedBox(height: Gap.snug),
        ],
        FilledButton(
          onPressed: _busy ? null : _recheck,
          child: Text(_busy ? 'Checking' : 'I have verified it'),
        ),
        const SizedBox(height: Gap.tight),
        CountdownButton(
          label: 'Send the link again',
          onPressed: () async {
            final address = auth.currentUser?.email;
            if (address == null) return 'Sign in again first.';
            await authRepo.resendVerification(address);
            return 'Sent again. It can take a minute to arrive.';
          },
          onMessage: _show,
        ),
        const SizedBox(height: Gap.page),
        Align(
          alignment: Alignment.centerLeft,
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
