import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/account_repository.dart';
import '../data/plan_repository.dart';
import '../models/plan.dart';
import '../models/profile.dart';
import '../models/resource.dart';
import '../models/study.dart';
import '../study/plan_demo.dart';
import '../study/planner.dart';
import '../study/recommend.dart';
import 'providers.dart';
import 'study_providers.dart';

const planRepo = PlanRepository();
const accountRepo = AccountRepository();

DateTime get _today => dateOnly(DateTime.now());

/// The running demo, if any. Held in memory only, so it survives moving
/// around the app but never reaches the database. Signing out ends it.
final planDemoProvider = StateProvider<PlanDemo?>((ref) {
  ref.watch(userIdProvider);
  return null;
});

final plansProvider = FutureProvider.autoDispose<List<StudyPlan>>((ref) {
  ref.watch(userIdProvider);
  return planRepo.plans();
});

/// What the student did per kit and day over the last 60 days.
final activityProvider = FutureProvider.autoDispose<Map<String, Map<DateTime, DayActivity>>>((ref) {
  ref.watch(userIdProvider);
  return planRepo.activity(_today.subtract(const Duration(days: 60)));
});

/// Tasks ticked by hand today, per plan.
final todayChecksProvider = FutureProvider.autoDispose<Map<String, Set<String>>>((ref) {
  ref.watch(userIdProvider);
  return planRepo.checks(_today);
});

/// Section to the day it was read, for one guide.
final guideReadsProvider = FutureProvider.autoDispose.family<Map<int, DateTime>, String>((ref, guideId) async {
  ref.watch(userIdProvider);
  final all = await planRepo.reads([guideId]);
  return all[guideId] ?? const {};
});

/// Everything a plan screen needs, worked out from the plan, the kit, its
/// progress and the student's activity.
class PlanView {
  const PlanView({
    required this.plan,
    required this.kit,
    required this.progress,
    required this.activity,
    required this.ticked,
    required this.days,
    required this.health,
    this.demoDate,
  });

  final StudyPlan plan;
  final KitData kit;
  final KitProgress progress;
  final Map<DateTime, DayActivity> activity;
  final Set<String> ticked;
  final List<PlanDay> days;
  final PlanHealth health;

  /// The pretend today, when this view is a demo.
  final DateTime? demoDate;

  bool get isDemo => demoDate != null;

  /// The date this view treats as today.
  DateTime get now => demoDate ?? _today;

  /// This plan as [demo] shows it. The kit's content stays real.
  PlanView withDemo(PlanDemo demo) => PlanView(
        plan: plan,
        kit: kit,
        progress: demo.progress,
        activity: demo.past,
        ticked: demo.ticked,
        days: demo.days,
        health: demo.health,
        demoDate: demo.date,
      );

  Note get note => kit.note;

  /// Today's tasks, when today is a study day before the exam.
  PlanDay? get today => days.isNotEmpty && days.first.date == now && days.first.isStudyDay ? days.first : null;

  DayActivity get todayActivity => activity[now] ?? DayActivity.none;

  bool done(PlanTask t) => taskDone(t, todayActivity, progress, ticked);

  int get todayDone => today?.tasks.where(done).length ?? 0;
  int get todayTotal => today?.tasks.length ?? 0;

  /// How much of the kit is learnt, 0 to 1, for the progress bar.
  double get mastery {
    final parts = <double>[
      if (progress.sections.isNotEmpty) progress.read.length / progress.sections.length,
      if (progress.cardIds.isNotEmpty) progress.cardMastery,
      if (progress.questionIds.isNotEmpty) progress.questionMastery,
    ];
    return parts.isEmpty ? 0 : parts.reduce((a, b) => a + b) / parts.length;
  }
}

Future<PlanView?> _view(Ref ref, StudyPlan plan) async {
  final kit = await ref.watch(kitProvider(plan.noteId).future);
  if (kit == null) return null;
  final results = await Future.wait<Object?>([
    ref.watch(activityProvider.future),
    ref.watch(todayChecksProvider.future),
    ref.watch(testsProvider(plan.noteId).future),
    kit.guide == null ? Future.value(const <int, DateTime>{}) : ref.watch(guideReadsProvider(kit.guide!.id).future),
  ]);
  final activity = (results[0] as Map<String, Map<DateTime, DayActivity>>)[plan.noteId] ?? const {};
  final ticked = (results[1] as Map<String, Set<String>>)[plan.id] ?? const <String>{};
  final tests = results[2] as List<StudyTest>;
  final reads = results[3] as Map<int, DateTime>;

  final best = [for (final t in tests) if (t.best != null) t.best!.percent];
  final progress = KitProgress(
    sections: [for (final s in kit.guide?.sections ?? const <GuideSection>[]) s.heading],
    readBeforeToday: {for (final e in reads.entries) if (dateOnly(e.value).isBefore(_today)) e.key},
    readToday: {for (final e in reads.entries) if (!dateOnly(e.value).isBefore(_today)) e.key},
    cardIds: [for (final c in kit.cards) c.id],
    boxes: kit.boxes,
    questionIds: [for (final q in kit.questions) q.id],
    stars: kit.stars,
    bestTestPercent: best.isEmpty ? null : best.reduce((a, b) => a > b ? a : b),
  );
  return PlanView(
    plan: plan,
    kit: kit,
    progress: progress,
    activity: activity,
    ticked: ticked,
    days: buildPlan(plan.settings, progress, _today),
    health: planHealth(plan.settings, progress, activity, _today),
  );
}

final planViewProvider = FutureProvider.autoDispose.family<PlanView?, String>((ref, planId) async {
  final plans = await ref.watch(plansProvider.future);
  final matches = plans.where((p) => p.id == planId);
  if (matches.isEmpty) return null;
  return _view(ref, matches.first);
});

/// Every plan whose exam is still ahead, soonest first.
final upcomingPlansProvider = FutureProvider.autoDispose<List<PlanView>>((ref) async {
  final plans = await ref.watch(plansProvider.future);
  final ahead = plans.where((p) => !dateOnly(p.examDate).isBefore(_today)).toList();
  final views = await Future.wait([for (final p in ahead) _view(ref, p)]);
  return views.whereType<PlanView>().toList();
});

/// The plan for one kit, if it has one.
final planForKitProvider = FutureProvider.autoDispose.family<StudyPlan?, String>((ref, noteId) async {
  final plans = await ref.watch(plansProvider.future);
  final matches = plans.where((p) => p.noteId == noteId);
  return matches.isEmpty ? null : matches.first;
});

/// Days in a row with any study, across every kit.
final streakProvider = FutureProvider.autoDispose<int>((ref) async {
  final activity = await ref.watch(activityProvider.future);
  final days = <DateTime>{
    for (final kit in activity.values)
      for (final e in kit.entries)
        if (e.value.any) e.key,
  };
  return studyStreak(days, _today);
});

/// "For your courses" on Explore.
final recommendationsProvider = FutureProvider.autoDispose<List<Recommendation<Resource>>>((ref) async {
  final profile = await ref.watch(profileProvider.future);
  if (profile == null || profile.role != UserRole.student) return const [];

  // Exams and recently studied courses come from the student's kits.
  final kits = await ref.watch(kitListProvider.future).catchError((_) => const <KitSummary>[]);
  final plans = await ref.watch(plansProvider.future).catchError((_) => const <StudyPlan>[]);
  final courseOf = {for (final k in kits) k.note.id: k.note.courseCode};
  final exams = <String, DateTime>{
    for (final p in plans)
      if ((courseOf[p.noteId] ?? '').isNotEmpty) courseOf[p.noteId]!: p.examDate,
  };
  final recent = <String>{
    for (final k in kits)
      if ((k.note.courseCode ?? '').isNotEmpty && DateTime.now().difference(k.note.updatedAt).inDays <= 14)
        k.note.courseCode!,
  };
  final rp = RecProfile(
    courses: profile.courses.toSet(),
    department: profile.department,
    yearOfStudy: profile.yearOfStudy,
    examDates: exams,
    recentCourses: recent,
  );
  if (rp.isEmpty) return const [];
  final candidates = await resourceRepo.forCourses([...profile.courses, ...exams.keys], profile.department);
  return recommend(
    [
      for (final r in candidates)
        RecItem(item: r, courseCode: r.courseCode, department: r.department, academicYear: r.academicYear),
    ],
    rp,
    DateTime.now(),
  );
});

/// After a plan, a tick or some study changes, refresh what shows it.
void refreshPlans(WidgetRef ref) {
  ref.invalidate(plansProvider);
  ref.invalidate(activityProvider);
  ref.invalidate(todayChecksProvider);
  ref.invalidate(guideReadsProvider);
  ref.invalidate(upcomingPlansProvider);
  ref.invalidate(planViewProvider);
}
