/// Demo mode for a study plan: walk through a whole plan in minutes, for a
/// presentation. A real plan only moves when the calendar does, so this
/// runs the same rules (planner.dart) on a pretend date with pretend
/// progress. It lives in memory only: nothing here reaches the database,
/// so the student's real plan, ticks and progress are left as they were.
///
/// A demo starts on the plan's first study day with an untouched kit, so
/// the whole process can be shown whatever the student has really done.
/// Plain Dart, covered by test/plan_demo_test.dart.
library;

import 'dart:math';

import 'planner.dart';

/// Test scores a demo pretends the student reached.
const _practiceScore = 72;
const _mockScore = 84;

class PlanDemo {
  const PlanDemo._({
    required this.planId,
    required this.settings,
    required this.date,
    required this.start,
    this.past = const {},
    this.ticked = const {},
    this.previous,
  });

  /// A new demo of [planId], using only the content of [kit], not its
  /// progress.
  factory PlanDemo.begin(String planId, PlanSettings settings, KitProgress kit) {
    final dates = studyDates(settings, settings.startDate);
    return PlanDemo._(
      planId: planId,
      settings: settings,
      date: dates.isEmpty ? dateOnly(settings.examDate) : dates.first,
      start: KitProgress(sections: kit.sections, cardIds: kit.cardIds, questionIds: kit.questionIds),
    );
  }

  final String planId;
  final PlanSettings settings;

  /// The pretend today: a study day, or the exam day at the end.
  final DateTime date;

  /// Progress at the start of [date]. Tasks are worked out from this, so a
  /// day's list stays the same while its tasks are ticked.
  final KitProgress start;

  /// What was done on each earlier day. A missed day has no entry.
  final Map<DateTime, DayActivity> past;

  /// Tasks ticked on [date].
  final Set<String> ticked;

  /// The day before this step, for going back.
  final PlanDemo? previous;

  /// True when [settings] leave at least one study day to walk through.
  static bool canRun(PlanSettings s) => studyDates(s, s.startDate).isNotEmpty;

  List<DateTime> get _dates => studyDates(settings, settings.startDate);

  bool get isFinished => !date.isBefore(dateOnly(settings.examDate));
  int get totalDays => _dates.length;

  /// Which study day this is, from 1.
  int get dayNumber => isFinished ? totalDays : _dates.indexOf(date) + 1;

  List<PlanDay> get days => buildPlan(settings, start, date);

  List<PlanTask> get tasks => days.isEmpty ? const [] : days.first.tasks;

  bool get allTicked => tasks.every((t) => ticked.contains(t.key));

  /// [start] with today's ticked tasks counted.
  KitProgress get progress => _apply(start, tasks.where((t) => ticked.contains(t.key)));

  PlanHealth get health {
    if (!isFinished) return planHealth(settings, progress, past, date);
    // The real rule says the exam has passed; a demo ends on the exam day,
    // so report how the last study day left things.
    final h = planHealth(settings, progress, past, _dates.last);
    return PlanHealth(h.status, h.missedDays, 'Exam day: this is where the plan ends.');
  }

  /// The next phase after today's, or null when only the exam is left.
  PlanPhase? get nextPhase {
    if (isFinished) return null;
    final all = _dates;
    final i = all.indexOf(date);
    final now = phaseFor(i, all.length);
    for (var j = i + 1; j < all.length; j++) {
      final p = phaseFor(j, all.length);
      if (p != now) return p;
    }
    return null;
  }

  PlanDemo toggle(String taskKey) => _copy(
        ticked: ticked.contains(taskKey) ? ({...ticked}..remove(taskKey)) : {...ticked, taskKey},
      );

  /// Does whatever is left today, then moves to the next study day.
  PlanDemo completeDay() => _move({for (final t in tasks) t.key}, this);

  /// Moves on with only today's ticked tasks done. Anything else counts as
  /// missed, so catch-up work and the Behind status can be shown.
  PlanDemo missDay() => _move(ticked, this);

  /// Completes every day up to the next phase, or up to the exam.
  PlanDemo jump() {
    if (isFinished) return this;
    final target = nextPhase;
    var d = this;
    while (!d.isFinished && (target == null || d.days.first.phase != target)) {
      d = d.completeDay();
    }
    return d._copy(previous: this);
  }

  PlanDemo back() => previous ?? this;

  PlanDemo restart() => PlanDemo.begin(planId, settings, start);

  PlanDemo _move(Set<String> done, PlanDemo from) {
    if (isFinished) return this;
    final finished = [for (final t in tasks) if (done.contains(t.key)) t];
    final after = _apply(start, finished);
    final activity = _activity(finished);
    final next = studyDates(settings, date.add(const Duration(days: 1)));
    return PlanDemo._(
      planId: planId,
      settings: settings,
      date: next.isEmpty ? dateOnly(settings.examDate) : next.first,
      start: KitProgress(
        sections: after.sections,
        readBeforeToday: after.read,
        cardIds: after.cardIds,
        boxes: after.boxes,
        questionIds: after.questionIds,
        stars: after.stars,
        bestTestPercent: after.bestTestPercent,
      ),
      past: {...past, if (activity.any) date: activity},
      previous: from,
    );
  }

  PlanDemo _copy({Set<String>? ticked, PlanDemo? previous}) => PlanDemo._(
        planId: planId,
        settings: settings,
        date: date,
        start: start,
        past: past,
        ticked: ticked ?? this.ticked,
        previous: previous ?? this.previous,
      );
}

/// [k] after [tasks]: sections read, cards known, questions at three stars,
/// and a test score.
KitProgress _apply(KitProgress k, Iterable<PlanTask> tasks) {
  final readToday = {...k.readToday};
  final boxes = {...k.boxes};
  final stars = {...k.stars};
  var best = k.bestTestPercent;

  void learnCards(int n) {
    for (final id in k.cardIds.where((id) => (boxes[id] ?? 0) < 2).take(n).toList()) {
      boxes[id] = 2;
    }
  }

  for (final task in tasks) {
    switch (task.kind) {
      case PlanTaskKind.guide:
        if (task.section != null) readToday.add(task.section!);
      case PlanTaskKind.newCards || PlanTaskKind.reviewCards || PlanTaskKind.lightReview:
        learnCards(task.target);
      case PlanTaskKind.questions:
        final open = k.questionIds.where((id) => (stars[id] ?? 0) < 3).toList()
          ..sort((a, b) => (stars[a] ?? 0).compareTo(stars[b] ?? 0));
        for (final id in open.take(task.target)) {
          stars[id] = 3;
        }
      case PlanTaskKind.practiceTest:
        best = max(best ?? 0, _practiceScore);
      case PlanTaskKind.mockTest:
        best = max(best ?? 0, _mockScore);
    }
  }

  return KitProgress(
    sections: k.sections,
    readBeforeToday: k.readBeforeToday,
    readToday: readToday,
    cardIds: k.cardIds,
    boxes: boxes,
    questionIds: k.questionIds,
    stars: stars,
    bestTestPercent: best,
  );
}

DayActivity _activity(Iterable<PlanTask> tasks) {
  var cards = 0, questions = 0, tests = 0, guide = 0;
  for (final t in tasks) {
    switch (t.kind) {
      case PlanTaskKind.guide:
        guide += 1;
      case PlanTaskKind.newCards || PlanTaskKind.reviewCards || PlanTaskKind.lightReview:
        cards += t.target;
      case PlanTaskKind.questions:
        questions += t.target;
      case PlanTaskKind.practiceTest || PlanTaskKind.mockTest:
        tests += t.target;
    }
  }
  return DayActivity(cards: cards, questions: questions, tests: tests, guide: guide);
}
