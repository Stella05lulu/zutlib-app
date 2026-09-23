import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/failure.dart';
import '../../../core/theme.dart';
import '../../../models/borrow_request.dart';
import '../../../state/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/state_views.dart';

class MyBorrowingScreen extends ConsumerWidget {
  const MyBorrowingScreen({super.key});

  Future<void> _cancel(BuildContext context, WidgetRef ref, BorrowRequest r) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancel this request?'),
        content: Text('Your request for "${r.resourceTitle}" will be withdrawn. '
            'You can apply again later.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep it')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Cancel request')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await borrowRepo.cancel(r.id);
      refreshBorrowing(ref);
      if (context.mounted) showMessage(context, 'Request cancelled.');
    } on Failure catch (f) {
      if (context.mounted) showMessage(context, f.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myBorrowingProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My borrowing')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(myBorrowingProvider);
          await ref.read(myBorrowingProvider.future);
        },
        child: AsyncView<List<BorrowRequest>>(
          value: async,
          onRetry: () => ref.invalidate(myBorrowingProvider),
          data: (all) {
            if (all.isEmpty) {
              return ListView(children: [
                const SizedBox(height: 60),
                EmptyView(
                  icon: Icons.import_contacts_outlined,
                  headline: 'Nothing borrowed yet',
                  body: 'Find a physical copy in the library and apply for it. '
                      'Your requests and their status will show up here.',
                  action: FilledButton(
                    onPressed: () => context.go('/browse'),
                    child: const Text('Browse the library'),
                  ),
                ),
              ]);
            }

            final live = all.where((r) => r.effectiveStatus.isLive).toList();
            final past = all.where((r) => !r.effectiveStatus.isLive).toList();

            return ListView(
              padding: const EdgeInsets.fromLTRB(
                Insets.md, Insets.md, Insets.md, kNavClearance),
              children: [
                Readable(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (live.isNotEmpty) ...[
                        Text('Active',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: Insets.sm),
                        for (final r in live)
                          Padding(
                            padding: const EdgeInsets.only(bottom: Insets.sm),
                            child: _RequestCard(
                              request: r,
                              onCancel: r.status == BorrowStatus.submitted
                                  ? () => _cancel(context, ref, r)
                                  : null,
                            ),
                          ),
                      ],
                      if (past.isNotEmpty) ...[
                        const SectionHeading('History'),
                        for (final r in past)
                          Padding(
                            padding: const EdgeInsets.only(bottom: Insets.sm),
                            child: _RequestCard(request: r),
                          ),
                      ],
                      const SizedBox(height: Insets.xl),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.request, this.onCancel});
  final BorrowRequest request;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final status = request.effectiveStatus;
    final days = request.daysUntilDue;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Insets.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(request.resourceTitle ?? 'Resource',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                const SizedBox(width: Insets.sm),
                StatusChip(status),
              ],
            ),
            const SizedBox(height: 3),
            MetaLine([
              request.courseCode ?? '',
              'Requested ${dateFmt.format(request.requestedAt)}',
            ]),
            const SizedBox(height: Insets.sm),
            Text(status.explanation,
                style: Theme.of(context).textTheme.bodyMedium),
            if (status == BorrowStatus.rejected &&
                request.rejectionReason != null) ...[
              const SizedBox(height: Insets.sm),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: Palette.badWash,
                  borderRadius: BorderRadius.circular(Corners.field),
                ),
                child: Text(request.rejectionReason!,
                    style: TextStyle(
                        color: Palette.bad, fontSize: 13, height: 1.4)),
              ),
            ],
            if (request.dueDate != null &&
                (status == BorrowStatus.collected ||
                    status == BorrowStatus.overdue)) ...[
              const SizedBox(height: Insets.sm),
              Row(
                children: [
                  Icon(Icons.event_outlined, size: 15, color: status.fg),
                  const SizedBox(width: 5),
                  Text(
                    days != null && days < 0
                        ? 'Due ${dateFmt.format(request.dueDate!)}, '
                            '${-days} ${-days == 1 ? "day" : "days"} ago'
                        : 'Due ${dateFmt.format(request.dueDate!)}'
                            '${days != null ? ", in $days ${days == 1 ? "day" : "days"}" : ""}',
                    style: TextStyle(
                        color: status.fg,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ],
            if (onCancel != null) ...[
              const SizedBox(height: Insets.sm),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                    onPressed: onCancel, child: const Text('Cancel request')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
