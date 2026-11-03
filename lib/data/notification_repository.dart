import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/failure.dart';
import '../core/supabase.dart';
import '../models/app_notification.dart';
import 'offline_cache.dart';

/// Row level security returns only the signed-in person's own rows, and
/// the only column they may change is read_at.
class NotificationRepository {
  const NotificationRepository();

  Future<List<AppNotification>> mine() async {
    if (currentUserId == null) return const [];
    try {
      final rows = await OfflineCache.rows('notifications', () async {
        return await db.from('notifications').select().order('created_at', ascending: false).limit(100);
      });
      return rows.map(AppNotification.fromMap).toList();
    } catch (e) {
      throw Failure.from(e);
    }
  }

  Future<void> markRead(String id) async {
    try {
      await db
          .from('notifications')
          .update({'read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', id)
          .isFilter('read_at', null);
    } catch (e) {
      throw Failure.from(e);
    }
  }

  Future<void> markAllRead() async {
    final id = currentUserId;
    if (id == null) return;
    try {
      await db
          .from('notifications')
          .update({'read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('user_id', id)
          .isFilter('read_at', null);
    } catch (e) {
      throw Failure.from(e);
    }
  }

  /// Calls [onNew] whenever a notification for the signed-in person is
  /// written (Supabase Realtime), so the bell updates without a refresh.
  /// Returns the channel, to pass to [stopListening].
  RealtimeChannel? listen(void Function() onNew) {
    final uid = currentUserId;
    if (uid == null) return null;
    return db
        .channel('zl-notifications-$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: uid),
          callback: (_) => onNew(),
        )
        .subscribe();
  }

  Future<void> stopListening(RealtimeChannel channel) async {
    try {
      await db.removeChannel(channel);
    } catch (_) {
      // Already closed.
    }
  }
}
