import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/reminders.dart';
import '../../../state/plan_providers.dart';
import '../../../study/planner.dart';
import '../../widgets/common.dart' show showMessage;
import '../../widgets/study_widgets.dart';
import 'plan_sheet.dart';
import 'plan_widgets.dart';

/// One exam's plan: the countdown and status, the three phases, today's
/// tasks, and every day up to the exam.
class PlanDetailScreen extends ConsumerWidget {
  const PlanDetailScreen({super.key, required this.planId});
  final String planId;

  Future<void> _delete(BuildContext context, WidgetRef ref, PlanView v) async {
    final ok = await confirmDelete(context,
        what: 'this plan', consequence: 'The study kit and all your progress in it stay.');
    if (!ok) return;
    try {
      await planRepo.delete(v.plan.id);
      refreshPlans(ref);
      Reminders.rescheduleSoon(ref);
      if (context.mounted) context.pop();
    } on Failure catch (f) {
      if (context.mounted) showMessage(context, f.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(planViewProvider(planId));
    final v = async.valueOrNull;

    return StudyScope(
      child: Builder(builder: (context) {
        return Scaffold(
          appBar: StudyTopBar(
            title: v?.note.title ?? 'Plan',
            actions: [
              if (v != null)
                PopupMenuButton<String>(
                  tooltip: 'Plan options',
                  onSelected: (choice) async {
                    switch (choice) {
                      case 'edit':
                        await showPlanSheet(context, existing: v.plan);
                      case 'kit':
                        unawaited(context.push('/study/note/${v.plan.noteId}'));
                      case 'delete':
                        await _delete(context, ref, v);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Change date or days')),
                    PopupMenuItem(value: 'kit', child: Text('Open the study kit')),
                    PopupMenuItem(value: 'delete', child: Text('Delete plan')),
                  ],
                ),
            ],
          ),
          body: StudyPage(
            onRefresh: () async {
              refreshPlans(ref);
              try {
                await ref.read(planViewProvider(planId).future);
              } catch (_) {
                // Shown on the page.
              }
            },
            children: [
              StudyAsync<PlanView?>(
                value: async,
                onRetry: () => ref.invalidate(planViewProvider(planId)),
                skeleton: const RowsSkeleton(rows: 5),
                isEmpty: (x) => x == null,
                empty: const StudyEmptyState('This plan no longer exists.'),
                data: (x) => _Body(view: x!),
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.view});
  final PlanView view;

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    final t = Theme.of(context).textTheme;
    final plan = view.plan;
    final health = view.health;
    final today = view.today;
    final upcoming = view.days.where((d) => today == null || d.date != today.date).toList();
    final noStudyDays = view.days.isNotEmpty && view.days.every((d) => !d.isStudyDay);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(examCountdown(plan.examDate, DateTime.now()), style: t.headlineSmall),
                  Text(DateFormat('EEEE d MMMM yyyy').format(plan.examDate), style: t.bodyMedium),
                ],
              ),
            ),
            PlanStatusTag(health),
          ],
        ),
        const SizedBox(height: Gap.snug),
        if (noStudyDays)
          InlineNotice(
            'None of the days you chose to study fall before the exam, so there is nothing to plan.',
            error: true,
            action: TextButton(
              onPressed: () => showPlanSheet(context, existing: plan),
              child: const Text('Change study days'),
            ),
          )
        else
          Text(health.message,
              style: t.bodyMedium?.copyWith(color: health.status == PlanStatus.behind ? c.warn : c.inkSoft)),
        const SizedBox(height: Gap.page),
        MasteryBar(value: view.mastery),
        const SizedBox(height: Gap.page),
        if (!noStudyDays) _Phases(view: view),
        SectionLabel(today == null ? 'Today' : 'Today  ${view.todayDone} of ${view.todayTotal} done'),
        if (today == null)
          StudyEmptyState(
            view.days.isNotEmpty && !view.days.first.isStudyDay
                ? 'Today is a day off in this plan.'
                : 'Nothing left to plan: the exam is here.',
            compact: true,
          )
        else if (today.tasks.isEmpty)
          const StudyEmptyState('Nothing to do for this kit today.', compact: true)
        else
          RowGroup(children: [for (final task in today.tasks) PlanTaskRow(view: view, task: task)]),
        const SectionLabel('Coming up'),
        if (upcoming.isEmpty)
          const StudyEmptyState('The exam is tomorrow. Rest well.', compact: true)
        else
          RowGroup(children: [for (final d in upcoming) _DayRow(day: d)]),
        const SizedBox(height: Gap.page),
        OutlinedButton.icon(
          onPressed: () => context.push('/study/note/${plan.noteId}'),
          icon: const Icon(Icons.auto_stories_outlined, size: 18),
          label: const Text('Open the study kit'),
        ),
      ],
    );
  }
}

/// Learn, Practise, Test: where each phase falls, and which one is now.
class _Phases extends StatelessWidget {
  const _Phases({required this.view});
  final PlanView view;

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    final t = Theme.of(context).textTheme;
    final settings = view.plan.settings;
    final all = studyDates(settings, settings.startDate);
    final ranges = <PlanPhase, List<DateTime>>{};
    for (var i = 0; i < all.length; i++) {
      (ranges[phaseFor(i, all.length)] ??= []).add(all[i]);
    }
    final now = view.days.isEmpty ? null : view.days.firstWhere((d) => d.isStudyDay, orElse: () => view.days.first).phase;
    final fmt = DateFormat('d MMM');
    return Row(
      children: [
        for (final p in PlanPhase.values)
          Expanded(
            child: Container(
              margin: EdgeInsets.only(right: p == PlanPhase.test ? 0 : Gap.tight),
              padding: const EdgeInsets.all(Gap.snug),
              decoration: BoxDecoration(
                color: p == now ? c.accentWash : c.surface,
                borderRadius: BorderRadius.circular(Radii.control),
                border: Border.all(color: p == now ? c.accent : c.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.label, style: t.titleSmall?.copyWith(color: p == now ? c.accent : c.ink)),
                  const SizedBox(height: 2),
                  Text(
                    (ranges[p] ?? const []).isEmpty
                        ? 'No days'
                        : ranges[p]!.length == 1
                            ? fmt.format(ranges[p]!.first)
                            : '${fmt.format(ranges[p]!.first)} to ${fmt.format(ranges[p]!.last)}',
                    style: t.bodySmall,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({required this.day});
  final PlanDay day;

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Gap.page - 4, vertical: Gap.snug),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(DateFormat('EEE d MMM').format(day.date), style: Mono.of(context, size: 13, color: c.ink)),
          ),
          Expanded(
            child: day.isStudyDay && day.tasks.isNotEmpty
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(day.phase.label, style: t.labelMedium?.copyWith(color: c.accent, fontWeight: FontWeight.w600)),
                      for (final task in day.tasks) Text(task.title, style: t.bodyMedium?.copyWith(color: c.ink)),
                    ],
                  )
                : Text(day.isStudyDay ? 'Nothing planned' : 'Day off', style: t.bodyMedium?.copyWith(color: c.inkFaint)),
          ),
          if (day.minutes > 0) Text('${day.minutes} min', style: Mono.of(context, size: 12, color: c.inkFaint)),
        ],
      ),
    );
  }
}
