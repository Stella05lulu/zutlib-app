import 'package:flutter_test/flutter_test.dart';
import 'package:zutlib/study/planner.dart';
import 'package:zutlib/study/recommend.dart';
import 'package:zutlib/study/reminder_rules.dart';

// Monday 2 November 2026.
final monday = DateTime(2026, 11, 2);
DateTime day(int offset) => DateTime(2026, 11, 2 + offset);

KitProgress kit({int sections = 6, int cards = 20, int questions = 15, Set<int> read = const {}}) => KitProgress(
      sections: [for (var i = 0; i < sections; i++) 'Section ${i + 1}'],
      readBeforeToday: read,
      cardIds: [for (var i = 0; i < cards; i++) 'c$i'],
      questionIds: [for (var i = 0; i < questions; i++) 'q$i'],
    );

void main() {
  group('Dates and study days', () {
    test('days between dates ignore the time of day', () {
      expect(daysBetween(DateTime(2026, 11, 2, 23, 59), DateTime(2026, 11, 3, 0, 1)), 1);
      expect(daysBetween(day(5), day(0)), -5);
    });

    test('study day masks', () {
      expect(StudyDays.has(StudyDays.weekdays, monday), isTrue);
      expect(StudyDays.has(StudyDays.weekdays, day(5)), isFalse); // Saturday
      expect(StudyDays.count(StudyDays.weekdays), 5);
      expect(StudyDays.toggle(StudyDays.all, DateTime.sunday), 63);
    });

    test('study dates stop the day before the exam', () {
      final s = PlanSettings(examDate: day(7), startDate: monday, studyDays: StudyDays.weekdays);
      expect(studyDates(s, monday), [day(0), day(1), day(2), day(3), day(4)]);
    });
  });

  group('Phases', () {
    test('ten days: 4 learn, 4 practise, 2 test', () {
      final phases = [for (var i = 0; i < 10; i++) phaseFor(i, 10)];
      expect(phases.where((p) => p == PlanPhase.learn).length, 4);
      expect(phases.where((p) => p == PlanPhase.practise).length, 4);
      expect(phases.where((p) => p == PlanPhase.test).length, 2);
      expect(phases.first, PlanPhase.learn);
      expect(phases.last, PlanPhase.test);
    });

    test('one or two days still end with a test', () {
      expect(phaseFor(0, 1), PlanPhase.test);
      expect([phaseFor(0, 2), phaseFor(1, 2)], [PlanPhase.practise, PlanPhase.test]);
    });
  });

  group('Building a plan', () {
    final settings = PlanSettings(examDate: day(10), startDate: monday);

    test('one day per date up to the exam, none on or after it', () {
      final plan = buildPlan(settings, kit(), monday);
      expect(plan.length, 10);
      expect(plan.first.date, monday);
      expect(plan.last.date, day(9));
      expect(buildPlan(settings, kit(), day(10)), isEmpty);
    });

    test('every guide section is planned on a learn day, in order', () {
      final plan = buildPlan(settings, kit(), monday);
      final sections = [
        for (final d in plan)
          for (final t in d.tasks)
            if (t.kind == PlanTaskKind.guide) t.section!
      ];
      expect(sections, [0, 1, 2, 3, 4, 5]);
      expect(plan.where((d) => d.phase == PlanPhase.learn).every((d) => d.tasks.any((t) => t.kind == PlanTaskKind.guide)),
          isTrue);
    });

    test('practise days ask questions and review cards; the last days test', () {
      final plan = buildPlan(settings, kit(), monday);
      final practise = plan.firstWhere((d) => d.phase == PlanPhase.practise);
      expect(practise.tasks.map((t) => t.kind), containsAll([PlanTaskKind.questions, PlanTaskKind.reviewCards]));
      expect(plan[8].tasks.single.kind, PlanTaskKind.mockTest);
      expect(plan[9].tasks.single.kind, PlanTaskKind.lightReview);
    });

    test('days off have no tasks', () {
      final s = PlanSettings(examDate: day(10), startDate: monday, studyDays: StudyDays.weekdays);
      final plan = buildPlan(s, kit(), monday);
      final saturday = plan.firstWhere((d) => d.date == day(5));
      expect(saturday.isStudyDay, isFalse);
      expect(saturday.tasks, isEmpty);
    });

    test('sections missed on earlier days come back today as catch-up', () {
      // Day 3 of the plan; nothing was read on days 1 and 2.
      final plan = buildPlan(settings, kit(), day(2));
      final today = plan.first;
      final guide = today.tasks.where((t) => t.kind == PlanTaskKind.guide).toList();
      expect(guide.map((t) => t.section), containsAll([0, 1, 2]));
      expect(guide.firstWhere((t) => t.section == 0).reason, startsWith('Catch-up'));
    });

    test('sections already read are not planned again', () {
      final plan = buildPlan(settings, kit(read: {0, 1}), day(2));
      final guide = plan.first.tasks.where((t) => t.kind == PlanTaskKind.guide).map((t) => t.section);
      expect(guide, isNot(contains(0)));
      expect(guide, isNot(contains(1)));
    });

    test('a kit without cards or questions only gets reading tasks', () {
      final plan = buildPlan(settings, kit(cards: 0, questions: 0), monday);
      expect(plan.expand((d) => d.tasks).every((t) => t.kind == PlanTaskKind.guide), isTrue);
    });

    test('more minutes a day means more questions', () {
      int questions(int minutes) => buildPlan(
              PlanSettings(examDate: day(10), startDate: monday, minutes: minutes), kit(questions: 40), monday)
          .expand((d) => d.tasks)
          .firstWhere((t) => t.kind == PlanTaskKind.questions)
          .target;
      expect(questions(15), lessThan(questions(60)));
    });

    test('task keys are stable and safe for the database', () {
      final keys = buildPlan(settings, kit(), monday).expand((d) => d.tasks).map((t) => t.key);
      expect(keys.every((k) => RegExp(r'^[a-z0-9:_-]{1,60}$').hasMatch(k)), isTrue);
    });
  });

  group('Ticking tasks', () {
    const cards = PlanTask(key: 'cards-new', kind: PlanTaskKind.newCards, title: '', reason: '', target: 10);
    const read = PlanTask(key: 'guide-2', kind: PlanTaskKind.guide, title: '', reason: '', target: 1, section: 2);

    test('a task ticks when the day\'s activity reaches its target', () {
      expect(taskDone(cards, const DayActivity(cards: 9), kit(), {}), isFalse);
      expect(taskDone(cards, const DayActivity(cards: 10), kit(), {}), isTrue);
    });

    test('a reading task ticks when that section is read', () {
      expect(taskDone(read, DayActivity.none, kit(), {}), isFalse);
      expect(taskDone(read, DayActivity.none, const KitProgress(sections: ['a', 'b', 'c'], readToday: {2}), {}),
          isTrue);
    });

    test('a hand tick always counts', () {
      expect(taskDone(cards, DayActivity.none, kit(), {'cards-new'}), isTrue);
    });
  });

  group('Plan health', () {
    final s = PlanSettings(examDate: day(10), startDate: monday);

    test('a missed study day shows as behind', () {
      final h = planHealth(s, kit(), {day(0): const DayActivity(cards: 3)}, day(2));
      expect(h.status, PlanStatus.behind);
      expect(h.missedDays, 1);
    });

    test('studying every day is on track', () {
      final h = planHealth(
          s, kit(), {day(0): const DayActivity(cards: 3), day(1): const DayActivity(questions: 2)}, day(2));
      expect(h.status, PlanStatus.onTrack);
    });

    test('knowing the kit well is ready', () {
      const k = KitProgress(
        sections: ['a'],
        readBeforeToday: {0},
        cardIds: ['c1'],
        boxes: {'c1': 3},
        questionIds: ['q1'],
        stars: {'q1': 3},
        bestTestPercent: 85,
      );
      expect(planHealth(s, k, const {}, day(2)).status, PlanStatus.ready);
    });

    test('a plan with no study days left before the exam says so', () {
      // Exam on Friday, but only weekends ticked.
      final weekends = PlanSettings(examDate: day(4), startDate: monday, studyDays: 96);
      final h = planHealth(weekends, kit(), const {}, monday);
      expect(h.status, PlanStatus.behind);
      expect(h.message, startsWith('No study days are left'));
      expect(buildPlan(weekends, kit(), monday).every((d) => !d.isStudyDay), isTrue);
    });

    test('after the exam the plan is finished', () {
      expect(planHealth(s, kit(), const {}, day(10)).status, PlanStatus.finished);
    });
  });

  group('Streaks and milestones', () {
    test('a streak counts days in a row up to today', () {
      expect(studyStreak([day(0), day(1), day(2)], day(2)), 3);
    });

    test('nothing yet today still keeps yesterday\'s streak', () {
      expect(studyStreak([day(0), day(1)], day(2)), 2);
    });

    test('a gap ends the streak', () {
      expect(studyStreak([day(0), day(2)], day(2)), 1);
      expect(studyStreak(const [], day(2)), 0);
    });

    test('milestones step in quarters', () {
      expect(milestone(0.1), 0);
      expect(milestone(0.5), 50);
      expect(milestone(0.99), 75);
      expect(milestone(1), 100);
    });

    test('exam countdown text', () {
      expect(examCountdown(day(1), day(0)), 'Exam tomorrow');
      expect(examCountdown(day(5), day(0)), 'Exam in 5 days');
      expect(examCountdown(day(0), day(0)), 'Exam today');
    });
  });

  group('Recommendations', () {
    RecItem<String> paper(String id, String code, {String dept = 'Engineering', int year = 2024}) =>
        RecItem(item: id, courseCode: code, department: dept, academicYear: year);

    final items = [
      paper('eee2011-2024', 'EEE 2011'),
      paper('eee2011-2025', 'eee  2011', year: 2025),
      paper('ict2010', 'ICT 2010', dept: 'ICT'),
      paper('eee2050', 'EEE 2050'),
      paper('mat1100', 'MAT 1100'),
      paper('bus3010', 'BUS 3010', dept: 'Business'),
    ];

    test('course codes are normalised and levels read from the number', () {
      expect(normaliseCourse(' eee   2011 '), 'EEE 2011');
      expect(courseLevel('EEE 2011'), 2);
      expect(courseLevel('ICT 101'), 1);
      expect(courseLevel('General'), isNull);
    });

    test('an upcoming exam comes first, newest paper first', () {
      final recs = recommend(
          items,
          RecProfile(courses: const {'ICT 2010'}, examDates: {'EEE 2011': day(5)}),
          day(0));
      expect(recs.take(2).map((r) => r.item), ['eee2011-2025', 'eee2011-2024']);
      expect(recs.first.reason, 'Your EEE 2011 exam is in 5 days');
      expect(recs[2].item, 'ict2010');
      expect(recs[2].reason, 'Because you take ICT 2010');
    });

    test('same department and year level is a weaker suggestion', () {
      final recs = recommend(items, const RecProfile(department: 'Engineering', yearOfStudy: 2), day(0));
      expect(recs.map((r) => r.item), containsAll(['eee2011-2024', 'eee2050']));
      expect(recs.map((r) => r.item), isNot(contains('mat1100')));
      expect(recs.first.reason, 'For Engineering year 2 students');
    });

    test('nothing known about the student means no suggestions', () {
      expect(recommend(items, const RecProfile(), day(0)), isEmpty);
      expect(const RecProfile().isEmpty, isTrue);
    });

    test('a past exam no longer boosts its course', () {
      final recs = recommend(items, RecProfile(examDates: {'EEE 2011': day(-1)}), day(0));
      expect(recs, isEmpty);
    });
  });

  group('Phone reminders', () {
    const task = PlanTask(key: 'questions', kind: PlanTaskKind.questions, title: 'Smart study: 10 questions', reason: '', target: 10);
    PlannedKit kitWith(List<int> dayOffsets) => PlannedKit(
          planId: 'p1',
          title: 'Loops kit',
          days: [for (final o in dayOffsets) PlanDay(date: day(o), phase: PlanPhase.practise, tasks: const [task])],
        );

    test('one study reminder per day with tasks, at the chosen time, after now', () {
      final r = buildReminders(
        now: DateTime(2026, 11, 2, 19, 0), // after today's 18:00
        hour: 18,
        minute: 0,
        studyReminders: true,
        plans: [kitWith([0, 1, 2])],
        loans: const [],
      );
      expect(r.map((x) => x.at), [DateTime(2026, 11, 3, 18), DateTime(2026, 11, 4, 18)]);
      expect(r.first.title, 'Study time: 1 task today');
      expect(r.first.body, 'Loops kit: Smart study: 10 questions');
      expect(r.first.link, '/plan/p1');
    });

    test('study reminders can be switched off', () {
      final r = buildReminders(
          now: monday, hour: 18, minute: 0, studyReminders: false, plans: [kitWith([0, 1])], loans: const []);
      expect(r, isEmpty);
    });

    test('a loan gets a reminder the day before and the morning it is due', () {
      final r = buildReminders(
        now: monday,
        hour: 18,
        minute: 0,
        studyReminders: false,
        plans: const [],
        loans: [LoanDue(title: 'Programming in C', dueDate: day(3))],
      );
      expect(r.map((x) => x.at), [DateTime(2026, 11, 4, 9), DateTime(2026, 11, 5, 9)]);
      expect(r.map((x) => x.title), ['Due back tomorrow', 'Due back today']);
    });

    test('nothing is scheduled beyond a week', () {
      final r = buildReminders(
        now: monday,
        hour: 18,
        minute: 0,
        studyReminders: true,
        plans: [kitWith([10])],
        loans: [LoanDue(title: 'x', dueDate: day(20))],
      );
      expect(r, isEmpty);
    });
  });
}
