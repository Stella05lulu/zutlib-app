import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/failure.dart';
import '../../../core/supabase.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/profile.dart';
import '../../../state/governance_providers.dart';
import '../../../state/providers.dart';
import '../../widgets/app_drawer.dart' show InitialsAvatar;
import '../../widgets/countdown_button.dart';
import '../../widgets/reason_dialog.dart';
import '../../widgets/reauth.dart';
import '../../widgets/study_widgets.dart';

/// One account. What is offered depends on the viewer's rank: an
/// administrator manages students and librarians; a super admin also
/// manages administrators and has the account tools (each needs a reason
/// and is audited). The server refuses anything else regardless.
class UserDetailScreen extends ConsumerStatefulWidget {
  const UserDetailScreen({super.key, required this.userId});
  final String userId;

  @override
  ConsumerState<UserDetailScreen> createState() => _UserDetailScreenState();
}

class _UserDetailScreenState extends ConsumerState<UserDetailScreen> {
  String? _message;
  bool _isError = false;
  bool _busy = false;

  void _show(String message, bool isError) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _isError = isError;
    });
  }

  /// Runs a change after a recent sign-in check, then reloads.
  Future<void> _act(Future<String?> Function() action, {String? done}) async {
    if (!await confirmRecentSignIn(context)) return;
    setState(() => _busy = true);
    try {
      final msg = await action();
      refreshAdmin(ref);
      _show(msg ?? done ?? 'Done.', false);
    } on Failure catch (f) {
      _show(f.message, true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _withReason(String title, String message, String confirm, Future<String?> Function(String reason) run,
      {bool destructive = false, String? done}) async {
    final reason = await askReason(context, title: title, message: message, confirmLabel: confirm, destructive: destructive);
    if (reason == null) return;
    await _act(() => run(reason), done: done);
  }

  Future<void> _edit(Profile p) async {
    final result = await showDialog<(String, String?, String?, String)>(
      context: context,
      builder: (_) => _EditDialog(profile: p),
    );
    if (result == null) return;
    await _act(() => adminRepo.editProfile(p.id,
        fullName: result.$1, department: result.$2, studentNumber: result.$3, reason: result.$4));
  }

  Future<void> _changeEmail(Profile p) async {
    final result = await showDialog<(String, String)>(context: context, builder: (_) => _EmailDialog(current: p.email));
    if (result == null) return;
    await _act(() => adminRepo.changeEmail(p.id, result.$1, result.$2));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(userDetailProvider(widget.userId));
    final myRole = ref.watch(profileProvider).valueOrNull?.role ?? UserRole.student;

    return StudyScope(
      child: Builder(builder: (context) {
        return Scaffold(
          appBar: StudyTopBar(title: async.valueOrNull?.fullName ?? 'Account'),
          body: StudyPage(
            onRefresh: () async {
              ref.invalidate(userDetailProvider(widget.userId));
              try {
                await ref.read(userDetailProvider(widget.userId).future);
              } catch (_) {
                // Shown on the page.
              }
            },
            children: [
              StudyAsync<Profile?>(
                value: async,
                onRetry: () => ref.invalidate(userDetailProvider(widget.userId)),
                skeleton: const RowsSkeleton(rows: 5),
                isEmpty: (p) => p == null,
                empty: const StudyEmptyState('This account no longer exists.'),
                data: (p) => _body(context, p!, myRole),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _body(BuildContext context, Profile p, UserRole myRole) {
    final t = Theme.of(context).textTheme;
    final c = StudyColors.of(context);
    final isMe = p.id == currentUserId;
    final canManage = !isMe && p.role.rank < myRole.rank;
    final isSuper = myRole == UserRole.superAdmin;
    final removed = p.status == AccountStatus.removed;

    Widget button(String label, VoidCallback onTap, {bool primary = false, bool danger = false, IconData? icon}) {
      final style = danger ? OutlinedButton.styleFrom(foregroundColor: c.danger) : null;
      final child = Text(label);
      if (primary) {
        return FilledButton(onPressed: _busy ? null : onTap, child: child);
      }
      return icon == null
          ? OutlinedButton(style: style, onPressed: _busy ? null : onTap, child: child)
          : OutlinedButton.icon(style: style, onPressed: _busy ? null : onTap, icon: Icon(icon, size: 18), label: child);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          InitialsAvatar(p.initials, size: 56),
          const SizedBox(width: Gap.snug),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.fullName, style: t.headlineSmall),
              const SizedBox(height: Gap.hair),
              Wrap(spacing: Gap.tight, runSpacing: Gap.hair, children: [
                Tag(p.role.label),
                Tag(p.status.label, sky: !p.isActive),
                if (p.mustSetPassword) const Tag('Invite not accepted'),
                if (isMe) const Tag('You'),
              ]),
            ]),
          ),
        ]),
        if (_message != null) ...[
          const SizedBox(height: Gap.page),
          InlineNotice(_message!, error: _isError, onClose: () => setState(() => _message = null)),
        ],
        const SectionLabel('Details'),
        RowGroup(children: [
          StudyRow(title: 'Email', detail: p.email ?? 'None'),
          StudyRow(title: 'Department', detail: p.department ?? 'None'),
          if (p.role == UserRole.student) StudyRow(title: 'Student number', detail: p.studentNumber ?? 'None'),
          if (p.yearOfStudy != null) StudyRow(title: 'Year of study', detail: '${p.yearOfStudy}'),
          if (p.createdAt != null) StudyRow(title: 'Joined', detail: studyDateTime.format(p.createdAt!)),
        ]),
        const SectionLabel('Actions'),
        if (isMe)
          Text('This is your own account. Another administrator has to change it.', style: t.bodyMedium)
        else if (!canManage)
          Text(
            p.role == UserRole.superAdmin
                ? 'A super admin account can only be changed from the Supabase dashboard.'
                : 'Only a super admin can change an administrator\'s account.',
            style: t.bodyMedium,
          )
        else ...[
          Wrap(spacing: Gap.tight, runSpacing: Gap.tight, children: [
            if (p.status == AccountStatus.pending) ...[
              button('Approve', () => _act(() async {
                    await adminRepo.approve(p.id);
                    return null;
                  }, done: '${p.fullName} can now use ZutLib.'), primary: true),
              button('Reject', () => _act(() async {
                    await adminRepo.reject(p.id);
                    return null;
                  }, done: '${p.fullName} was not approved.')),
            ],
            if (p.status == AccountStatus.active)
              button('Suspend', () => _act(() async {
                    await adminRepo.suspend(p.id);
                    return null;
                  }, done: '${p.fullName} is suspended.'), danger: true),
            if (p.status == AccountStatus.suspended || p.status == AccountStatus.rejected)
              button('Reinstate', () => _act(() async {
                    await adminRepo.reactivate(p.id);
                    return null;
                  }, done: '${p.fullName} is active again.'), primary: true),
          ]),
          if (p.mustSetPassword && !removed) ...[
            const SizedBox(height: Gap.snug),
            CountdownButton(label: 'Resend invite email', onPressed: () => adminRepo.resendInvite(p.id), onMessage: _show),
          ],
          if (isSuper) ...[
            if (p.status == AccountStatus.active) ...[
              const SectionLabel('Role'),
              Wrap(spacing: Gap.tight, runSpacing: Gap.tight, children: [
                for (final r in UserRole.values)
                  if (r != p.role && r.rank < myRole.rank)
                    button('Make ${r.label.toLowerCase()}', () => _act(() async {
                          await adminRepo.setRole(p.id, r);
                          return null;
                        }, done: '${p.fullName} is now a ${r.label.toLowerCase()}.')),
              ]),
            ],
            const SectionLabel('Account tools'),
            Text('Super admin only. Each asks for a reason, which is kept in the audit log.', style: t.bodySmall),
            const SizedBox(height: Gap.tight),
            Wrap(spacing: Gap.tight, runSpacing: Gap.tight, children: [
              if (!removed) ...[
                button('Edit details', () => _edit(p), icon: Icons.edit_outlined),
                button('Change email', () => _changeEmail(p), icon: Icons.alternate_email),
                button('Send password link', () => _withReason(
                      'Send a password link?',
                      'A link to choose a new password goes to ${p.email}. You never see or set the password.',
                      'Send',
                      (r) => adminRepo.sendPasswordLink(p.id, r),
                    ), icon: Icons.key_outlined),
                button('Sign out everywhere', () => _withReason(
                      'Sign out everywhere?',
                      'Every device signed in as ${p.fullName} has to sign in again within the hour.',
                      'Sign out',
                      (r) => adminRepo.signOutEverywhere(p.id, r),
                    ), icon: Icons.devices_other_outlined),
                if (p.role == UserRole.student || p.role == UserRole.librarian)
                  button('View as', () => context.push('/admin/view-as/${p.id}'), icon: Icons.visibility_outlined),
                button('Remove account', () => _withReason(
                      'Remove ${p.fullName}?',
                      'They lose access straight away. The account and its history are kept, so it can be restored.',
                      'Remove',
                      (r) async {
                        await adminRepo.remove(p.id, r);
                        return '${p.fullName} was removed.';
                      },
                      destructive: true,
                    ), danger: true, icon: Icons.person_remove_outlined),
              ] else
                button('Restore account', () => _withReason(
                      'Restore ${p.fullName}?',
                      'The account becomes active again with its old role.',
                      'Restore',
                      (r) async {
                        await adminRepo.restore(p.id, r);
                        return '${p.fullName} was restored.';
                      },
                    ), primary: true),
            ]),
          ] else if (removed)
            Text('This account was removed. Only a super admin can restore it.', style: t.bodyMedium),
        ],
      ],
    );
  }
}

class _EditDialog extends StatefulWidget {
  const _EditDialog({required this.profile});
  final Profile profile;

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late final _name = TextEditingController(text: widget.profile.fullName);
  late final _number = TextEditingController(text: widget.profile.studentNumber ?? '');
  final _reason = TextEditingController();
  late String? _dept = widget.profile.department;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _number.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final student = widget.profile.role == UserRole.student;
    return AlertDialog(
      title: const Text('Edit details'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: _name, maxLength: 120, decoration: const InputDecoration(labelText: 'Full name')),
            DropdownButtonFormField<String?>(
              initialValue: _dept,
              decoration: const InputDecoration(labelText: 'Department'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('None')),
                for (final d in kStudentDepartments) DropdownMenuItem<String?>(value: d, child: Text(d)),
              ],
              onChanged: (v) => setState(() => _dept = v),
            ),
            if (student) ...[
              const SizedBox(height: Gap.snug),
              TextField(controller: _number, maxLength: 20, decoration: const InputDecoration(labelText: 'Student number')),
            ],
            const SizedBox(height: Gap.snug),
            TextField(
              controller: _reason,
              maxLength: 500,
              decoration: InputDecoration(labelText: 'Reason', errorText: _error),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          onPressed: () {
            if (_name.text.trim().length < 2) return setState(() => _error = 'Enter their full name.');
            if (_reason.text.trim().length < 3) return setState(() => _error = 'Say briefly why.');
            Navigator.pop(context, (_name.text.trim(), _dept, student ? _number.text.trim() : null, _reason.text.trim()));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _EmailDialog extends StatefulWidget {
  const _EmailDialog({required this.current});
  final String? current;

  @override
  State<_EmailDialog> createState() => _EmailDialogState();
}

class _EmailDialogState extends State<_EmailDialog> {
  final _email = TextEditingController();
  final _reason = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change email'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Now: ${widget.current ?? 'none'}. After the change, a link to choose a password goes to the new address.'),
          const SizedBox(height: Gap.snug),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'New email address'),
          ),
          TextField(controller: _reason, maxLength: 500, decoration: InputDecoration(labelText: 'Reason', errorText: _error)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          onPressed: () {
            if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_email.text.trim())) {
              return setState(() => _error = 'Enter a valid email address.');
            }
            if (_reason.text.trim().length < 3) return setState(() => _error = 'Say briefly why.');
            Navigator.pop(context, (_email.text.trim(), _reason.text.trim()));
          },
          child: const Text('Change'),
        ),
      ],
    );
  }
}
