import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/failure.dart';
import '../../../core/theme.dart';
import '../../../models/app_notification.dart';
import '../../../state/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/state_views.dart';

/// Decisions on borrowing requests, newest first. Written by the
/// decide-request function; the student can only mark them read.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  Future<void> _markAllRead(BuildContext context, WidgetRef ref) async {
    try {
      await notificationRepo.markAllRead();
      ref.invalidate(notificationsProvider);
    } on Failure catch (f) {
      if (context.mounted) showMessage(context, f.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(notificationsProvider);
    final unread = ref.watch(unreadCountProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Updates'),
        actions: [
          if (unread > 0)
            TextButton(
              onPressed: () => _markAllRead(context, ref),
              child: const Text('Mark all read'),
            ),
          const SizedBox(width: Insets.sm),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(notificationsProvider);
          await ref.read(notificationsProvider.future);
        },
        child: AsyncView<List<AppNotification>>(
          value: async,
          onRetry: () => ref.invalidate(notificationsProvider),
          data: (items) {
            if (items.isEmpty) {
              return ListView(children: const [
                SizedBox(height: 60),
                EmptyView(
                  icon: Icons.notifications_none_rounded,
                  headline: 'No updates yet',
                  body: 'When a librarian approves, rejects or records one of '
                      'your borrowing requests, it will show up here.',
                ),
              ]);
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(
                  Insets.md, Insets.md, Insets.md, kNavClearance),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: Insets.sm),
              itemBuilder: (_, i) => Readable(child: _NoticeCard(items[i])),
            );
          },
        ),
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard(this.n);
  final AppNotification n;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Insets.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6, right: Insets.sm),
              child: Container(
                height: 8,
                width: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: n.isUnread ? Palette.blue : Colors.transparent,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(n.subject,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(n.body, style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 6),
                  Text(dateTimeFmt.format(n.createdAt),
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
