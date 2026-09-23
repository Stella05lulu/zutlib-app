import '../core/failure.dart';
import '../core/supabase.dart';
import '../models/app_notification.dart';

/// Row level security returns only the signed-in person's own rows, and
/// the only column they may change is read_at.
class NotificationRepository {
  const NotificationRepository();

  Future<List<AppNotification>> mine() async {
    if (currentUserId == null) return const [];
    try {
      final rows = await db
          .from('notifications')
          .select()
          .order('created_at', ascending: false)
          .limit(100);
      return (rows as List)
          .map((e) => AppNotification.fromMap(e as Map<String, dynamic>))
          .toList();
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
}
