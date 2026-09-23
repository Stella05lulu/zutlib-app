import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/failure.dart';
import '../../../core/theme.dart';
import '../../../state/providers.dart';
import 'auth_scaffold.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _email = TextEditingController();
  bool _busy = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() { _email.dispose(); super.dispose(); }

  Future<void> _submit() async {
    if (!_email.text.contains('@')) {
      setState(() => _error = 'Enter your email address');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await authRepo.sendPasswordReset(_email.text);
      if (mounted) setState(() => _sent = true);
    } on Failure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_sent) {
      return AuthScaffold(
        title: 'Check your email',
        subtitle: 'If an account exists for ${_email.text.trim()}, a reset '
            'link is on its way. Open it on this phone.',
        children: [
          const SizedBox(height: Insets.sm),
          FilledButton(
            onPressed: () => context.go('/login'),
            child: const Text('Back to sign in'),
          ),
        ],
      );
    }

    return AuthScaffold(
      title: 'Reset your password',
      subtitle: 'We will email you a link to set a new one.',
      children: [
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: 'Email address',
            prefixIcon: const Icon(Icons.mail_outline),
            errorText: _error,
          ),
        ),
        const SizedBox(height: Insets.lg),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? SizedBox(
                  height: 19, width: 19,
                  child: CircularProgressIndicator(strokeWidth: 2.2, color: Palette.onAccent))
              : const Text('Send reset link'),
        ),
        const SizedBox(height: Insets.md),
        Center(
          child: TextButton(
            onPressed: () => context.go('/login'),
            child: const Text('Back to sign in'),
          ),
        ),
      ],
    );
  }
}
