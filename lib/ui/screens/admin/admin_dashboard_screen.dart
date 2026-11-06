import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/failure.dart';
import '../../../core/theme.dart' show kNavClearance;
import '../../../core/theme/app_theme.dart';
import '../../../data/governance_repository.dart';
import '../../../state/governance_providers.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/common.dart' show showMessage;
import '../../widgets/charts.dart';
import '../../widgets/notification_bell.dart';
import '../../widgets/reauth.dart';
import '../../widgets/shelves.dart';
import '../../widgets/audit_activity.dart';
import '../../widgets/study_widgets.dart';
import '../../../state/plan_providers.dart' show accountRepo;
import '../../../data/account_repository.dart' show FeedbackItem;
import '../../../state/providers.dart' show adminRepo, usersTabProvider;

/// The administrator's Overview: the key numbers, the borrowing trend by
/// week or month, where requests stand, what the library holds by
/// department, the latest pending approvals and audit events. Everything
/// comes from admin_dashboard() (0021), which refuses anyone who is not an
/// active administrator.
class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(adminDashboardProvider);

    Future<void> refresh() async {
      refreshAdmin(ref);
      ref.invalidate(_feedbackProvider);
      try {
        await ref.read(adminDashboardProvider.future);
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
              maxWidth: 980,
              onRefresh: refresh,
              children: [
                Row(children: [
                  const ShellMenuButton(),
                  Expanded(child: Text('Overview', style: t.headlineSmall)),
                  const NotificationBell(),
                ]),
                const SizedBox(height: Gap.hair),
                Text('Accounts, borrowing and the library, as of now.', style: t.bodyMedium),
                const SizedBox(height: Gap.page),
                Wrap(spacing: Gap.tight, runSpacing: Gap.tight, children: [
                  FilledButton.icon(
                    onPressed: () => context.push('/admin/users/new'),
                    icon: const Icon(Icons.person_add_alt, size: 18),
                    label: const Text('Create account'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => context.push('/admin/reports'),
                    icon: const Icon(Icons.insights_outlined, size: 18),
                    label: const Text('Reports'),
                  ),
                ]),
                const SizedBox(height: Gap.page),
                StudyAsync<AdminDashboardData>(
                  value: async,
                  onRetry: () => ref.invalidate(adminDashboardProvider),
                  skeleton: const Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        Expanded(child: Bone(height: 72)),
                        SizedBox(width: Gap.tight),
                        Expanded(child: Bone(height: 72)),
                        SizedBox(width: Gap.tight),
                        Expanded(child: Bone(height: 72)),
                      ]),
                      SizedBox(height: Gap.section),
                      Bone(height: 200),
                      SizedBox(height: Gap.section),
                      RowsSkeleton(rows: 4),
                    ],
                  ),
                  data: (d) => _Body(d: d),
                ),
                const _FeedbackSection(),
              ],
            ),
          ),
        );
      }),
    );
  }
}

String _statusLabel(String s) => switch (s) {
      'submitted' => 'Submitted',
      'under_review' => 'Under review',
      'approved' => 'Approved',
      'rejected' => 'Rejected',
      'collected' => 'On loan',
      'overdue' => 'Overdue',
      'returned' => 'Returned',
      'cancelled' => 'Cancelled',
      _ => s,
    };

class _Body extends ConsumerWidget {
  const _Body({required this.d});
  final AdminDashboardData d;

  Future<void> _approve(BuildContext context, WidgetRef ref, PendingPerson p) async {
    if (!await confirmRecentSignIn(context)) return;
    try {
      await adminRepo.approve(p.id);
      refreshAdmin(ref);
      if (context.mounted) showMessage(context, '${p.fullName} can now use ZutLib.');
    } on Failure catch (f) {
      if (context.mounted) showMessage(context, f.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final c = StudyColors.of(context);
    final monthly = ref.watch(dashboardMonthlyProvider);
    final fmt = DateFormat(monthly ? 'MMM' : 'd MMM');
    final statusTotal = d.statuses.values.fold<int>(0, (a, b) => a + b);
    final deptTotal = d.departments.fold<int>(0, (a, b) => a + b.$2);
    const order = ['submitted', 'under_review', 'approved', 'collected', 'overdue', 'returned', 'rejected', 'cancelled'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StatGrid(children: [
          StatTile(value: '${d.totalUsers}', label: 'Total users', onTap: () => context.go('/admin/users')),
          StatTile(
            value: '${d.pending}',
            label: 'Pending approvals',
            detail: d.pending > 0 ? 'Waiting for you' : null,
            alert: d.pending > 0,
            onTap: () {
              ref.read(usersTabProvider.notifier).state = 1;
              context.go('/admin/users');
            },
          ),
          StatTile(value: '${d.activeBorrows}', label: 'Active borrows', onTap: () => context.go('/staff/requests')),
          StatTile(
            value: '${d.overdue}',
            label: 'Overdue borrows',
            detail: d.overdue > 0 ? 'Follow up' : null,
            alert: d.overdue > 0,
            onTap: () => context.go('/staff/requests'),
          ),
          StatTile(value: '${d.resources}', label: 'Total resources', onTap: () => context.go('/staff/library')),
        ]),
        const SizedBox(height: Gap.section),
        const AuditActivity(),
        Padding(
          padding: const EdgeInsets.only(top: Gap.section, bottom: Gap.snug),
          child: Row(children: [
            Expanded(child: Text('Borrowing trend', style: t.titleLarge)),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, label: Text('Week')),
                ButtonSegment(value: true, label: Text('Month')),
              ],
              selected: {monthly},
              onSelectionChanged: (s) => ref.read(dashboardMonthlyProvider.notifier).state = s.first,
            ),
          ]),
        ),
        Panel(
          child: d.trend.every((p) => p.count == 0)
              ? Text('No borrow requests in this period yet.', style: t.bodyMedium)
              : BarChart(
                  semanticLabel: monthly ? 'Borrow requests per month' : 'Borrow requests per week',
                  data: [for (final p in d.trend) BarDatum(fmt.format(p.start), p.count.toDouble())],
                ),
        ),
        Text(monthly ? 'Requests made each month, last 6 months.' : 'Requests made each week, last 8 weeks.',
            style: t.bodySmall),
        const ShelfHeading('Where requests stand'),
        Panel(
          child: statusTotal == 0
              ? Text('No borrow requests yet.', style: t.bodyMedium)
              : Column(children: [
                  for (final s in order)
                    if ((d.statuses[s] ?? 0) > 0)
                      CountBar(
                        label: _statusLabel(s),
                        count: d.statuses[s]!,
                        total: statusTotal,
                        color: s == 'overdue' ? c.warn : null,
                      ),
                ]),
        ),
        const ShelfHeading('Resources by department'),
        Panel(
          child: d.departments.isEmpty
              ? Text('The catalogue is empty.', style: t.bodyMedium)
              : Column(children: [
                  for (final (dept, n) in d.departments) CountBar(label: dept, count: n, total: deptTotal),
                ]),
        ),
        ShelfHeading('Pending approvals', onSeeAll: () => context.go('/admin/users')),
        if (d.pendingPeople.isEmpty)
          const StudyEmptyState('Nobody is waiting for approval.', compact: true)
        else
          RowGroup(children: [
            for (final p in d.pendingPeople)
              Padding(
                padding: const EdgeInsets.fromLTRB(Gap.page - 4, Gap.snug, Gap.snug, Gap.snug),
                child: Row(children: [
                  InitialsAvatar(_initials(p.fullName), size: 36),
                  const SizedBox(width: Gap.snug),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(p.fullName, style: t.titleMedium),
                      Text([p.department ?? 'No department', if (p.createdAt != null) 'signed up ${daysAgo(p.createdAt!)}']
                          .join('  /  '), style: t.bodySmall),
                    ]),
                  ),
                  const SizedBox(width: Gap.tight),
                  Wrap(spacing: Gap.tight, children: [
                    FilledButton(onPressed: () => _approve(context, ref, p), child: const Text('Approve')),
                    OutlinedButton(onPressed: () => context.push('/admin/users/${p.id}'), child: const Text('Review')),
                  ]),
                ]),
              ),
          ]),
        ShelfHeading('Latest audit events', onSeeAll: () => context.go('/admin/audit')),
        if (d.audit.isEmpty)
          const StudyEmptyState('Nothing in the audit log yet.', compact: true)
        else
          RowGroup(children: [
            for (final e in d.audit)
              StudyRow(
                title: e.label,
                detail: [if (e.actorName != null) 'by ${e.actorName}' else 'by the system', if (e.detail['reason'] != null) '${e.detail['reason']}']
                    .join('  /  '),
                detailLines: 1,
                meta: studyDateTime.format(e.at),
              ),
          ]),
      ],
    );
  }
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((x) => x.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
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
