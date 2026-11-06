import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/failure.dart';
import '../../../core/supabase.dart';
import '../../../core/theme.dart' show kNavClearance;
import '../../../core/theme/app_theme.dart';
import '../../../models/profile.dart';
import '../../../state/governance_providers.dart';
import '../../../state/providers.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/notification_bell.dart';
import '../../widgets/reauth.dart';
import '../../widgets/study_widgets.dart';

/// Every account, by status: All, Pending, Active, Suspended (and Removed,
/// for a super admin). Search, a result count, pull to refresh, and a detail
/// screen for each person. Each change goes through the admin-users Edge
/// Function, which checks the caller's role and writes the audit log.
class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});
  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

/// The status tabs. The first is everyone except removed accounts.
const _tabs = <(String, AccountStatus?)>[
  ('All', null),
  ('Pending', AccountStatus.pending),
  ('Active', AccountStatus.active),
  ('Suspended', AccountStatus.suspended),
  ('Removed', AccountStatus.removed),
];

class _UsersScreenState extends ConsumerState<UsersScreen> {
  String? _message;
  bool _isError = false;
  String _query = '';

  void _show(String message, bool isError) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _isError = isError;
    });
  }

  Future<void> _act(String done, Future<void> Function() action) async {
    if (!await confirmRecentSignIn(context)) return;
    try {
      await action();
      if (!mounted) return;
      refreshAdmin(ref);
      _show(done, false);
    } on Failure catch (f) {
      _show(f.message, true);
    }
  }

  bool _matches(Profile p) {
    final q = _query.trim().toLowerCase();
    return q.isEmpty || p.fullName.toLowerCase().contains(q) || (p.email ?? '').toLowerCase().contains(q);
  }

  static bool _inTab(Profile p, AccountStatus? s) =>
      s == null ? p.status != AccountStatus.removed : p.status == s;

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(profileProvider).valueOrNull;
    final isSuper = me?.role == UserRole.superAdmin;
    final tabs = [for (final x in _tabs) if (x.$2 != AccountStatus.removed || isSuper) x];
    final tab = ref.watch(usersTabProvider).clamp(0, tabs.length - 1);
    final everyone = ref.watch(usersProvider);
    final all = everyone.valueOrNull ?? const <Profile>[];
    int count(AccountStatus? s) => all.where((p) => _inTab(p, s)).length;

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
                refreshAdmin(ref);
                try {
                  await ref.read(usersProvider.future);
                } catch (_) {
                  // Shown on screen.
                }
              },
              children: [
                Row(children: [
                  const ShellMenuButton(),
                  Expanded(child: Text('Users', style: t.headlineSmall)),
                  const NotificationBell(),
                ]),
                const SizedBox(height: Gap.snug),
                Row(children: [
                  Expanded(
                    child: TextField(
                      decoration: const InputDecoration(
                        hintText: 'Search by name or email',
                        prefixIcon: Icon(Icons.search, size: 20),
                      ),
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                  const SizedBox(width: Gap.tight),
                  FilledButton.icon(
                    onPressed: () => context.push('/admin/users/new'),
                    icon: const Icon(Icons.person_add_alt, size: 18),
                    label: const Text('Invite'),
                  ),
                ]),
                const SizedBox(height: Gap.snug),
                Container(
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      for (var i = 0; i < tabs.length; i++)
                        UnderlineTab(
                          label: everyone.hasValue ? '${tabs[i].$1} (${count(tabs[i].$2)})' : tabs[i].$1,
                          selected: tab == i,
                          onTap: () => ref.read(usersTabProvider.notifier).state = i,
                        ),
                    ]),
                  ),
                ),
                if (_message != null) ...[
                  const SizedBox(height: Gap.snug),
                  InlineNotice(_message!, error: _isError, onClose: () => setState(() => _message = null)),
                ],
                const SizedBox(height: Gap.snug),
                StudyAsync<List<Profile>>(
                  value: everyone,
                  onRetry: () => ref.invalidate(usersProvider),
                  skeleton: const RowsSkeleton(rows: 6),
                  data: (people) {
                    final status = tabs[tab].$2;
                    final shown = [for (final p in people) if (_inTab(p, status) && _matches(p)) p];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('${shown.length} ${shown.length == 1 ? 'account' : 'accounts'}', style: t.bodySmall),
                        const SizedBox(height: Gap.tight),
                        if (shown.isEmpty)
                          StudyEmptyState(
                            status == AccountStatus.pending ? 'Nobody is waiting for approval.' : 'No accounts match.',
                            compact: true,
                          )
                        else
                          RowGroup(children: [
                            for (final p in shown)
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
                                trailing: p.status == AccountStatus.pending && p.id != currentUserId
                                    ? Wrap(spacing: Gap.hair, children: [
                                        IconButton(
                                          tooltip: 'Approve ${p.fullName}',
                                          icon: Icon(Icons.check, color: c.success),
                                          onPressed: () =>
                                              _act('${p.fullName} can now use ZutLib.', () => adminRepo.approve(p.id)),
                                        ),
                                        IconButton(
                                          tooltip: 'Reject ${p.fullName}',
                                          icon: Icon(Icons.close, color: c.danger),
                                          onPressed: () =>
                                              _act('${p.fullName} was not approved.', () => adminRepo.reject(p.id)),
                                        ),
                                      ])
                                    : const Icon(Icons.chevron_right, size: 20),
                                onTap: () => context.push('/admin/users/${p.id}'),
                              ),
                          ]),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

/// A tab with a thin underline in the accent colour when selected.
class UnderlineTab extends StatelessWidget {
  const UnderlineTab({super.key, required this.label, required this.selected, required this.onTap});
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
          constraints: const BoxConstraints(minHeight: 48),
          alignment: Alignment.center,
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
