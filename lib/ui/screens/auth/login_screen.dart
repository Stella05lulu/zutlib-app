import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/failure.dart';
import '../../../core/theme.dart';
import '../../../state/providers.dart';
import 'auth_scaffold.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() { _busy = true; _error = null; });
    try {
      await authRepo.signIn(_email.text, _password.text);
      ref.invalidate(profileProvider);
      if (mounted) context.go('/');
    } on Failure catch (f) {
      if (!mounted) return;
      if (f.code == 'unverified') {
        context.go('/verify');
        return;
      }
      setState(() => _error = f.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Sign in',
      subtitle: 'Use the email address you registered with.',
      children: [
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Email address',
                  prefixIcon: Icon(Icons.mail_outline),
                ),
                validator: (v) => (v == null || !v.contains('@'))
                    ? 'Enter your email address' : null,
              ),
              const SizedBox(height: Insets.md),
              TextFormField(
                controller: _password,
                obscureText: _obscure,
                autofillHints: const [AutofillHints.password],
                onFieldSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscure = !_obscure),
                    tooltip: _obscure ? 'Show password' : 'Hide password',
                  ),
                ),
                validator: (v) => (v == null || v.isEmpty)
                    ? 'Enter your password' : null,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => context.push('/forgot-password'),
                  child: const Text('Forgot password?'),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: Insets.sm),
                _ErrorBanner(_error!),
                const SizedBox(height: Insets.sm),
              ],
              const SizedBox(height: Insets.sm),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? SizedBox(
                        height: 19, width: 19,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.2, color: Palette.onAccent))
                    : const Text('Sign in'),
              ),
              const SizedBox(height: Insets.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('No account yet?',
                      style: Theme.of(context).textTheme.bodyMedium),
                  TextButton(
                    onPressed: () => context.push('/register'),
                    child: const Text('Register'),
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

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Container(
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
              child: Text(message,
                  style: TextStyle(
                      color: Palette.bad, fontSize: 13.5, height: 1.4)),
            ),
          ],
        ),
      );
}
