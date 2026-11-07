import 'package:flutter_test/flutter_test.dart';
import 'package:zutlib/study/plan_demo.dart';
import 'package:zutlib/study/planner.dart';

// Monday 2 November 2026.
DateTime day(int offset) => DateTime(2026, 11, 2 + offset);

KitProgress kit({Set<int> read = const {}, Map<String, int> boxes = const {}}) => KitProgress(
      sections: [for (var i = 0; i < 6; i++) 'Section ${i + 1}'],
      readBeforeToday: read,
      cardIds: [for (var i = 0; i < 20; i++) 'c$i'],
      boxes: boxes,
      questionIds: [for (var i = 0; i < 15; i++) 'q$i'],
    );

PlanSettings plan({int days = 10, int studyDays = StudyDays.all}) =>
    PlanSettings(examDate: day(days), startDate: day(0), studyDays: studyDays);

PlanDemo demo({PlanSettings? settings, KitProgress? progress}) =>
    PlanDemo.begin('plan-1', settings ?? plan(), progress ?? kit());

void main() {
  group('Starting', () {
    test('starts on the first study day with an untouched kit', () {
      final d = demo(progress: kit(read: {0, 1}, boxes: {'c0': 3}));
      expect(d.date, day(0));
      expect(d.dayNumber, 1);
      expect(d.totalDays, 10);
      expect(d.progress.read, isEmpty);
      expect(d.progress.cardsLearning, 20);
    });

    test('skips days off to reach the first study day', () {
      final s = PlanSettings(examDate: day(12), startDate: day(5), studyDays: StudyDays.weekdays);
      expect(demo(settings: s).date, day(7)); // Saturday start, so Monday
    });

    test('cannot run with no study days before the exam', () {
      expect(PlanDemo.canRun(plan(days: 0)), isFalse);
      expect(PlanDemo.canRun(plan(days: 1)), isTrue);
    });

    test('works however far the plan is from the real date', () {
      final d = demo().completeDay().completeDay();
      expect(d.days.first.date, day(2));
      expect(d.days.first.tasks, isNotEmpty);
    });
  });

  group('Walking through', () {
    test('completing every day reaches the exam through all three phases', () {
      var d = demo();
      final phases = <PlanPhase>{};
      while (!d.isFinished) {
        phases.add(d.days.first.phase);
        d = d.completeDay();
      }
      expect(d.date, day(10));
      expect(phases, PlanPhase.values.toSet());
      expect(d.progress.read.length, 6);
      expect(d.days, isEmpty);
    });

    test('a finished walk through a full plan ends Ready', () {
      var d = demo();
      while (!d.isFinished) {
        d = d.completeDay();
      }
      expect(d.health.status, PlanStatus.ready);
      expect(d.health.message, contains('Exam day'));
    });

    test('moving on skips days off', () {
      final s = PlanSettings(examDate: day(10), startDate: day(4), studyDays: StudyDays.weekdays);
      expect(demo(settings: s).completeDay().date, day(7)); // Friday to Monday
    });

    test('does nothing more once the exam is reached', () {
      var d = demo(settings: plan(days: 1)).completeDay();
      expect(d.isFinished, isTrue);
      expect(identical(d.completeDay(), d), isTrue);
      expect(identical(d.missDay(), d), isTrue);
      expect(identical(d.jump(), d), isTrue);
    });
  });

  group('Ticking', () {
    test('a tick counts at once and an untick takes it back', () {
      final d = demo();
      final task = d.tasks.firstWhere((t) => t.kind == PlanTaskKind.guide);
      final on = d.toggle(task.key);
      expect(on.progress.read, contains(task.section));
      expect(on.allTicked, isFalse);
      expect(on.toggle(task.key).progress.read, isEmpty);
    });

    test('the day\'s tasks stay the same while ticking', () {
      var d = demo();
      final keys = [for (final t in d.tasks) t.key];
      for (final k in keys) {
        d = d.toggle(k);
      }
      expect([for (final t in d.tasks) t.key], keys);
      expect(d.allTicked, isTrue);
    });
  });

  group('Missing a day', () {
    test('unread sections come back as catch-up and the plan is Behind', () {
      final d = demo().missDay();
      expect(d.date, day(1));
      expect(d.tasks.where((t) => t.isCatchUp), isNotEmpty);
      expect(d.health.status, PlanStatus.behind);
      expect(d.health.missedDays, 1);
    });

    test('work ticked before moving on is kept', () {
      final first = demo();
      final task = first.tasks.firstWhere((t) => t.kind == PlanTaskKind.guide);
      final d = first.toggle(task.key).missDay();
      expect(d.progress.read, contains(task.section));
      expect(d.health.status, isNot(PlanStatus.behind));
    });
  });

  group('Jumping, going back and restarting', () {
    test('jump lands on the first day of the next phase', () {
      final d = demo();
      expect(d.nextPhase, PlanPhase.practise);
      final practise = d.jump();
      expect(practise.days.first.phase, PlanPhase.practise);
      expect(practise.nextPhase, PlanPhase.test);
      expect(practise.jump().days.first.phase, PlanPhase.test);
    });

    test('jump from the last phase goes to the exam', () {
      final d = demo().jump().jump();
      expect(d.nextPhase, isNull);
      expect(d.jump().isFinished, isTrue);
    });

    test('back undoes a whole step, even a jump', () {
      final d = demo();
      expect(d.completeDay().back().date, d.date);
      final j = d.jump();
      expect(j.back().date, d.date);
      expect(j.back().progress.read, isEmpty);
    });

    test('back on the first day stays put', () {
      final d = demo();
      expect(identical(d.back(), d), isTrue);
    });

    test('restart goes back to day one with nothing done', () {
      final d = demo().jump().completeDay().restart();
      expect(d.date, day(0));
      expect(d.progress.read, isEmpty);
      expect(d.past, isEmpty);
      expect(d.previous, isNull);
    });
  });
}
