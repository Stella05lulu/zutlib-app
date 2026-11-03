import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme.dart' show kNavClearance;
import '../../../core/theme/app_theme.dart';
import '../../../data/admin_repository.dart';
import '../../../state/providers.dart';
import '../../widgets/study_widgets.dart';
import '../../widgets/notification_bell.dart';
import '../../../state/plan_providers.dart' show accountRepo;
import '../../../data/account_repository.dart' show FeedbackItem;

/// The administrator's overview: who is waiting, who is active, what the
/// library holds, and the latest administrator actions. The counts come
/// from admin_overview(), which refuses anyone who is not an active admin.
class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(adminOverviewProvider);
    final audit = ref.watch(auditProvider);

    Future<void> refresh() async {
      refreshUsers(ref);
      try {
        await ref.read(adminOverviewProvider.future);
      } catch (_) {
        // Shown on screen.
      }
    }

    return StudyScope(
      child: Builder(builder: (context) {
        final t = Theme.of(context).textTheme;
        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: StudyPage(
              bottom: kNavClearance,
              onRefresh: refresh,
              children: [
                const SizedBox(height: Gap.tight),
                Row(children: [
                  Expanded(child: Text('Dashboard', style: t.headlineSmall)),
                  const NotificationBell(),
                ]),
                const SizedBox(height: Gap.hair + 2),
                Text('Accounts, the library and recent administrator actions.', style: t.bodyMedium),
                const SizedBox(height: Gap.page),
                Wrap(spacing: Gap.tight, runSpacing: Gap.tight, children: [
                  FilledButton.icon(
                    onPressed: () => context.push('/admin/users/new'),
                    icon: const Icon(Icons.person_add_alt, size: 18),
                    label: const Text('Create account'),
                  ),
                  OutlinedButton(
                    onPressed: () {
                      ref.read(usersTabProvider.notifier).state = 0;
                      context.go('/admin/users');
                    },
                    child: const Text('Review waiting students'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => context.push('/admin/reports'),
                    icon: const Icon(Icons.insights_outlined, size: 18),
                    label: const Text('Reports'),
                  ),
                ]),
                StudyAsync<AdminOverview>(
                  value: overview,
                  onRetry: () => ref.invalidate(adminOverviewProvider),
                  skeleton: const Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SectionLabel('People'),
                      RowsSkeleton(rows: 4, detail: false),
                      SectionLabel('Library'),
                      RowsSkeleton(rows: 4, detail: false),
                    ],
                  ),
                  data: (o) => _Figures(o: o),
                ),
                const _FeedbackSection(),
                const SectionLabel('Recent administrator actions'),
                StudyAsync<List<AuditEntry>>(
                  value: audit,
                  onRetry: () => ref.invalidate(auditProvider),
                  skeleton: const RowsSkeleton(rows: 3, detail: false),
                  isEmpty: (v) => v.isEmpty,
                  empty: const StudyEmptyState('No administrator actions yet.', compact: true),
                  data: (items) => RowGroup(children: [
                    for (final e in items.take(15))
                      StudyRow(
                        title: e.label,
                        detail: [
                          if (e.actorName != null) 'by ${e.actorName}',
                          if (e.detail['email'] != null) '${e.detail['email']}',
                          if (e.detail['role_to'] != null && e.action == 'admin.set_role')
                            'now ${e.detail['role_to']}',
                        ].join(', '),
                        meta: studyDateTime.format(e.at),
                      ),
                  ]),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

class _Figures extends ConsumerWidget {
  const _Figures({required this.o});
  final AdminOverview o;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void openUsers(int tab) {
      ref.read(usersTabProvider.notifier).state = tab;
      context.go('/admin/users');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('People'),
        RowGroup(children: [
          _Figure('Students waiting for approval', o.pendingStudents,
              highlight: o.pendingStudents > 0, onTap: () => openUsers(0)),
          _Figure('Active students', o.activeStudents, onTap: () => openUsers(1)),
          _Figure('Librarians', o.librarians, onTap: () => openUsers(1)),
          _Figure('Administrators', o.admins, onTap: () => openUsers(1)),
          _Figure('Suspended or rejected accounts', o.suspendedAccounts, onTap: () => openUsers(1)),
        ]),
        const SectionLabel('Library'),
        RowGroup(children: [
          _Figure('Books in the catalogue', o.books,
              note: o.sampleBooks > 0 ? '${o.sampleBooks} sample' : null, onTap: () => context.go('/staff/library')),
          _Figure('Past and test papers', o.papers,
              note: o.samplePapers > 0 ? '${o.samplePapers} sample' : null, onTap: () => context.go('/staff/library')),
          _Figure('Open borrowing requests', o.openRequests, onTap: () => context.go('/staff/requests')),
          _Figure('Overdue loans', o.overdueRequests, highlight: o.overdueRequests > 0,
              onTap: () => context.go('/staff/requests')),
        ]),
      ],
    );
  }
}

/// One figure: a label on the left, the number in the mono face on the right.
class _Figure extends StatelessWidget {
  const _Figure(this.label, this.value, {this.note, this.highlight = false, this.onTap});
  final String label;
  final int value;
  final String? note;
  final bool highlight;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.page - 4, Gap.row, Gap.page - 4, Gap.row),
        child: Row(
          children: [
            Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: c.ink))),
            if (note != null) ...[Tag(note!), const SizedBox(width: Gap.snug)],
            Text('$value',
                style: Mono.of(context, size: 17, weight: FontWeight.w600, color: highlight ? c.accent : c.ink)),
          ],
        ),
      ),
    );
  }
}

final _feedbackProvider = FutureProvider.autoDispose<List<FeedbackItem>>((ref) => accountRepo.feedback(limit: 20));

/// Feedback sent from Account, Send feedback: newest first, open ones on top.
class _FeedbackSection extends ConsumerWidget {
  const _FeedbackSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_feedbackProvider);
    final c = StudyColors.of(context);
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Feedback'),
        StudyAsync<List<FeedbackItem>>(
          value: async,
          onRetry: () => ref.invalidate(_feedbackProvider),
          skeleton: const RowsSkeleton(rows: 2, detail: false),
          isEmpty: (v) => v.isEmpty,
          empty: const StudyEmptyState('No feedback yet. Students and staff send it from Account.', compact: true),
          data: (items) {
            final sorted = [...items]..sort((a, b) => a.resolved == b.resolved ? 0 : (a.resolved ? 1 : -1));
            return RowGroup(children: [
              for (final f in sorted.take(10))
                Padding(
                  padding: const EdgeInsets.fromLTRB(Gap.page - 4, Gap.snug, Gap.tight, Gap.snug),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(f.message,
                                style: t.bodyLarge?.copyWith(color: f.resolved ? c.inkFaint : c.ink)),
                            const SizedBox(height: 2),
                            Text(
                              [
                                if (f.role != null) f.role!,
                                studyDateTime.format(f.createdAt),
                                if (f.appVersion != null) 'app ${f.appVersion}',
                              ].join('  /  '),
                              style: t.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          await accountRepo.resolveFeedback(f.id, !f.resolved);
                          ref.invalidate(_feedbackProvider);
                        },
                        child: Text(f.resolved ? 'Reopen' : 'Mark done'),
                      ),
                    ],
                  ),
                ),
            ]);
          },
        ),
      ],
    );
  }
}
