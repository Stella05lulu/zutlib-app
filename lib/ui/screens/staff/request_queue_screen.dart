import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme.dart';
import '../../../models/borrow_request.dart';
import '../../../state/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/state_views.dart';

const _tabs = <String, Set<BorrowStatus>>{
  'Pending': {BorrowStatus.submitted, BorrowStatus.underReview},
  'Approved': {BorrowStatus.approved},
  'On loan': {BorrowStatus.collected},
  'Closed': {BorrowStatus.returned, BorrowStatus.rejected, BorrowStatus.cancelled},
};

class RequestQueueScreen extends ConsumerWidget {
  const RequestQueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(queueFilterProvider);
    final async = ref.watch(queueProvider);
    final overview = ref.watch(overviewProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Borrowing requests'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () {
              ref.invalidate(queueProvider);
              ref.invalidate(overviewProvider);
            },
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: Insets.sm),
        ],
      ),
      body: Column(
        children: [
          if (overview != null)
            Container(
              color: Palette.surface,
              padding: const EdgeInsets.fromLTRB(
                  Insets.md, 0, Insets.md, Insets.md),
              child: Readable(
                maxWidth: 900,
                child: Row(
                  children: [
                    _Stat('Pending', overview.pending, Palette.warn),
                    _Stat('On loan', overview.collected, Palette.blueDeep),
                    _Stat('Overdue', overview.overdue, Palette.bad),
                    _Stat('Resources', overview.resources, Palette.inkSoft),
                  ],
                ),
              ),
            ),
          Container(
            color: Palette.surface,
            padding: const EdgeInsets.fromLTRB(
                Insets.md, 0, Insets.md, Insets.md),
            child: Readable(
              maxWidth: 900,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final entry in _tabs.entries)
                      Padding(
                        padding: const EdgeInsets.only(right: Insets.sm),
                        child: _Tab(
                          label: entry.key,
                          selected: _sameSet(selected, entry.value),
                          onTap: () => ref
                              .read(queueFilterProvider.notifier)
                              .state = entry.value,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(queueProvider);
                await ref.read(queueProvider.future);
              },
              child: AsyncView<List<BorrowRequest>>(
                value: async,
                onRetry: () => ref.invalidate(queueProvider),
                data: (items) {
                  if (items.isEmpty) {
                    return ListView(children: const [
                      SizedBox(height: 60),
                      EmptyView(
                        icon: Icons.inbox_outlined,
                        headline: 'Nothing here',
                        body: 'No requests are in this state right now.',
                      ),
                    ]);
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                Insets.md, Insets.md, Insets.md, kNavClearance),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: Insets.sm),
                    itemBuilder: (_, i) => Readable(
                      maxWidth: 900,
                      child: _QueueCard(
                        request: items[i],
                        onTap: () => context.push('/staff/request/${items[i].id}'),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

bool _sameSet(Set<BorrowStatus> a, Set<BorrowStatus> b) =>
    a.length == b.length && a.containsAll(b);

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.color);
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$value',
                style: TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.w600,
                  color: color,
                  letterSpacing: -0.6,
                )),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
}

class _Tab extends StatelessWidget {
  const _Tab({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Corners.chip),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? Palette.blueDeep : Palette.canvas,
            borderRadius: BorderRadius.circular(Corners.chip),
            border: Border.all(color: selected ? Palette.blueDeep : Palette.line),
          ),
          child: Text(label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: selected ? Palette.onAccent : Palette.inkSoft,
              )),
        ),
      );
}

class _QueueCard extends StatelessWidget {
  const _QueueCard({required this.request, required this.onTap});
  final BorrowRequest request;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = request.effectiveStatus;
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Corners.card),
        child: Padding(
          padding: const EdgeInsets.all(Insets.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 40, width: 40,
                decoration: BoxDecoration(
                    color: Palette.blueWash, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Text(
                  request.studentName.isEmpty
                      ? '?'
                      : request.studentName[0].toUpperCase(),
                  style: TextStyle(
                      color: Palette.blueDeep, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: Insets.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(request.resourceTitle ?? 'Resource',
                              style: Theme.of(context).textTheme.titleMedium,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                        const SizedBox(width: Insets.sm),
                        StatusChip(status, dense: true),
                      ],
                    ),
                    const SizedBox(height: 3),
                    MetaLine([
                      request.studentName,
                      request.studentNumber,
                      dateFmt.format(request.requestedAt),
                    ]),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
