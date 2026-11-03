import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/borrow_request.dart';
import '../models/profile.dart';
import '../state/plan_providers.dart';
import '../state/providers.dart';
import '../study/reminder_rules.dart';

/// Study and due-date reminders scheduled on the phone itself, so they
/// arrive even with the app closed and with no internet. They need no
/// server and no Firebase. On the web they are skipped (the bell and push
/// notifications cover the web).
abstract final class Reminders {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static bool get supported =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'zutlib_reminders',
      'Study and due-date reminders',
      channelDescription: 'Your daily study plan and books due back at the library.',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    ),
    iOS: DarwinNotificationDetails(),
  );

  static Future<void> init() async {
    if (!supported || _ready) return;
    try {
      tzdata.initializeTimeZones();
      // ZutLib is used in Zambia; reminder times are Zambia times.
      tz.setLocalLocation(tz.getLocation('Africa/Lusaka'));
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      );
      await _plugin.initialize(settings);
      _ready = true;
    } catch (e) {
      if (kDebugMode) debugPrint('Reminders.init: $e');
    }
  }

  /// Asks to show notifications (Android 13 and later, and iPhone). Safe to
  /// call often: the phone only asks once.
  static Future<void> requestPermission() async {
    if (!supported) return;
    await init();
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      await _plugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } catch (e) {
      if (kDebugMode) debugPrint('Reminders.requestPermission: $e');
    }
  }

  /// Replaces every scheduled reminder with [items].
  static Future<void> schedule(List<ReminderItem> items) async {
    if (!supported) return;
    await init();
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
      final now = tz.TZDateTime.now(tz.local);
      var id = 1;
      for (final r in items.take(60)) {
        final when = tz.TZDateTime(tz.local, r.at.year, r.at.month, r.at.day, r.at.hour, r.at.minute);
        if (!when.isAfter(now)) continue;
        await _plugin.zonedSchedule(
          id++,
          r.title,
          r.body,
          when,
          _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: r.link,
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Reminders.schedule: $e');
    }
  }

  static Future<void> cancelAll() async {
    if (!supported || !_ready) return;
    try {
      await _plugin.cancelAll();
    } catch (_) {
      // Nothing scheduled.
    }
  }

  /// Works the reminders out again soon (after a plan or a setting changes).
  static void rescheduleSoon(WidgetRef ref) => ref.invalidate(remindersSyncProvider);
}

/// Watched by the app shell for students: whenever the plans, the loans or
/// the reminder settings change, the phone's reminders are replaced.
final remindersSyncProvider = FutureProvider.autoDispose<void>((ref) async {
  if (!Reminders.supported) return;
  final profile = await ref.watch(profileProvider.future);
  if (profile == null || profile.role != UserRole.student || !profile.isActive) return;
  final views = await ref.watch(upcomingPlansProvider.future);
  final loans = await ref.watch(myBorrowingProvider.future);
  final (hour, minute) = profile.reminderHourMinute;
  await Reminders.schedule(buildReminders(
    now: DateTime.now(),
    hour: hour,
    minute: minute,
    studyReminders: profile.notifyStudy,
    plans: [for (final v in views) PlannedKit(planId: v.plan.id, title: v.note.title, days: v.days)],
    loans: [
      for (final l in loans)
        if (l.status == BorrowStatus.collected && l.dueDate != null)
          LoanDue(title: l.resourceTitle ?? 'Your book', dueDate: l.dueDate!),
    ],
  ));
});
