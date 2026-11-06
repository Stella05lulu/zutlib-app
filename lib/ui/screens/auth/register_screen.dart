import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/governance_repository.dart' show governanceRepo;
import '../../../models/profile.dart';
import '../../../state/providers.dart';
import '../../widgets/study_widgets.dart';
import 'auth_scaffold.dart';

/// Public sign-up, for students only. The account starts as "waiting for
/// approval": the person verifies their email, then an administrator
/// approves them. Staff accounts are never made here; an administrator
/// invites them.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});
  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String? _department;
  bool _busy = false;
  bool _obscure = true;
  String? _error;
  bool _done = false;

  /// Whether sign-up is open (System settings, 0018). Null while asking.
  bool? _open;

  @override
  void initState() {
    super.initState();
    governanceRepo.registrationOpen().then((v) {
      if (mounted) setState(() => _open = v);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await authRepo.register(
        fullName: _name.text,
        department: _department!,
        email: _email.text,
        password: _password.text,
      );
      if (mounted) setState(() => _done = true);
    } on Failure catch (f) {
      // The database refuses sign-up while registration is closed; say so
      // plainly instead of showing the raw error.
      final open = await governanceRepo.registrationOpen();
      if (mounted) {
        setState(() {
          _open = open;
          _error = f.message;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_done) {
      return AuthScaffold(
        title: 'Check your email',
        subtitle: 'We sent a link to ${_email.text.trim()}. Open it to verify your address. '
            'After that, an administrator approves your account and you can sign in.',
        children: [
          FilledButton(
            onPressed: () => context.go('/login'),
            child: const Text('Back to sign in'),
          ),
        ],
      );
    }

    if (_open == false) {
      return AuthScaffold(
        title: 'Registration is closed',
        subtitle: 'New student accounts cannot be made right now. Ask the library for an invite, '
            'or try again later.',
        children: [
          FilledButton(
            onPressed: () => context.go('/login'),
            child: const Text('Back to sign in'),
          ),
        ],
      );
    }

    return AuthScaffold(
      title: 'Create a student account',
      subtitle: 'Staff accounts are created by an administrator, not here.',
      children: [
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.name],
                decoration: const InputDecoration(labelText: 'Full name'),
                validator: (v) => (v == null || v.trim().length < 2) ? 'Enter your full name' : null,
              ),
              const SizedBox(height: Gap.snug),
              DropdownButtonFormField<String>(
                initialValue: _department,
                decoration: const InputDecoration(labelText: 'Department'),
                items: [
                  for (final d in kStudentDepartments) DropdownMenuItem(value: d, child: Text(d)),
                ],
                onChanged: (v) => setState(() => _department = v),
                validator: (v) => v == null ? 'Choose your department' : null,
              ),
              const SizedBox(height: Gap.snug),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(
                  labelText: 'Email address',
                  helperText: 'You will need to open a link sent here',
                ),
                validator: (v) => (v == null || !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim()))
                    ? 'Enter a valid email address'
                    : null,
              ),
              const SizedBox(height: Gap.snug),
              TextFormField(
                controller: _password,
                obscureText: _obscure,
                textInputAction: TextInputAction.next,
                autofillHints: kIsWeb ? null : const [AutofillHints.newPassword],
                decoration: const InputDecoration(
                  labelText: 'Password',
                  helperText: 'At least 8 characters',
                ),
                validator: (v) => (v == null || v.length < 8) ? 'Use at least 8 characters' : null,
              ),
              const SizedBox(height: Gap.snug),
              TextFormField(
                controller: _confirm,
                obscureText: _obscure,
                onFieldSubmitted: (_) => _submit(),
                decoration: const InputDecoration(labelText: 'Password again'),
                validator: (v) => v != _password.text ? 'The two passwords are different' : null,
              ),
              ShowPasswordToggle(hidden: _obscure, onChanged: (v) => setState(() => _obscure = v)),
              if (_error != null) ...[
                const SizedBox(height: Gap.snug),
                InlineNotice(_error!, error: true),
              ],
              const SizedBox(height: Gap.page),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: Text(_busy ? 'Creating account' : 'Create account'),
              ),
              const SizedBox(height: Gap.tight),
              Row(
                children: [
                  Text('Already have an account?', style: Theme.of(context).textTheme.bodyMedium),
                  TextButton(onPressed: () => context.go('/login'), child: const Text('Sign in')),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
