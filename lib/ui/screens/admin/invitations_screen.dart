import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme.dart' show kNavClearance;
import '../../../core/theme/app_theme.dart';
import '../../../models/profile.dart';
import '../../../state/governance_providers.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/notification_bell.dart';
import '../../widgets/study_widgets.dart';

/// People who were invited but have not chosen a password yet. Search,
/// filter by role, a result count and pull to refresh; each opens the
/// person's detail screen, where the invite can be sent again.
class InvitationsScreen extends ConsumerStatefulWidget {
  const InvitationsScreen({super.key});

  @override
  ConsumerState<InvitationsScreen> createState() => _InvitationsScreenState();
}

class _InvitationsScreenState extends ConsumerState<InvitationsScreen> {
  String _query = '';
  UserRole? _role;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(invitationsProvider);
    return StudyScope(
      child: Builder(builder: (context) {
        final t = Theme.of(context).textTheme;
        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: StudyPage(
              bottom: kNavClearance,
              onRefresh: () async {
                ref.invalidate(invitationsProvider);
                try {
                  await ref.read(invitationsProvider.future);
                } catch (_) {
                  // Shown on screen.
                }
              },
              children: [
                Row(children: [
                  const ShellMenuButton(),
                  Expanded(child: Text('Invitations', style: t.headlineSmall)),
                  const NotificationBell(),
                ]),
                const SizedBox(height: Gap.hair),
                Text('Invites that have not been accepted yet.', style: t.bodyMedium),
                const SizedBox(height: Gap.snug),
                Row(children: [
                  Expanded(
                    child: TextField(
                      decoration: const InputDecoration(hintText: 'Search by name or email', prefixIcon: Icon(Icons.search, size: 20)),
                      onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
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
                Wrap(spacing: Gap.tight, runSpacing: Gap.tight, children: [
                  ChoiceChip(label: const Text('All'), selected: _role == null, onSelected: (_) => setState(() => _role = null)),
                  for (final r in const [UserRole.student, UserRole.librarian, UserRole.admin])
                    ChoiceChip(label: Text(r.label), selected: _role == r, onSelected: (_) => setState(() => _role = r)),
                ]),
                const SizedBox(height: Gap.snug),
                StudyAsync<List<Profile>>(
                  value: async,
                  onRetry: () => ref.invalidate(invitationsProvider),
                  skeleton: const RowsSkeleton(rows: 4),
                  isEmpty: (v) => v.isEmpty,
                  empty: const StudyEmptyState('Every invite has been accepted.'),
                  data: (people) {
                    final shown = [
                      for (final p in people)
                        if ((_role == null || p.role == _role) &&
                            (_query.isEmpty ||
                                p.fullName.toLowerCase().contains(_query) ||
                                (p.email ?? '').toLowerCase().contains(_query)))
                          p,
                    ];
                    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Text('${shown.length} of ${people.length} open', style: t.bodySmall),
                      const SizedBox(height: Gap.tight),
                      if (shown.isEmpty)
                        const StudyEmptyState('No invites match.', compact: true)
                      else
                        RowGroup(children: [
                          for (final p in shown)
                            StudyRow(
                              title: p.fullName,
                              detail: p.email,
                              detailLines: 1,
                              meta: p.createdAt == null ? null : 'Invited ${studyDate.format(p.createdAt!)}',
                              tags: [Tag(p.role.label), if (!p.isActive) Tag(p.status.label, sky: true)],
                              trailing: const Icon(Icons.chevron_right, size: 20),
                              onTap: () => context.push('/admin/users/${p.id}'),
                            ),
                        ]),
                    ]);
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
