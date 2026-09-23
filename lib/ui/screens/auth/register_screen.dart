import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/failure.dart';
import '../../../core/theme.dart';
import '../../../state/providers.dart';
import 'auth_scaffold.dart';

/// Registration is self service. The roll decides eligibility, not a member
/// of staff, so nobody waits in a queue to be let in.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});
  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _number = TextEditingController();
  final _surname = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;
  String? _done;

  @override
  void dispose() {
    _number.dispose();
    _surname.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() { _busy = true; _error = null; });
    try {
      final message = await authRepo.register(
        studentNumber: _number.text,
        surname: _surname.text,
        email: _email.text,
        password: _password.text,
      );
      if (mounted) setState(() => _done = message);
    } on Failure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_done != null) {
      return AuthScaffold(
        title: 'Check your email',
        subtitle: _done!,
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
      title: 'Create your account',
      subtitle: 'Your student number and surname are checked against the '
          'institutional roll before an account is made.',
      children: [
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _number,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Student number',
                  prefixIcon: Icon(Icons.badge_outlined),
                  helperText: 'As it appears on your registration',
                ),
                validator: (v) => (v == null || v.trim().length < 5)
                    ? 'Enter your student number' : null,
              ),
              const SizedBox(height: Insets.md),
              TextFormField(
                controller: _surname,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Surname',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Enter your surname' : null,
              ),
              const SizedBox(height: Insets.md),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Email address',
                  prefixIcon: Icon(Icons.mail_outline),
                  helperText: 'You will need to open this to verify it',
                ),
                validator: (v) => (v == null || !v.contains('@'))
                    ? 'Enter a valid email address' : null,
              ),
              const SizedBox(height: Insets.md),
              TextFormField(
                controller: _password,
                obscureText: _obscure,
                onFieldSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  helperText: 'At least 8 characters',
                  suffixIcon: IconButton(
                    icon: Icon(_obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                validator: (v) => (v == null || v.length < 8)
                    ? 'Use at least 8 characters' : null,
              ),
              if (_error != null) ...[
                const SizedBox(height: Insets.md),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Palette.badWash,
                    borderRadius: BorderRadius.circular(Corners.field),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.error_outline, size: 18, color: Palette.bad),
                      const SizedBox(width: Insets.sm),
                      Expanded(
                        child: Text(_error!,
                            style: TextStyle(
                                color: Palette.bad, fontSize: 13.5, height: 1.4)),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: Insets.lg),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? SizedBox(
                        height: 19, width: 19,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.2, color: Palette.onAccent))
                    : const Text('Create account'),
              ),
              const SizedBox(height: Insets.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Already registered?',
                      style: Theme.of(context).textTheme.bodyMedium),
                  TextButton(
                    onPressed: () => context.go('/login'),
                    child: const Text('Sign in'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
