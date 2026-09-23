import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/failure.dart';
import '../../../core/theme.dart';
import '../../../models/borrow_request.dart';
import '../../../state/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/state_views.dart';

final _requestProvider =
    FutureProvider.family<BorrowRequest?, String>((ref, id) async {
  final all = await borrowRepo.queue();
  for (final r in all) {
    if (r.id == id) return r;
  }
  return null;
});

/// The decision screen. Staff see the verified identity the roll supplied,
/// then approve or reject. Nothing about identity is entered here.
class RequestDetailScreen extends ConsumerStatefulWidget {
  const RequestDetailScreen({super.key, required this.requestId});
  final String requestId;

  @override
  ConsumerState<RequestDetailScreen> createState() => _RequestDetailScreenState();
}

class _RequestDetailScreenState extends ConsumerState<RequestDetailScreen> {
  bool _busy = false;

  Future<void> _act(String action, {String? reason}) async {
    setState(() => _busy = true);
    try {
      await borrowRepo.decide(
          requestId: widget.requestId, action: action, reason: reason);
      refreshBorrowing(ref);
      ref.invalidate(_requestProvider(widget.requestId));
      if (!mounted) return;
      showMessage(context, switch (action) {
        'approve' => 'Approved. A copy is reserved and the student has been emailed.',
        'reject' => 'Rejected. The student has been emailed the reason.',
        'collect' => 'Collection recorded. The due date is set.',
        'return' => 'Return recorded. The copy is back on the shelf.',
        _ => 'Updated.',
      });
    } on Failure catch (f) {
      if (mounted) showMessage(context, f.message, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reject this request'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('The student will see this reason in the app and in '
                'their email.'),
            const SizedBox(height: Insets.md),
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'e.g. Outstanding overdue item on your account',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Back')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Reject request'),
          ),
        ],
      ),
    );
    if (reason == null || reason.isEmpty) return;
    await _act('reject', reason: reason);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_requestProvider(widget.requestId));

    return Scaffold(
      appBar: AppBar(title: const Text('Request')),
      body: AsyncView<BorrowRequest?>(
        value: async,
        onRetry: () => ref.invalidate(_requestProvider(widget.requestId)),
        data: (r) {
          if (r == null) {
            return const ErrorView(message: 'That request no longer exists.');
          }
          final status = r.effectiveStatus;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(Insets.md),
            child: Readable(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(r.resourceTitle ?? 'Resource',
                            style: Theme.of(context).textTheme.headlineSmall),
                      ),
                      const SizedBox(width: Insets.sm),
                      StatusChip(status),
                    ],
                  ),
                  const SizedBox(height: Insets.xs),
                  MetaLine([r.courseCode ?? '']),

                  const SectionHeading('Verified requester'),
                  Card(
                    child: Column(
                      children: [
                        _Row('Name', r.studentName),
                        const Divider(height: 1),
                        _Row('Student number', r.studentNumber),
                        const Divider(height: 1),
                        _Row('Programme', r.programme ?? ''),
                      ],
                    ),
                  ),
                  const SizedBox(height: Insets.sm),
                  Row(
                    children: [
                      Icon(Icons.verified_outlined,
                          size: 15, color: Palette.good),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          'Checked against the institutional roll when the '
                          'account was created.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),

                  const SectionHeading('Timeline'),
                  Card(
                    child: Column(
                      children: [
                        _Row('Requested', dateTimeFmt.format(r.requestedAt)),
                        if (r.collectionDate != null) ...[
                          const Divider(height: 1),
                          _Row('Wants to collect', dateFmt.format(r.collectionDate!)),
                        ],
                        if (r.decidedAt != null) ...[
                          const Divider(height: 1),
                          _Row('Decided', dateTimeFmt.format(r.decidedAt!)),
                        ],
                        if (r.dueDate != null) ...[
                          const Divider(height: 1),
                          _Row('Due back', dateFmt.format(r.dueDate!)),
                        ],
                        if (r.returnedAt != null) ...[
                          const Divider(height: 1),
                          _Row('Returned', dateTimeFmt.format(r.returnedAt!)),
                        ],
                      ],
                    ),
                  ),

                  if (r.rejectionReason != null) ...[
                    const SectionHeading('Reason given'),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(Insets.md),
                      decoration: BoxDecoration(
                        color: Palette.badWash,
                        borderRadius: BorderRadius.circular(Corners.field),
                      ),
                      child: Text(r.rejectionReason!,
                          style: TextStyle(
                              color: Palette.bad, height: 1.45)),
                    ),
                  ],

                  const SizedBox(height: Insets.lg),
                  if (_busy)
                    const Center(child: CircularProgressIndicator())
                  else
                    ..._actions(status),
                  const SizedBox(height: Insets.xl),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _actions(BorrowStatus status) => switch (status) {
        BorrowStatus.submitted || BorrowStatus.underReview => [
            FilledButton.icon(
              onPressed: () => _act('approve'),
              icon: const Icon(Icons.check),
              label: const Text('Approve and reserve a copy'),
            ),
            const SizedBox(height: Insets.sm),
            OutlinedButton.icon(
              onPressed: _reject,
              icon: const Icon(Icons.close),
              label: const Text('Reject'),
            ),
          ],
        BorrowStatus.approved => [
            FilledButton.icon(
              onPressed: () => _act('collect'),
              icon: const Icon(Icons.outbound_outlined),
              label: const Text('Record collection'),
            ),
          ],
        BorrowStatus.collected || BorrowStatus.overdue => [
            FilledButton.icon(
              onPressed: () => _act('return'),
              icon: const Icon(Icons.assignment_turned_in_outlined),
              label: const Text('Record return'),
            ),
          ],
        _ => [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(Insets.md),
              decoration: BoxDecoration(
                color: Palette.canvas,
                borderRadius: BorderRadius.circular(Corners.field),
                border: Border.all(color: Palette.line),
              ),
              child: Text('This request is closed. Nothing more to do.',
                  style: Theme.of(context).textTheme.bodyMedium),
            ),
          ],
      };
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);
  final String label, value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: Insets.md, vertical: 13),
        child: Row(
          children: [
            SizedBox(
                width: 140,
                child: Text(label,
                    style: Theme.of(context).textTheme.bodyMedium)),
            Expanded(
                child: Text(value,
                    style: const TextStyle(fontWeight: FontWeight.w600))),
          ],
        ),
      );
}
