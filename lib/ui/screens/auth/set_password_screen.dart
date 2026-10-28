import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/failure.dart';
import '../../../core/supabase.dart';
import '../../../core/theme/app_theme.dart';
import '../../../state/providers.dart';
import '../../widgets/study_widgets.dart';
import 'auth_scaffold.dart';

/// Where an invite link lands. The person chooses their own password; no
/// administrator ever sees or sets it.
class SetPasswordScreen extends ConsumerStatefulWidget {
  const SetPasswordScreen({super.key});
  @override
  ConsumerState<SetPasswordScreen> createState() => _SetPasswordScreenState();
}

class _SetPasswordScreenState extends ConsumerState<SetPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await authRepo.setFirstPassword(_password.text);
      ref.invalidate(profileProvider);
      await ref.read(profileProvider.future);
      if (mounted) context.go(ref.read(homeRouteProvider));
    } on Failure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).valueOrNull;
    return AuthScaffold(
      title: 'Choose your password',
      subtitle: 'Welcome to ZutLib${profile == null ? '' : ', ${profile.fullName}'}. '
          'Choose a password for ${auth.currentUser?.email ?? 'your account'}. '
          'You will use it to sign in from now on.',
      children: [
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _password,
                obscureText: _obscure,
                autofillHints: const [AutofillHints.newPassword],
                decoration: InputDecoration(
                  labelText: 'New password',
                  helperText: 'At least 8 characters',
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Show password' : 'Hide password',
                    icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                validator: (v) => (v == null || v.length < 8) ? 'Use at least 8 characters' : null,
              ),
              const SizedBox(height: Gap.snug),
              TextFormField(
                controller: _confirm,
                obscureText: _obscure,
                onFieldSubmitted: (_) => _save(),
                decoration: const InputDecoration(labelText: 'New password again'),
                validator: (v) => v != _password.text ? 'The two passwords are different' : null,
              ),
              if (_error != null) ...[
                const SizedBox(height: Gap.snug),
                InlineNotice(_error!, error: true),
              ],
              const SizedBox(height: Gap.page),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: Text(_busy ? 'Saving' : 'Save and continue'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
