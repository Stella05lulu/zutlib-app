import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/failure.dart';
import '../../../core/supabase.dart';
import '../../../core/theme.dart' show kNavClearance;
import '../../../core/theme/app_theme.dart';
import '../../../models/profile.dart';
import '../../../state/providers.dart';
import '../../widgets/countdown_button.dart';
import '../../widgets/study_widgets.dart';

/// Every account, with the students waiting for approval first. Each
/// change goes through the admin-users Edge Function, which checks the
/// caller is an administrator and writes the audit log.
class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});
  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen> {
  String? _message;
  bool _isError = false;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search.text = ref.read(usersSearchProvider);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _show(String message, bool isError) {
    if (mounted) {
      setState(() {
        _message = message;
        _isError = isError;
      });
    }
  }

  Future<void> _act(String done, Future<void> Function() action) async {
    try {
      await action();
      if (!mounted) return;
      refreshUsers(ref);
      _show(done, false);
    } on Failure catch (f) {
      _show(f.message, true);
    }
  }

  Future<void> _openActions(Profile p) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.panel)),
      ),
      builder: (sheet) => _AccountSheet(
        profile: p,
        onAction: (label, action) async {
          Navigator.pop(sheet);
          await _act(label, action);
        },
        onMessage: _show,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tab = ref.watch(usersTabProvider);
    final pending = ref.watch(pendingUsersProvider);
    final everyone = ref.watch(usersProvider);
    final waiting = pending.valueOrNull?.length;

    return StudyScope(
      child: Builder(builder: (context) {
        final c = StudyColors.of(context);
        final t = Theme.of(context).textTheme;
        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: StudyPage(
              bottom: kNavClearance,
              onRefresh: () async {
                refreshUsers(ref);
                try {
                  await ref.read(pendingUsersProvider.future);
                } catch (_) {
                  // Shown on screen.
                }
              },
              children: [
                const SizedBox(height: Gap.tight),
                Row(
                  children: [
                    Expanded(child: Text('Users', style: t.headlineSmall)),
                    FilledButton.icon(
                      onPressed: () => context.push('/admin/users/new'),
                      icon: const Icon(Icons.person_add_alt, size: 18),
                      label: const Text('Create account'),
                    ),
                  ],
                ),
                const SizedBox(height: Gap.page),
                Container(
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
                  child: Row(children: [
                    _Tab(
                      label: waiting == null ? 'Waiting for approval' : 'Waiting for approval ($waiting)',
                      selected: tab == 0,
                      onTap: () => ref.read(usersTabProvider.notifier).state = 0,
                    ),
                    _Tab(
                      label: 'Everyone',
                      selected: tab == 1,
                      onTap: () => ref.read(usersTabProvider.notifier).state = 1,
                    ),
                  ]),
                ),
                if (_message != null) ...[
                  const SizedBox(height: Gap.snug),
                  InlineNotice(_message!, error: _isError, onClose: () => setState(() => _message = null)),
                ],
                const SizedBox(height: Gap.page),
                if (tab == 0)
                  StudyAsync<List<Profile>>(
                    value: pending,
                    onRetry: () => ref.invalidate(pendingUsersProvider),
                    skeleton: const RowsSkeleton(rows: 3),
                    isEmpty: (v) => v.isEmpty,
                    empty: const StudyEmptyState('Nobody is waiting for approval.'),
                    data: (people) => RowGroup(children: [
                      for (final p in people)
                        _PendingRow(
                          profile: p,
                          onApprove: () => _act('${p.fullName} can now use ZutLib.', () => adminRepo.approve(p.id)),
                          onReject: () => _act('${p.fullName} was not approved.', () => adminRepo.reject(p.id)),
                        ),
                    ]),
                  )
                else ...[
                  TextField(
                    controller: _search,
                    decoration: const InputDecoration(
                      hintText: 'Search by name or email',
                      prefixIcon: Icon(Icons.search, size: 20),
                    ),
                    onSubmitted: (v) => ref.read(usersSearchProvider.notifier).state = v,
                  ),
                  const SizedBox(height: Gap.snug),
                  StudyAsync<List<Profile>>(
                    value: everyone,
                    onRetry: () => ref.invalidate(usersProvider),
                    skeleton: const RowsSkeleton(rows: 6),
                    isEmpty: (v) => v.isEmpty,
                    empty: const StudyEmptyState('No accounts match that search.'),
                    data: (people) => RowGroup(children: [
                      for (final p in people)
                        StudyRow(
                          title: p.fullName,
                          detail: [p.email ?? '', if (p.department != null) p.department!].join('  /  '),
                          detailLines: 1,
                          tags: [
                            Tag(p.role.label),
                            if (!p.isActive) Tag(p.status.label, sky: true),
                            if (p.mustSetPassword) const Tag('Invite not accepted'),
                            if (p.id == currentUserId) const Tag('You'),
                          ],
                          trailing: const Icon(Icons.more_horiz, size: 20),
                          onTap: () => _openActions(p),
                        ),
                    ]),
                  ),
                ],
              ],
            ),
          ),
        );
      }),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(2, Gap.snug, 2, Gap.snug - 2),
          margin: const EdgeInsets.only(right: Gap.page + 2),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: selected ? c.accent : c.canvas, width: 2)),
          ),
          child: Text(label,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: selected ? c.ink : c.inkFaint,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  )),
        ),
      ),
    );
  }
}

class _PendingRow extends StatelessWidget {
  const _PendingRow({required this.profile, required this.onApprove, required this.onReject});
  final Profile profile;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.page - 4, Gap.row, Gap.snug, Gap.row),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(profile.fullName, style: t.titleMedium),
          const SizedBox(height: Gap.hair),
          Text(profile.email ?? '', style: t.bodyMedium),
          const SizedBox(height: Gap.tight),
          Wrap(
            spacing: Gap.tight,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Tag(profile.department ?? 'No department'),
              if (profile.createdAt != null)
                Text('Signed up ${studyDateTime.format(profile.createdAt!)}', style: Mono.of(context, size: 12)),
            ],
          ),
          const SizedBox(height: Gap.snug),
          Wrap(spacing: Gap.tight, runSpacing: Gap.tight, children: [
            FilledButton(onPressed: onApprove, child: const Text('Approve')),
            OutlinedButton(onPressed: onReject, child: const Text('Reject')),
          ]),
        ],
      ),
    );
  }
}

/// What can be done to one account, depending on its status.
class _AccountSheet extends StatelessWidget {
  const _AccountSheet({required this.profile, required this.onAction, required this.onMessage});
  final Profile profile;
  final Future<void> Function(String doneMessage, Future<void> Function() action) onAction;
  final void Function(String message, bool isError) onMessage;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = profile;
    final isMe = p.id == currentUserId;

    Widget action(String label, String done, Future<void> Function() run, {bool primary = false}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: Gap.tight),
          child: primary
              ? FilledButton(onPressed: () => onAction(done, run), child: Text(label))
              : OutlinedButton(onPressed: () => onAction(done, run), child: Text(label)),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.page, Gap.page, Gap.page, Gap.section),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(p.fullName, style: t.titleMedium),
          const SizedBox(height: Gap.hair),
          Text('${p.email ?? ''}  /  ${p.role.label}  /  ${p.status.label}', style: t.bodySmall),
          const SizedBox(height: Gap.page),
          if (isMe)
            Text('This is your own account. Another administrator has to change it.', style: t.bodyMedium)
          else ...[
            if (p.status == AccountStatus.pending) ...[
              action('Approve', '${p.fullName} can now use ZutLib.', () => adminRepo.approve(p.id), primary: true),
              action('Reject', '${p.fullName} was not approved.', () => adminRepo.reject(p.id)),
            ],
            if (p.status == AccountStatus.active)
              action('Suspend', '${p.fullName} is suspended and can no longer use ZutLib.', () => adminRepo.suspend(p.id)),
            if (p.status == AccountStatus.suspended || p.status == AccountStatus.rejected)
              action('Reactivate', '${p.fullName} is active again.', () => adminRepo.reactivate(p.id), primary: true),
            if (p.status == AccountStatus.active) ...[
              const SizedBox(height: Gap.tight),
              Text('Role', style: t.titleSmall),
              const SizedBox(height: Gap.tight),
              Wrap(spacing: Gap.tight, runSpacing: Gap.tight, children: [
                for (final r in UserRole.values)
                  if (r != p.role)
                    OutlinedButton(
                      onPressed: () => onAction('${p.fullName} is now a ${r.label.toLowerCase()}.',
                          () => adminRepo.setRole(p.id, r)),
                      child: Text('Make ${r.label.toLowerCase()}'),
                    ),
              ]),
            ],
            if (p.mustSetPassword) ...[
              const SizedBox(height: Gap.page),
              Text('They have not accepted their invite yet.', style: t.bodyMedium),
              const SizedBox(height: Gap.tight),
              CountdownButton(
                label: 'Resend invite email',
                onPressed: () => adminRepo.resendInvite(p.id),
                onMessage: onMessage,
              ),
            ],
          ],
        ],
      ),
    );
  }
}
