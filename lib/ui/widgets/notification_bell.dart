import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/providers.dart';

/// The bell at the top right of every main screen, with the unread count.
/// Watching [notificationsLiveProvider] keeps it updating the moment a new
/// notification arrives.
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(notificationsLiveProvider);
    final unread = ref.watch(unreadCountProvider);
    final icon = Icon(unread > 0 ? Icons.notifications_active_outlined : Icons.notifications_none_rounded);
    return IconButton(
      tooltip: unread > 0 ? 'Notifications, $unread unread' : 'Notifications',
      onPressed: () => context.push('/updates'),
      icon: unread > 0 ? Badge(label: Text(unread > 99 ? '99+' : '$unread'), child: icon) : icon,
    );
  }
}
