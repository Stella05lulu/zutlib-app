import 'package:flutter_test/flutter_test.dart';

import 'package:zutlib/study/audit_stats.dart';

void main() {
  final now = DateTime(2026, 11, 4, 15);

  group('Audit activity', () {
    test('seven days ending today, oldest first, even with no events', () {
      final s = AuditStats.from(const [], now);
      expect(s.days.length, 7);
      expect(s.days.first.day, DateTime(2026, 10, 29));
      expect(s.days.last.day, DateTime(2026, 11, 4));
      expect(s.total, 0);
      expect(s.busiest, isNull);
      expect(s.breakdown, isEmpty);
    });

    test('counts per day and ignores anything older than the week', () {
      final s = AuditStats.from([
        ('Approved an account', DateTime(2026, 11, 4, 9)),
        ('Approved an account', DateTime(2026, 11, 4, 10)),
        ('Suspended an account', DateTime(2026, 10, 30, 8)),
        ('Approved an account', DateTime(2026, 10, 28, 23)), // eight days back
      ], now);
      expect(s.total, 3);
      expect(s.days.last.count, 2);
      expect(s.days[1].count, 1);
      expect(s.busiest!.day, DateTime(2026, 11, 4));
    });

    test('breakdown is most frequent first with shares adding up to one', () {
      final s = AuditStats.from([
        ('B event', DateTime(2026, 11, 3)),
        ('A event', DateTime(2026, 11, 3)),
        ('A event', DateTime(2026, 11, 2)),
        ('C event', DateTime(2026, 11, 1)),
      ], now);
      expect([for (final e in s.breakdown) e.label], ['A event', 'B event', 'C event']);
      expect(s.breakdown.first.count, 2);
      expect(percent(s.breakdown.first.share), '50.0%');
      expect(s.breakdown.fold<double>(0, (a, e) => a + e.share), closeTo(1, 1e-9));
    });

    test('on a tie the most recent day is the busiest', () {
      final s = AuditStats.from([
        ('x', DateTime(2026, 11, 1)),
        ('x', DateTime(2026, 11, 3)),
      ], now);
      expect(s.busiest!.day, DateTime(2026, 11, 3));
    });
  });
}
