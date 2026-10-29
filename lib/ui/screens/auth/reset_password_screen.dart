import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/failure.dart';
import '../../../core/theme.dart';
import '../../../state/providers.dart';
import '../../widgets/common.dart';
import 'auth_scaffold.dart';

/// Shown when the app is opened from a password reset email. The link has
/// already signed the person in for this one purpose; setting a new
/// password ends recovery mode and the router takes them home.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});
  @override
  ConsumerState<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_password.text.length < 8) {
      setState(() => _error = 'Use at least 8 characters.');
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _error = 'The two passwords do not match.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await authRepo.updatePassword(_password.text);
      if (!mounted) return;
      showMessage(context, 'Password changed. You are signed in.');
      ref.invalidate(profileProvider);
      ref.read(passwordRecoveryProvider.notifier).state = false;
    } on Failure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Choose a new password',
      subtitle: 'Use at least 8 characters. You will stay signed in afterwards.',
      children: [
        TextField(
          controller: _password,
          obscureText: _obscure,
          autofillHints: kIsWeb ? null : const [AutofillHints.newPassword],
          decoration: const InputDecoration(
            labelText: 'New password',
            prefixIcon: Icon(Icons.lock_outline_rounded),
          ),
        ),
        const SizedBox(height: Insets.md),
        TextField(
          controller: _confirm,
          obscureText: _obscure,
          onSubmitted: (_) => _submit(),
          decoration: const InputDecoration(
            labelText: 'Confirm new password',
            prefixIcon: Icon(Icons.lock_outline_rounded),
          ),
        ),
        ShowPasswordToggle(hidden: _obscure, onChanged: (v) => setState(() => _obscure = v)),
        if (_error != null) ...[
          const SizedBox(height: Insets.md),
          Text(_error!,
              style: TextStyle(color: Palette.bad, fontWeight: FontWeight.w600)),
        ],
        const SizedBox(height: Insets.lg),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? SizedBox(
                  height: 20, width: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.2, color: Palette.onAccent))
              : const Text('Save new password'),
        ),
      ],
    );
  }
}
