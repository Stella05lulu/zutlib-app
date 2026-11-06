/// Activity figures for the audit log: events per day for the last seven
/// days, the week's total, the busiest day, and a breakdown by kind of
/// event with each kind's share. Plain Dart, no database, so it is unit
/// tested (test/audit_stats_test.dart).
library;

class DayCount {
  const DayCount(this.day, this.count);
  final DateTime day;
  final int count;
}

class EventShare {
  const EventShare(this.label, this.count, this.share);
  final String label;
  final int count;

  /// 0 to 1.
  final double share;
}

class AuditStats {
  const AuditStats({required this.days, required this.total, required this.breakdown});

  /// Oldest first, always seven entries ending today.
  final List<DayCount> days;
  final int total;

  /// Most frequent first; ties keep alphabetical order.
  final List<EventShare> breakdown;

  /// The day with the most events, or null when the week was quiet. On a
  /// tie the most recent day wins.
  DayCount? get busiest {
    DayCount? best;
    for (final d in days) {
      if (d.count > 0 && (best == null || d.count >= best.count)) best = d;
    }
    return best;
  }

  /// [events] are (label, when) pairs; anything older than six days before
  /// [now] is ignored.
  factory AuditStats.from(Iterable<(String, DateTime)> events, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final first = today.subtract(const Duration(days: 6));
    final perDay = List<int>.filled(7, 0);
    final perLabel = <String, int>{};
    var total = 0;
    for (final (label, at) in events) {
      final local = at.toLocal();
      final day = DateTime(local.year, local.month, local.day);
      final i = day.difference(first).inDays;
      if (i < 0 || i > 6) continue;
      perDay[i]++;
      perLabel[label] = (perLabel[label] ?? 0) + 1;
      total++;
    }
    final kinds = perLabel.entries.toList()
      ..sort((a, b) => b.value != a.value ? b.value.compareTo(a.value) : a.key.compareTo(b.key));
    return AuditStats(
      days: [for (var i = 0; i < 7; i++) DayCount(first.add(Duration(days: i)), perDay[i])],
      total: total,
      breakdown: [for (final k in kinds) EventShare(k.key, k.value, total == 0 ? 0 : k.value / total)],
    );
  }
}

/// "44.4%" with one decimal, as in the breakdown table.
String percent(double share) => '${(share * 100).toStringAsFixed(1)}%';
