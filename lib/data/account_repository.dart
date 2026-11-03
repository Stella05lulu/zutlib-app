import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/failure.dart';
import '../core/supabase.dart';

/// Changing your own profile, sending feedback, anonymous usage events,
/// administrator reports and phone registration for push notifications.
class AccountRepository {
  const AccountRepository();

  /// Shown on feedback so the developers know which build it came from.
  static const appVersion = '2.0.0';

  static Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on PostgrestException catch (e) {
      if (e.code == '22023' || e.code == '42501' || e.code == '54000') throw Failure(e.message);
      throw Failure.from(e);
    } catch (e) {
      if (e is Failure) rethrow;
      throw Failure.from(e);
    }
  }

  // ------------------------------------------------------------- profile
  /// The database checks every value; email, role and status never change
  /// here.
  Future<void> updateProfile({
    required String fullName,
    required String? department,
    required int? yearOfStudy,
    required List<String> courses,
    required String reminderTime,
    required bool notifyUploads,
    required bool notifyStudy,
    bool finishOnboarding = false,
  }) =>
      _guard(() async {
        await db.rpc('update_my_profile', params: {
          'p_full_name': fullName,
          'p_department': department,
          'p_year': yearOfStudy,
          'p_courses': courses,
          'p_reminder_time': reminderTime,
          'p_notify_uploads': notifyUploads,
          'p_notify_study': notifyStudy,
          'p_finish_onboarding': finishOnboarding,
        });
      });

  // ------------------------------------------------------------- feedback
  Future<void> sendFeedback(String message) => _guard(() async {
        await db.from('feedback').insert({'message': message.trim(), 'app_version': appVersion});
      });

  /// Newest first. Administrators see everyone's; anyone else their own.
  Future<List<FeedbackItem>> feedback({int limit = 50}) => _guard(() async {
        final data = await db
            .from('feedback')
            .select('id,role,message,app_version,created_at,resolved_at')
            .order('created_at', ascending: false)
            .limit(limit);
        return [for (final r in data as List) FeedbackItem.fromMap(r as Map<String, dynamic>)];
      });

  Future<void> resolveFeedback(String id, bool resolved) => _guard(() async {
        await db.rpc('admin_resolve_feedback', params: {'p_id': id, 'p_resolved': resolved});
      });

  // ------------------------------------------------------------- usage
  /// Records an anonymous event for the reports. Never throws: a report
  /// that misses one search must not break the search.
  Future<void> logEvent(String kind, {String? courseCode, String? resourceId}) async {
    try {
      await db.rpc('log_event', params: {'p_kind': kind, 'p_course': courseCode, 'p_resource': resourceId});
    } catch (_) {
      // Ignored on purpose.
    }
  }

  Future<Map<String, dynamic>> reports(int days) => _guard(() async {
        final data = await db.rpc('admin_reports', params: {'p_days': days});
        return Map<String, dynamic>.from(data as Map);
      });

  // ------------------------------------------------------------- devices
  Future<void> registerDevice(String token, String platform) => _guard(() async {
        await db.rpc('register_device', params: {'p_token': token, 'p_platform': platform});
      });

  Future<void> unregisterDevice(String token) async {
    try {
      await db.rpc('unregister_device', params: {'p_token': token});
    } catch (_) {
      // Signing out must not fail because of this.
    }
  }
}

class FeedbackItem {
  const FeedbackItem({
    required this.id,
    required this.message,
    required this.createdAt,
    this.role,
    this.appVersion,
    this.resolvedAt,
  });

  final String id;
  final String message;
  final DateTime createdAt;
  final String? role;
  final String? appVersion;
  final DateTime? resolvedAt;

  bool get resolved => resolvedAt != null;

  factory FeedbackItem.fromMap(Map<String, dynamic> m) => FeedbackItem(
        id: m['id'] as String,
        message: (m['message'] ?? '') as String,
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
        role: m['role'] as String?,
        appVersion: m['app_version'] as String?,
        resolvedAt: m['resolved_at'] == null ? null : DateTime.parse(m['resolved_at'] as String).toLocal(),
      );
}
