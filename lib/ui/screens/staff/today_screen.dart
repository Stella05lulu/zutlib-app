import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme.dart' show kNavClearance;
import '../../../core/theme/app_theme.dart';
import '../../../data/governance_repository.dart';
import '../../../state/governance_providers.dart';
import '../../../state/providers.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/notification_bell.dart';
import '../../widgets/shelves.dart';
import '../../widgets/study_widgets.dart';

/// The librarian's day: requests waiting for a decision, collections due,
/// overdue copies and books with no copy on the shelf. Live counts.
class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(libraryTodayProvider);
    final profile = ref.watch(profileProvider).valueOrNull;
    return StudyScope(
      child: Builder(builder: (context) {
        final t = Theme.of(context).textTheme;
        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: StudyPage(
              bottom: kNavClearance,
              onRefresh: () async {
                ref.invalidate(libraryTodayProvider);
                try {
                  await ref.read(libraryTodayProvider.future);
                } catch (_) {
                  // Shown on the page.
                }
              },
              children: [
                Row(children: [
                  const ShellMenuButton(),
                  Expanded(child: Text('Today', style: t.headlineSmall)),
                  const NotificationBell(),
                ]),
                Text(
                  [
                    DateFormat('EEEE d MMMM').format(DateTime.now()),
                    if (profile != null) profile.fullName,
                  ].join('  /  '),
                  style: t.bodyMedium,
                ),
                const SizedBox(height: Gap.page),
                StudyAsync<LibraryToday>(
                  value: async,
                  onRetry: () => ref.invalidate(libraryTodayProvider),
                  skeleton: const RowsSkeleton(rows: 6),
                  data: (d) => _Body(d: d),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.d});
  final LibraryToday d;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('d MMM');
    Widget list(String title, int count, List<TodayItem> items, String empty, Widget Function(TodayItem) row,
        {VoidCallback? onSeeAll}) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ShelfHeading('$title ($count)', onSeeAll: count > items.length ? onSeeAll : null),
          if (items.isEmpty)
            StudyEmptyState(empty, compact: true)
          else
            RowGroup(children: [for (final i in items) row(i)]),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StatGrid(children: [
          StatTile(value: '${d.waitingCount}', label: 'Waiting for a decision', onTap: () => context.go('/staff/requests')),
          StatTile(value: '${d.collectionsCount}', label: 'Collections due today'),
          StatTile(
            value: '${d.overdueCount}',
            label: 'Overdue copies',
            detail: d.overdueCount > 0 ? 'Follow up' : null,
            alert: d.overdueCount > 0,
          ),
          StatTile(value: '${d.lowStockCount}', label: 'Books with none on the shelf'),
        ]),
        list('Waiting for a decision', d.waitingCount, d.waiting, 'No requests are waiting.',
            (i) => StudyRow(
                  title: i.title,
                  detail: '${i.studentName ?? 'A student'}  /  asked ${i.date == null ? '' : fmt.format(i.date!)}',
                  detailLines: 1,
                  tags: [Tag(i.status == 'under_review' ? 'Under review' : 'New')],
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () => context.push('/staff/request/${i.id}'),
                ),
            onSeeAll: () => context.go('/staff/requests')),
        list('Collections due today', d.collectionsCount, d.collections, 'Nobody is due to collect today.',
            (i) => StudyRow(
                  title: i.title,
                  detail: '${i.studentName ?? 'A student'}  /  collect by ${i.date == null ? 'today' : fmt.format(i.date!)}',
                  detailLines: 1,
                  tags: const [Tag('Approved')],
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () => context.push('/staff/request/${i.id}'),
                )),
        list('Overdue copies', d.overdueCount, d.overdue, 'Nothing is overdue.',
            (i) => StudyRow(
                  title: i.title,
                  detail: '${i.studentName ?? 'A student'}  /  was due ${i.date == null ? '' : fmt.format(i.date!)}',
                  detailLines: 1,
                  tags: const [Tag('Overdue')],
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () => context.push('/staff/request/${i.id}'),
                )),
        list('Books with none on the shelf', d.lowStockCount, d.lowStock, 'Every book has a copy on the shelf.',
            (i) => StudyRow(
                  title: i.title,
                  detail: i.detail,
                  detailLines: 1,
                  tags: const [Tag('0 available')],
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () => context.push('/resource/${i.id}'),
                )),
      ],
    );
  }
}
