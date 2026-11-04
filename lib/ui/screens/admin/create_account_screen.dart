import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/profile.dart';
import '../../../state/providers.dart';
import '../../widgets/countdown_button.dart';
import '../../widgets/study_widgets.dart';

/// An administrator creates a student, librarian or administrator account.
/// Supabase emails the person an invite and they choose their own password
/// from it: no password is set, seen or shown here. The account is approved
/// straight away with the chosen role.
class CreateAccountScreen extends ConsumerStatefulWidget {
  const CreateAccountScreen({super.key});
  @override
  ConsumerState<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends ConsumerState<CreateAccountScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _testEmail = TextEditingController();
  UserRole _role = UserRole.librarian;
  String? _department;
  bool _busy = false;
  String? _message;
  bool _isError = false;
  String? _testMessage;
  bool _testIsError = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _testEmail.dispose();
    super.dispose();
  }

  bool _validEmail(String v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim());

  Future<void> _create() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final msg = await adminRepo.createAccount(
        email: _email.text,
        fullName: _name.text,
        role: _role,
        department: _role == UserRole.student ? _department : null,
      );
      if (!mounted) return;
      refreshUsers(ref);
      setState(() {
        _message = msg;
        _isError = false;
        _name.clear();
        _email.clear();
      });
    } on Failure catch (f) {
      if (mounted) {
        setState(() {
          _message = f.message;
          _isError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StudyScope(
      child: Builder(builder: (context) {
        final t = Theme.of(context).textTheme;
        return Scaffold(
          appBar: const StudyTopBar(title: 'Create account'),
          body: StudyPage(children: [
            Text('The person gets an email from ZutLib and chooses their own password. '
                'Accounts created here are approved straight away.',
                style: t.bodyMedium),
            const SizedBox(height: Gap.page),
            Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Full name'),
                    validator: (v) => (v == null || v.trim().length < 2) ? 'Enter their full name' : null,
                  ),
                  const SizedBox(height: Gap.snug),
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email address'),
                    validator: (v) => (v == null || !_validEmail(v)) ? 'Enter a valid email address' : null,
                  ),
                  const SizedBox(height: Gap.snug),
                  DropdownButtonFormField<UserRole>(
                    initialValue: _role,
                    decoration: const InputDecoration(labelText: 'Role'),
                    // Only roles below your own: an admin invites students and
                    // librarians, a super admin also administrators. The
                    // database refuses anything else.
                    items: [
                      for (final r in UserRole.values)
                        if (r.rank < (ref.watch(profileProvider).valueOrNull?.role.rank ?? 0))
                          DropdownMenuItem(value: r, child: Text(r.label)),
                    ],
                    onChanged: (v) => setState(() => _role = v ?? _role),
                  ),
                  if (_role == UserRole.student) ...[
                    const SizedBox(height: Gap.snug),
                    DropdownButtonFormField<String>(
                      initialValue: _department,
                      decoration: const InputDecoration(labelText: 'Department'),
                      items: [
                        for (final d in kStudentDepartments) DropdownMenuItem(value: d, child: Text(d)),
                      ],
                      onChanged: (v) => setState(() => _department = v),
                      validator: (v) => v == null ? 'Choose a department' : null,
                    ),
                  ],
                  if (_message != null) ...[
                    const SizedBox(height: Gap.snug),
                    InlineNotice(_message!, error: _isError),
                  ],
                  const SizedBox(height: Gap.page),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton(
                      onPressed: _busy ? null : _create,
                      child: Text(_busy ? 'Sending invite' : 'Create and send invite'),
                    ),
                  ),
                ],
              ),
            ),
            const SectionLabel('Check that emails arrive', top: Gap.wide),
            Text('Sends an invite to any address you own, such as a second inbox, so you can see '
                'whether it arrives and whether the link opens the app. The account it makes is '
                'suspended and can do nothing.',
                style: t.bodyMedium),
            const SizedBox(height: Gap.snug),
            TextField(
              controller: _testEmail,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Test address'),
            ),
            if (_testMessage != null) ...[
              const SizedBox(height: Gap.snug),
              InlineNotice(_testMessage!, error: _testIsError),
            ],
            const SizedBox(height: Gap.snug),
            Align(
              alignment: Alignment.centerLeft,
              child: CountdownButton(
                label: 'Send test invite',
                onPressed: () async {
                  if (!_validEmail(_testEmail.text)) {
                    throw const Failure('Enter a valid test address first.');
                  }
                  return adminRepo.sendTestInvite(_testEmail.text);
                },
                onMessage: (m, e) {
                  if (mounted) {
                    setState(() {
                      _testMessage = m;
                      _testIsError = e;
                    });
                  }
                },
              ),
            ),
          ]),
        );
      }),
    );
  }
}
