import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/failure.dart';
import '../../../core/router.dart' show openLink;
import '../../../core/theme.dart';
import '../../../models/app_notification.dart';
import '../../../data/governance_repository.dart' show Announcement;
import '../../../state/governance_providers.dart';
import '../../../state/providers.dart';
import '../../widgets/shelves.dart' show Panel;
import '../../widgets/common.dart';
import '../../widgets/state_views.dart';

/// Announcements from the library first, then everything the bell holds,
/// newest first: borrowing decisions, due-date
/// reminders, new papers for your courses, exam reminders and, for staff,
/// new requests and sign-ups. Tapping one marks it read and opens it.
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

  Future<void> _open(BuildContext context, WidgetRef ref, AppNotification n) async {
    if (n.isUnread) {
      try {
        await notificationRepo.markRead(n.id);
        ref.invalidate(notificationsProvider);
      } on Failure {
        // Opening still works if marking read failed.
      }
    }
    final link = n.link;
    if (link != null && link.startsWith('/') && context.mounted) {
      await openLink(context, link);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(notificationsLiveProvider);
    final async = ref.watch(notificationsProvider);
    final unread = ref.watch(unreadCountProvider);
    final notices = [
      for (final a in ref.watch(announcementsProvider).valueOrNull ?? const <Announcement>[])
        if (!a.hasEnded) a,
    ];
    final t = Theme.of(context).textTheme;
    final header = <Widget>[
      if (notices.isNotEmpty) ...[
        Readable(child: SizedBox(width: double.infinity, child: Text('Announcements', style: t.titleLarge))),
        const SizedBox(height: Insets.sm),
        for (final a in notices) ...[Readable(child: _AnnouncementCard(a)), const SizedBox(height: Insets.sm)],
        const SizedBox(height: Insets.md),
        Readable(child: SizedBox(width: double.infinity, child: Text('Notifications', style: t.titleLarge))),
        const SizedBox(height: Insets.sm),
      ],
    ];

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
          ref.invalidate(announcementsProvider);
          await ref.read(notificationsProvider.future);
        },
        child: AsyncView<List<AppNotification>>(
          value: async,
          onRetry: () => ref.invalidate(notificationsProvider),
          data: (items) {
            if (items.isEmpty) {
              return ListView(
                  padding: const EdgeInsets.fromLTRB(Insets.md, Insets.md, Insets.md, kNavClearance),
                  children: [
                ...header,
                SizedBox(height: header.isEmpty ? 60 : Insets.md),
                const EmptyView(
                  icon: Icons.notifications_none_rounded,
                  headline: 'No notifications yet',
                  body: 'Borrowing decisions, due-date reminders, new papers for your courses '
                      'and exam reminders will show up here.',
                ),
              ]);
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(Insets.md, Insets.md, Insets.md, kNavClearance),
              children: [
                ...header,
                for (final n in items) ...[
                  Readable(child: _NoticeCard(n, onTap: () => _open(context, ref, n))),
                  const SizedBox(height: Insets.sm),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

IconData _iconFor(String kind) => switch (kind) {
      'borrow' => Icons.library_books_outlined,
      'due' => Icons.event_outlined,
      'upload' => Icons.description_outlined,
      'study' => Icons.school_outlined,
      'staff' => Icons.inbox_outlined,
      'admin' => Icons.person_add_alt,
      _ => Icons.notifications_none_rounded,
    };

class _NoticeCard extends StatelessWidget {
  const _NoticeCard(this.n, {required this.onTap});
  final AppNotification n;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final urgent = n.kind == 'due' && n.subject.startsWith('Overdue');
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Insets.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 36,
                width: 36,
                decoration: BoxDecoration(
                  color: urgent ? Palette.badWash : Palette.blueWash,
                  borderRadius: BorderRadius.circular(Corners.field),
                ),
                child: Icon(_iconFor(n.kind), size: 19, color: urgent ? Palette.bad : Palette.blueDeep),
              ),
              const SizedBox(width: Insets.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(n.subject,
                              style: t.titleMedium?.copyWith(
                                  fontWeight: n.isUnread ? FontWeight.w600 : FontWeight.w500)),
                        ),
                        if (n.isUnread)
                          Container(
                            height: 8,
                            width: 8,
                            margin: const EdgeInsets.only(left: Insets.sm),
                            decoration: BoxDecoration(shape: BoxShape.circle, color: Palette.blue),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(n.body, style: t.bodyMedium),
                    const SizedBox(height: 6),
                    Text(dateTimeFmt.format(n.createdAt), style: t.bodySmall),
                  ],
                ),
              ),
              if (n.link != null) ...[
                const SizedBox(width: Insets.sm),
                Icon(Icons.chevron_right, color: Palette.inkFaint),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// An announcement from an administrator: title, message, who it is for
/// and when it ends.
class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard(this.a);
  final Announcement a;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.campaign_outlined, size: 20, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: Insets.sm),
            Expanded(child: Text(a.title, style: t.titleMedium)),
          ]),
          const SizedBox(height: Insets.xs),
          Text(a.body, style: t.bodyMedium),
          const SizedBox(height: Insets.xs),
          Text(
            [
              a.department == null ? 'For everyone' : 'For ${a.department}',
              if (a.endsOn != null) 'until ${a.endsOn!.day}/${a.endsOn!.month}/${a.endsOn!.year}',
              if (a.isSample) 'Sample',
            ].join('  /  '),
            style: t.bodySmall,
          ),
        ],
      ),
    );
  }
}
