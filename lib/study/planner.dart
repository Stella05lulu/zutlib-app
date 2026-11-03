/// The rules behind study plans: which days a student studies, what they do
/// on each day before an exam, how a task ticks itself off, whether they
/// are on track, and study streaks. Plain Dart with no Flutter or Supabase,
/// so every rule is covered by test/planner_test.dart.
///
/// A plan is never stored as a list of tasks. It is worked out again each
/// time from three things: the plan's settings (exam date, study days,
/// minutes a day), the kit's content and progress, and what the student
/// actually did each day. That is what makes it adapt: miss a day and the
/// unread guide sections come back as catch-up work on the next one.
library;

import 'dart:math';

// ------------------------------------------------------------------ dates

/// The date part only, so comparisons ignore the time of day.
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Whole days from [a] to [b] (negative when [b] is earlier). Counted on
/// UTC dates, so a daylight-saving change cannot shift it by a day.
int daysBetween(DateTime a, DateTime b) =>
    DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

/// Study days are kept as a bit mask: Monday 1, Tuesday 2, Wednesday 4,
/// Thursday 8, Friday 16, Saturday 32, Sunday 64. Every day is 127.
abstract final class StudyDays {
  static const all = 127;
  static const weekdays = 31;
  static const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  static int bit(int weekday) => 1 << (weekday - 1);
  static bool has(int mask, DateTime d) => mask & bit(d.weekday) != 0;
  static int toggle(int mask, int weekday) => mask ^ bit(weekday);
  static int count(int mask) => List.generate(7, (i) => (mask >> i) & 1).fold(0, (a, b) => a + b);
}

// ------------------------------------------------------------------ inputs

/// What the student chose when they made the plan.
class PlanSettings {
  const PlanSettings({
    required this.examDate,
    required this.startDate,
    this.studyDays = StudyDays.all,
    this.minutes = 30,
  });

  final DateTime examDate;
  final DateTime startDate;
  final int studyDays;

  /// 15, 30, 45, 60 or 90.
  final int minutes;
}

/// The kit's content and the student's progress on it.
class KitProgress {
  const KitProgress({
    this.sections = const [],
    this.readBeforeToday = const {},
    this.readToday = const {},
    this.cardIds = const [],
    this.boxes = const {},
    this.questionIds = const [],
    this.stars = const {},
    this.bestTestPercent,
  });

  /// Guide section headings, in order.
  final List<String> sections;

  /// Section numbers (from 0) read before today, and read today.
  final Set<int> readBeforeToday;
  final Set<int> readToday;

  final List<String> cardIds;
  final Map<String, int> boxes;
  final List<String> questionIds;
  final Map<String, int> stars;

  /// Best practice test score so far, 0 to 100.
  final int? bestTestPercent;

  Set<int> get read => {...readBeforeToday, ...readToday};

  int get cardsLearning => cardIds.where((id) => (boxes[id] ?? 0) == 0).length;
  int get cardsNotKnown => cardIds.where((id) => (boxes[id] ?? 0) < 2).length;
  int get questionsWeak => questionIds.where((id) => (stars[id] ?? 0) == 0).length;
  int get questionsOpen => questionIds.where((id) => (stars[id] ?? 0) < 3).length;

  double get cardMastery =>
      cardIds.isEmpty ? 1 : cardIds.where((id) => (boxes[id] ?? 0) >= 2).length / cardIds.length;
  double get questionMastery => questionIds.isEmpty
      ? 1
      : questionIds.fold<int>(0, (s, id) => s + (stars[id] ?? 0).clamp(0, 3)) / (questionIds.length * 3);
}

/// What the student did on one day for one kit (from study_activity).
class DayActivity {
  const DayActivity({this.cards = 0, this.questions = 0, this.tests = 0, this.guide = 0});
  final int cards, questions, tests, guide;

  bool get any => cards + questions + tests + guide > 0;

  static const none = DayActivity();
}

// ------------------------------------------------------------------ outputs

enum PlanPhase { learn, practise, test }

extension PlanPhaseX on PlanPhase {
  String get label => switch (this) {
        PlanPhase.learn => 'Learn',
        PlanPhase.practise => 'Practise',
        PlanPhase.test => 'Test',
      };

  String get sentence => switch (this) {
        PlanPhase.learn => 'Read the guide and learn the flashcards.',
        PlanPhase.practise => 'Answer questions, weakest first, and review cards.',
        PlanPhase.test => 'Timed tests, a mock exam, then a light review.',
      };
}

enum PlanTaskKind { guide, newCards, reviewCards, questions, practiceTest, mockTest, lightReview }

/// The kit tab a task opens: 1 Study guide, 2 Smart study, 3 Flashcards,
/// 4 Test (0 is the kit's overview).
extension PlanTaskKindX on PlanTaskKind {
  int get tab => switch (this) {
        PlanTaskKind.guide => 1,
        PlanTaskKind.questions => 2,
        PlanTaskKind.newCards || PlanTaskKind.reviewCards || PlanTaskKind.lightReview => 3,
        PlanTaskKind.practiceTest || PlanTaskKind.mockTest => 4,
      };
}

class PlanTask {
  const PlanTask({
    required this.key,
    required this.kind,
    required this.title,
    required this.reason,
    required this.target,
    this.section,
    this.minutes = 10,
  });

  /// Stable within a day, so a hand tick (study_plan_checks) finds it again.
  final String key;
  final PlanTaskKind kind;
  final String title;

  /// One line saying why this task is here today.
  final String reason;

  /// How many cards, questions, tests or sections finish the task.
  final int target;

  /// The guide section, for a reading task.
  final int? section;

  /// A rough time, so a day adds up to the minutes chosen.
  final int minutes;
}

class PlanDay {
  const PlanDay({required this.date, required this.phase, required this.tasks, this.isStudyDay = true});

  final DateTime date;
  final PlanPhase phase;
  final List<PlanTask> tasks;

  /// False on a day the student chose not to study.
  final bool isStudyDay;

  int get minutes => tasks.fold(0, (s, t) => s + t.minutes);
}

// ------------------------------------------------------------------ the schedule

/// Every study date from [from] up to the day before the exam.
List<DateTime> studyDates(PlanSettings s, DateTime from) {
  final out = <DateTime>[];
  var d = dateOnly(from);
  final exam = dateOnly(s.examDate);
  while (d.isBefore(exam)) {
    if (StudyDays.has(s.studyDays, d)) out.add(d);
    d = DateTime(d.year, d.month, d.day + 1);
  }
  return out;
}

/// The phase of the [index]th of [total] study days: roughly the first 40%
/// learn, the next 40% practise and the last 20% test, with at least one
/// test day whenever there are two days or more.
PlanPhase phaseFor(int index, int total) {
  if (total <= 1) return PlanPhase.test;
  if (total == 2) return index == 0 ? PlanPhase.practise : PlanPhase.test;
  final testDays = max(1, (total * 0.2).round());
  final learnDays = ((total - testDays) / 2).ceil();
  if (index < learnDays) return PlanPhase.learn;
  if (index < total - testDays) return PlanPhase.practise;
  return PlanPhase.test;
}

/// How much fits in one sitting.
int _cardsPerDay(int minutes) => switch (minutes) { <= 15 => 8, <= 30 => 12, <= 45 => 16, <= 60 => 20, _ => 30 };
int _questionsPerDay(int minutes) => switch (minutes) { <= 15 => 5, <= 30 => 10, <= 45 => 15, <= 60 => 20, _ => 30 };

String _plural(int n, String one, [String? many]) => '$n ${n == 1 ? one : (many ?? '${one}s')}';

/// Guide sections assigned to each learn day of the whole plan, in order,
/// spread as evenly as the days allow.
Map<DateTime, List<int>> _sectionSchedule(List<DateTime> learnDates, int sectionCount) {
  final out = <DateTime, List<int>>{};
  if (learnDates.isEmpty || sectionCount == 0) return out;
  for (var s = 0; s < sectionCount; s++) {
    final day = learnDates[(s * learnDates.length) ~/ sectionCount];
    (out[day] ??= []).add(s);
  }
  return out;
}

/// The plan from [today] to the exam: one [PlanDay] per date, including the
/// days off (with no tasks). Past days are left out.
List<PlanDay> buildPlan(PlanSettings s, KitProgress k, DateTime today) {
  final t = dateOnly(today);
  final exam = dateOnly(s.examDate);
  if (!t.isBefore(exam)) return const [];

  final all = studyDates(s, s.startDate.isAfter(t) ? t : s.startDate);
  final total = all.length;
  final phaseOf = {for (var i = 0; i < total; i++) all[i]: phaseFor(i, total)};
  final learnDates = [for (final d in all) if (phaseOf[d] == PlanPhase.learn) d];
  final sectionsByDay = _sectionSchedule(learnDates, k.sections.length);

  // Sections whose day has passed but were not read before today come
  // back today, as catch-up.
  final remaining = [for (final d in all) if (!d.isBefore(t)) d];
  final catchUp = <int>[
    for (final e in sectionsByDay.entries)
      if (e.key.isBefore(t))
        for (final sec in e.value)
          if (!k.readBeforeToday.contains(sec)) sec,
  ];
  // Sections not scheduled on any learn day (a plan with no learn days).
  final unscheduled = learnDates.isEmpty
      ? [for (var i = 0; i < k.sections.length; i++) if (!k.readBeforeToday.contains(i)) i]
      : <int>[];

  final testDates = [for (final d in remaining) if (phaseOf[d] == PlanPhase.test) d];
  final lastDay = remaining.isEmpty ? null : remaining.last;
  final mockDay = testDates.length >= 2 ? testDates[testDates.length - 2] : (testDates.isNotEmpty ? testDates.last : null);

  final cardsPerDay = min(_cardsPerDay(s.minutes), k.cardIds.length);
  final questionsPerDay = min(_questionsPerDay(s.minutes), k.questionIds.length);
  final learnLeft = [for (final d in remaining) if (phaseOf[d] == PlanPhase.learn) d].length;

  final days = <PlanDay>[];
  var d = t;
  var firstStudyDay = true;
  while (d.isBefore(exam)) {
    if (!StudyDays.has(s.studyDays, d)) {
      days.add(PlanDay(date: d, phase: phaseOf[d] ?? _phaseNear(d, all, phaseOf), tasks: const [], isStudyDay: false));
      d = DateTime(d.year, d.month, d.day + 1);
      continue;
    }
    final phase = phaseOf[d]!;
    final tasks = <PlanTask>[];

    // ---- reading
    final toRead = <int>{
      ...(sectionsByDay[d] ?? const <int>[]).where((sec) => !k.readBeforeToday.contains(sec)),
      if (firstStudyDay) ...catchUp,
      if (firstStudyDay) ...unscheduled.take(3),
    }.toList()
      ..sort();
    for (final sec in toRead) {
      final caughtUp = catchUp.contains(sec) && firstStudyDay;
      tasks.add(PlanTask(
        key: 'guide-$sec',
        kind: PlanTaskKind.guide,
        title: 'Read section ${sec + 1}: ${k.sections[sec]}',
        reason: caughtUp
            ? 'Catch-up: this section was planned for an earlier day'
            : '${_plural(k.sections.length - k.read.length, 'section')} of ${k.sections.length} still to read',
        target: 1,
        section: sec,
        minutes: 10,
      ));
    }

    switch (phase) {
      case PlanPhase.learn:
        if (cardsPerDay > 0) {
          final perDay = min(cardsPerDay, max(1, (k.cardIds.length / max(1, learnLeft)).ceil()));
          tasks.add(PlanTask(
            key: 'cards-new',
            kind: PlanTaskKind.newCards,
            title: 'Flashcards: learn ${_plural(perDay, 'card')}',
            reason: '${_plural(k.cardsLearning, 'card')} still in Learning',
            target: perDay,
            minutes: max(5, perDay ~/ 2),
          ));
        }
      case PlanPhase.practise:
        if (questionsPerDay > 0) {
          tasks.add(PlanTask(
            key: 'questions',
            kind: PlanTaskKind.questions,
            title: 'Smart study: ${_plural(questionsPerDay, 'question')}, weakest first',
            reason: k.questionsWeak > 0
                ? '${_plural(k.questionsWeak, 'question')} you got wrong or have not tried'
                : '${_plural(k.questionsOpen, 'question')} not yet at 3 stars',
            target: questionsPerDay,
            minutes: questionsPerDay,
          ));
        }
        if (cardsPerDay > 0) {
          final review = min(cardsPerDay, max(1, k.cardsNotKnown));
          tasks.add(PlanTask(
            key: 'cards-review',
            kind: PlanTaskKind.reviewCards,
            title: 'Flashcards: review ${_plural(review, 'card')}',
            reason: k.cardsNotKnown > 0
                ? '${_plural(k.cardsNotKnown, 'card')} not yet Known'
                : 'Keep known cards fresh',
            target: review,
            minutes: max(5, review ~/ 2),
          ));
        }
      case PlanPhase.test:
        if (d == lastDay && testDates.length >= 2) {
          if (cardsPerDay > 0) {
            tasks.add(PlanTask(
              key: 'review-light',
              kind: PlanTaskKind.lightReview,
              title: 'Light review: ${_plural(cardsPerDay, 'flashcard')}',
              reason: 'Last day before the exam: go over the basics and rest well',
              target: cardsPerDay,
              minutes: 10,
            ));
          }
        } else if (k.questionIds.isNotEmpty) {
          final mock = d == mockDay;
          final n = mock ? min(20, k.questionIds.length) : min(10, k.questionIds.length);
          final daysLeft = daysBetween(d, exam);
          tasks.add(PlanTask(
            key: mock ? 'test-mock' : 'test-practice',
            kind: mock ? PlanTaskKind.mockTest : PlanTaskKind.practiceTest,
            title: mock ? 'Mock exam: a timed test of $n questions' : 'Practice test: $n questions',
            reason: mock
                ? 'Exam in ${_plural(daysLeft, 'day')}: a full timed run'
                : k.bestTestPercent == null
                    ? 'See where you stand before the exam'
                    : 'Your best test so far is ${k.bestTestPercent}%',
            target: 1,
            minutes: mock ? 30 : 15,
          ));
        }
    }

    days.add(PlanDay(date: d, phase: phase, tasks: tasks));
    firstStudyDay = false;
    d = DateTime(d.year, d.month, d.day + 1);
  }
  return days;
}

PlanPhase _phaseNear(DateTime d, List<DateTime> all, Map<DateTime, PlanPhase> phaseOf) {
  for (final x in all) {
    if (!x.isBefore(d)) return phaseOf[x]!;
  }
  return PlanPhase.test;
}

// ------------------------------------------------------------------ ticking

/// True when [task] is done today: ticked by hand, or the day's activity
/// reached its target. Guide tasks tick when that section has been read.
bool taskDone(PlanTask task, DayActivity today, KitProgress k, Set<String> ticked) {
  if (ticked.contains(task.key)) return true;
  return switch (task.kind) {
    PlanTaskKind.guide => task.section != null && k.read.contains(task.section),
    PlanTaskKind.newCards || PlanTaskKind.reviewCards || PlanTaskKind.lightReview => today.cards >= task.target,
    PlanTaskKind.questions => today.questions >= task.target,
    PlanTaskKind.practiceTest || PlanTaskKind.mockTest => today.tests >= task.target,
  };
}

// ------------------------------------------------------------------ status

enum PlanStatus { onTrack, behind, ready, finished }

class PlanHealth {
  const PlanHealth(this.status, this.missedDays, this.message);
  final PlanStatus status;
  final int missedDays;
  final String message;

  String get label => switch (status) {
        PlanStatus.onTrack => 'On track',
        PlanStatus.behind => 'Behind',
        PlanStatus.ready => 'Ready',
        PlanStatus.finished => 'Exam passed',
      };
}

/// Ready once the student knows the kit well; Behind if a study day in the
/// last fortnight passed with no study on this kit; otherwise On track.
PlanHealth planHealth(PlanSettings s, KitProgress k, Map<DateTime, DayActivity> activity, DateTime today) {
  final t = dateOnly(today);
  if (!t.isBefore(dateOnly(s.examDate))) {
    return const PlanHealth(PlanStatus.finished, 0, 'The exam date has passed.');
  }
  if (studyDates(s, t).isEmpty) {
    return const PlanHealth(PlanStatus.behind, 0,
        'No study days are left before the exam. Change the days in this plan so ZutLib can plan them.');
  }
  final testsOk = k.questionIds.isEmpty || (k.bestTestPercent ?? 0) >= 70;
  if (k.cardMastery >= 0.8 && k.questionMastery >= 0.8 && testsOk && k.read.length >= k.sections.length) {
    return const PlanHealth(PlanStatus.ready, 0, 'You know this kit well. Keep it fresh with a test.');
  }
  final start = dateOnly(s.startDate);
  final from = t.subtract(const Duration(days: 14)).isAfter(start) ? t.subtract(const Duration(days: 14)) : start;
  var missed = 0;
  for (var d = from; d.isBefore(t); d = DateTime(d.year, d.month, d.day + 1)) {
    if (StudyDays.has(s.studyDays, d) && !(activity[d]?.any ?? false)) missed++;
  }
  if (missed > 0) {
    return PlanHealth(PlanStatus.behind, missed,
        'Missed ${_plural(missed, 'study day')} recently. Today includes catch-up work.');
  }
  return const PlanHealth(PlanStatus.onTrack, 0, 'Keep going: do today\'s tasks to stay on track.');
}

// ------------------------------------------------------------------ streaks

/// Days in a row with any study, ending today (or yesterday, if nothing
/// has been done yet today).
int studyStreak(Iterable<DateTime> activeDays, DateTime today) {
  final days = activeDays.map(dateOnly).toSet();
  var d = dateOnly(today);
  if (!days.contains(d)) d = DateTime(d.year, d.month, d.day - 1);
  var n = 0;
  while (days.contains(d)) {
    n++;
    d = DateTime(d.year, d.month, d.day - 1);
  }
  return n;
}

/// The last milestone reached: 0, 25, 50, 75 or 100 per cent.
int milestone(double share) => (share.clamp(0, 1) * 4).floor() * 25;

/// Countdown text for an exam.
String examCountdown(DateTime exam, DateTime today) {
  final n = daysBetween(today, exam);
  if (n < 0) return 'Exam passed';
  if (n == 0) return 'Exam today';
  if (n == 1) return 'Exam tomorrow';
  return 'Exam in $n days';
}
