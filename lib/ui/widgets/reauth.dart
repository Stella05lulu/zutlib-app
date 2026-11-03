import 'package:flutter/material.dart';

import '../../core/failure.dart';
import '../../core/supabase.dart';
import '../../state/providers.dart' show authRepo;

DateTime? _confirmedAt;

/// How long a sign-in counts as recent for sensitive actions.
const kReauthWindow = Duration(minutes: 15);

/// Before a sensitive action (deciding a borrow request, changing someone's
/// account), make sure this person signed in recently. If it has been more
/// than 15 minutes, ask for their password again, so a phone left unlocked
/// on a desk cannot be used to approve loans or change roles.
Future<bool> confirmRecentSignIn(BuildContext context) async {
  final user = auth.currentUser;
  final email = user?.email;
  if (user == null || email == null) return false;
  final now = DateTime.now().toUtc();
  final last = DateTime.tryParse(user.lastSignInAt ?? '')?.toUtc();
  if ((last != null && now.difference(last) < kReauthWindow) ||
      (_confirmedAt != null && now.difference(_confirmedAt!) < kReauthWindow)) {
    return true;
  }
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ReauthDialog(email: email),
  );
  if (ok == true) _confirmedAt = DateTime.now().toUtc();
  return ok == true;
}

class _ReauthDialog extends StatefulWidget {
  const _ReauthDialog({required this.email});
  final String email;

  @override
  State<_ReauthDialog> createState() => _ReauthDialogState();
}

class _ReauthDialogState extends State<_ReauthDialog> {
  final _password = TextEditingController();
  bool _busy = false;
  bool _hidden = true;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_password.text.isEmpty) return setState(() => _error = 'Enter your password.');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await authRepo.signIn(widget.email, _password.text);
      if (mounted) Navigator.of(context).pop(true);
    } on Failure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Confirm it is you'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('For your security, enter the password for ${widget.email} before making this change.'),
          const SizedBox(height: 16),
          TextField(
            controller: _password,
            obscureText: _hidden,
            autofocus: true,
            decoration: InputDecoration(labelText: 'Password', errorText: _error),
            onSubmitted: (_) => _confirm(),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _hidden = !_hidden),
              child: Text(_hidden ? 'Show password' : 'Hide password'),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton(onPressed: _busy ? null : _confirm, child: Text(_busy ? 'Checking' : 'Confirm')),
      ],
    );
  }
}
