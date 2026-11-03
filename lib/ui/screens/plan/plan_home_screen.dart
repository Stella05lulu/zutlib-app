import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme.dart' show kNavClearance;
import '../../../core/theme/app_theme.dart';
import '../../../models/study.dart' show KitColorX;
import '../../../state/plan_providers.dart';
import '../../../state/study_providers.dart';
import '../../../study/planner.dart';
import '../../widgets/notification_bell.dart';
import '../../widgets/study_widgets.dart';
import '../study/kit_widgets.dart' show KitEmpty;
import 'plan_sheet.dart';
import 'plan_widgets.dart';

/// The Plan tab: today's tasks from every exam plan, the week ahead, and
/// each upcoming exam with its countdown and status.
class PlanHomeScreen extends ConsumerWidget {
  const PlanHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final views = ref.watch(upcomingPlansProvider);

    Future<void> refresh() async {
      refreshPlans(ref);
      ref.invalidate(kitListProvider);
      try {
        await ref.read(upcomingPlansProvider.future);
      } catch (_) {
        // The page shows its own error state.
      }
    }

    return StudyScope(
      child: Builder(builder: (context) {
        final t = Theme.of(context).textTheme;
        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: StudyPage(
              bottom: kNavClearance,
              onRefresh: refresh,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('Plan', style: t.headlineSmall?.copyWith(fontSize: 28, fontWeight: FontWeight.w700))),
                    const NotificationBell(),
                  ],
                ),
                Text('Your exams, and what to study each day to be ready for them.',
                    style: t.bodyLarge?.copyWith(color: StudyColors.of(context).inkSoft)),
                const SizedBox(height: Gap.snug),
                const StreakLine(),
                const SizedBox(height: Gap.page),
                StudyAsync<List<PlanView>>(
                  value: views,
                  onRetry: () => ref.invalidate(upcomingPlansProvider),
                  skeleton: const RowsSkeleton(rows: 4),
                  isEmpty: (v) => v.isEmpty,
                  empty: KitEmpty(
                    icon: Icons.event_note_outlined,
                    title: 'Plan for your exams',
                    sentence: 'Add an exam, choose the days you can study, and ZutLib builds a day-by-day '
                        'plan from your study kit: learn first, then practise, then test.',
                    actions: [
                      FilledButton.icon(
                        onPressed: () => _add(context, ref),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add an exam'),
                      ),
                    ],
                  ),
                  data: (list) => _PlanBody(views: list, onAdd: () => _add(context, ref)),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final kits = await ref.read(kitListProvider.future).catchError((_) => const <KitSummary>[]);
    if (!context.mounted) return;
    if (kits.isEmpty) {
      final go = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Make a study kit first'),
          content: const Text('A plan is built from a study kit: its guide, flashcards and questions. '
              'Make a kit from your notes or a past paper, then add the exam.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not now')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Go to Study')),
          ],
        ),
      );
      if (go == true && context.mounted) context.go('/study');
      return;
    }
    final plan = await showPlanSheet(context);
    if (plan != null && context.mounted) unawaited(context.push('/plan/${plan.id}'));
  }
}

class _PlanBody extends StatelessWidget {
  const _PlanBody({required this.views, required this.onAdd});
  final List<PlanView> views;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    final t = Theme.of(context).textTheme;
    final today = [for (final v in views) if (v.today != null) for (final task in v.today!.tasks) (v, task)];
    final done = today.where((x) => x.$1.done(x.$2)).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(
          today.isEmpty ? 'Today' : 'Today  $done of ${today.length} done',
          top: 0,
        ),
        if (today.isEmpty)
          const StudyEmptyState('Nothing planned for today. Enjoy the rest day.', compact: true)
        else
          RowGroup(children: [for (final (v, task) in today) PlanTaskRow(view: v, task: task, showKit: true)]),
        const SectionLabel('This week'),
        _WeekStrip(views: views),
        SectionLabel('Upcoming exams',
            action: TextButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add an exam'),
            )),
        for (final v in views) ...[
          _ExamCard(view: v),
          const SizedBox(height: Gap.snug),
        ],
        Text('Tasks tick themselves as you study: rate flashcards, answer Smart study questions, '
            'take tests and mark guide sections read.',
            style: t.bodySmall?.copyWith(color: c.inkFaint)),
      ],
    );
  }
}

/// Seven days from today: how many tasks each holds, and exam days.
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({required this.views});
  final List<PlanView> views;

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    final t = Theme.of(context).textTheme;
    final start = dateOnly(DateTime.now());
    return Row(
      children: [
        for (var i = 0; i < 7; i++)
          Builder(builder: (context) {
            final d = start.add(Duration(days: i));
            final tasks = views.fold<int>(
                0, (s, v) => s + v.days.where((x) => x.date == d).fold<int>(0, (a, x) => a + x.tasks.length));
            final exam = views.any((v) => dateOnly(v.plan.examDate) == d);
            final isToday = i == 0;
            return Expanded(
              child: Container(
                margin: EdgeInsets.only(right: i == 6 ? 0 : Gap.hair + 2),
                padding: const EdgeInsets.symmetric(vertical: Gap.snug),
                decoration: BoxDecoration(
                  color: exam ? c.accentWash : c.surface,
                  borderRadius: BorderRadius.circular(Radii.control),
                  border: Border.all(color: isToday ? c.accent : c.line, width: isToday ? 1.5 : 1),
                ),
                child: Column(
                  children: [
                    Text(DateFormat('EEE').format(d), style: t.labelSmall?.copyWith(color: c.inkSoft)),
                    Text('${d.day}', style: Mono.of(context, size: 16, weight: FontWeight.w600, color: c.ink)),
                    const SizedBox(height: 2),
                    Text(exam ? 'Exam' : (tasks == 0 ? 'Off' : '$tasks'),
                        style: t.labelSmall?.copyWith(
                            color: exam ? c.accent : (tasks == 0 ? c.inkFaint : c.inkSoft),
                            fontWeight: exam ? FontWeight.w600 : FontWeight.w500)),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }
}

class _ExamCard extends StatelessWidget {
  const _ExamCard({required this.view});
  final PlanView view;

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    final t = Theme.of(context).textTheme;
    final fill = KitPalette.fill(view.note.color.wire);
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.panel),
        side: BorderSide(color: c.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/plan/${view.plan.id}'),
        child: Padding(
          padding: const EdgeInsets.all(Gap.page - 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(width: 10, height: 36, decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(Radii.tag))),
                  const SizedBox(width: Gap.snug),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(view.note.title, style: t.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(
                          '${examCountdown(view.plan.examDate, DateTime.now())}  /  '
                          '${DateFormat('EEE d MMM').format(view.plan.examDate)}',
                          style: t.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  PlanStatusTag(view.health),
                ],
              ),
              const SizedBox(height: Gap.snug),
              MasteryBar(value: view.mastery),
              if (view.todayTotal > 0) ...[
                const SizedBox(height: Gap.tight),
                Text('Today: ${view.todayDone} of ${view.todayTotal} tasks done', style: t.bodySmall),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
