/// Which reminders the phone should show over the next week: one at the
/// student's reminder time on each study day that has tasks, and two for
/// each book on loan (the day before it is due, and the morning it is
/// due). Plain Dart, covered by test/planner_test.dart; the phone part is
/// in lib/services/reminders.dart.
library;

import 'planner.dart';

class ReminderItem {
  const ReminderItem({required this.at, required this.title, required this.body, this.link});
  final DateTime at;
  final String title;
  final String body;

  /// Where tapping it opens, such as /plan or /borrowing.
  final String? link;
}

/// One kit's plan days, as worked out by [buildPlan].
class PlannedKit {
  const PlannedKit({required this.planId, required this.title, required this.days});
  final String planId;
  final String title;
  final List<PlanDay> days;
}

/// A book on loan.
class LoanDue {
  const LoanDue({required this.title, required this.dueDate});
  final String title;
  final DateTime dueDate;
}

List<ReminderItem> buildReminders({
  required DateTime now,
  required int hour,
  required int minute,
  required bool studyReminders,
  required List<PlannedKit> plans,
  required List<LoanDue> loans,
  int days = 7,
}) {
  final out = <ReminderItem>[];
  final today = dateOnly(now);
  final end = today.add(Duration(days: days));

  if (studyReminders) {
    // One reminder per day, listing every kit with tasks that day.
    final byDay = <DateTime, List<(PlannedKit, PlanDay)>>{};
    for (final p in plans) {
      for (final d in p.days) {
        if (d.isStudyDay && d.tasks.isNotEmpty && d.date.isBefore(end)) {
          (byDay[d.date] ??= []).add((p, d));
        }
      }
    }
    for (final e in byDay.entries) {
      final at = DateTime(e.key.year, e.key.month, e.key.day, hour, minute);
      if (!at.isAfter(now)) continue;
      final tasks = e.value.fold<int>(0, (s, x) => s + x.$2.tasks.length);
      final kits = e.value.map((x) => x.$1.title).toList();
      out.add(ReminderItem(
        at: at,
        title: 'Study time: $tasks ${tasks == 1 ? 'task' : 'tasks'} today',
        body: kits.length == 1 ? '${kits.first}: ${e.value.first.$2.tasks.first.title}' : kits.join(', '),
        link: kits.length == 1 ? '/plan/${e.value.first.$1.planId}' : '/plan',
      ));
    }
  }

  for (final l in loans) {
    final due = dateOnly(l.dueDate);
    final dayBefore = DateTime(due.year, due.month, due.day - 1, 9);
    final morning = DateTime(due.year, due.month, due.day, 9);
    if (dayBefore.isAfter(now) && dayBefore.isBefore(end)) {
      out.add(ReminderItem(
          at: dayBefore, title: 'Due back tomorrow', body: '${l.title}: return it to the library', link: '/borrowing'));
    }
    if (morning.isAfter(now) && morning.isBefore(end)) {
      out.add(ReminderItem(at: morning, title: 'Due back today', body: l.title, link: '/borrowing'));
    }
  }

  out.sort((a, b) => a.at.compareTo(b.at));
  return out;
}
