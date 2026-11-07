import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../../state/plan_providers.dart';
import '../../../study/plan_demo.dart';
import '../../../study/planner.dart';
import '../../widgets/common.dart' show showMessage;

/// One task: a tick box, what to do, and why. The box ticks itself when
/// the work is done; tapping it ticks or unticks by hand. Tapping the row
/// opens the right part of the kit.
class PlanTaskRow extends ConsumerStatefulWidget {
  const PlanTaskRow({super.key, required this.view, required this.task, this.showKit = false});
  final PlanView view;
  final PlanTask task;
  final bool showKit;

  @override
  ConsumerState<PlanTaskRow> createState() => _PlanTaskRowState();
}

class _PlanTaskRowState extends ConsumerState<PlanTaskRow> {
  bool _busy = false;

  /// What the box shows while a tap is being saved, so it ticks at once
  /// instead of waiting for the database and the plan to reload.
  bool? _pending;

  @override
  void didUpdateWidget(covariant PlanTaskRow old) {
    super.didUpdateWidget(old);
    // The reloaded plan now agrees with the tap: stop overriding it.
    if (_pending != null && !_busy && widget.view.done(widget.task) == _pending) {
      _pending = null;
    }
  }

  Future<void> _toggle(bool done) async {
    if (widget.view.isDemo) {
      ref.read(planDemoProvider.notifier).update((d) => d?.toggle(widget.task.key));
      return;
    }
    setState(() {
      _busy = true;
      _pending = !done;
    });
    try {
      await planRepo.setCheck(widget.view.plan.id, dateOnly(DateTime.now()), widget.task.key, !done);
      ref.invalidate(todayChecksProvider);
    } on Failure catch (f) {
      // Not saved: put the box back the way it was.
      if (mounted) {
        setState(() => _pending = null);
        showMessage(context, f.message, isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          if (widget.view.done(widget.task) == _pending) _pending = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    final t = Theme.of(context).textTheme;
    final task = widget.task;
    final saved = widget.view.done(task);
    final done = _pending ?? saved;
    final autoDone = saved && !widget.view.ticked.contains(task.key);
    return InkWell(
      onTap: () async {
        await context.push('/study/note/${widget.view.plan.noteId}?tab=${task.kind.tab}');
        // Back from studying: re-read activity so finished tasks tick.
        if (mounted) refreshPlans(ref);
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.tight, Gap.tight, Gap.page - 4, Gap.tight),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: done,
              // A task the app ticked from your study stays ticked.
              onChanged: autoDone ? null : (_) {
                if (!_busy) _toggle(done);
              },
            ),
            const SizedBox(width: Gap.hair),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: Gap.snug - 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      style: t.bodyLarge?.copyWith(
                        color: done ? c.inkFaint : c.ink,
                        decoration: done ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.showKit ? '${widget.view.note.title}  /  ${task.reason}' : task.reason,
                      style: t.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: Gap.snug - 2, left: Gap.tight),
              child: Text('${task.minutes} min', style: Mono.of(context, size: 12, color: c.inkFaint)),
            ),
          ],
        ),
      ),
    );
  }
}

/// The controls for a running demo: move through the plan a day or a phase
/// at a time, miss a day to show catch-up work, go back, restart or leave.
class PlanDemoBar extends ConsumerWidget {
  const PlanDemoBar({super.key, required this.demo});
  final PlanDemo demo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = StudyColors.of(context);
    final t = Theme.of(context).textTheme;
    void set(PlanDemo? next) => ref.read(planDemoProvider.notifier).state = next;
    final next = demo.nextPhase;

    return Material(
      color: c.accentWash,
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(border: Border(top: BorderSide(color: c.accent))),
          padding: const EdgeInsets.fromLTRB(Gap.page, Gap.tight, Gap.tight, Gap.snug),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.slideshow_outlined, size: 18, color: c.accent),
                const SizedBox(width: Gap.tight),
                Expanded(
                  child: Text(
                    demo.isFinished
                        ? 'Demo mode  /  Exam day'
                        : 'Demo mode  /  Day ${demo.dayNumber} of ${demo.totalDays}  /  '
                            '${DateFormat('EEE d MMM').format(demo.date)}',
                    style: t.titleSmall?.copyWith(color: c.ink),
                  ),
                ),
                TextButton(onPressed: () => set(null), child: const Text('Exit demo')),
              ]),
              Text('Nothing here is saved. Your real plan and progress stay as they are.', style: t.bodySmall),
              const SizedBox(height: Gap.tight),
              Wrap(spacing: Gap.tight, runSpacing: Gap.tight, children: [
                if (!demo.isFinished) ...[
                  FilledButton(
                    onPressed: () => set(demo.completeDay()),
                    child: Text(demo.allTicked ? 'Next day' : 'Complete day'),
                  ),
                  if (!demo.allTicked)
                    OutlinedButton(onPressed: () => set(demo.missDay()), child: const Text('Miss this day')),
                  OutlinedButton(
                    onPressed: () => set(demo.jump()),
                    child: Text(next == null ? 'Jump to exam day' : 'Jump to ${next.label}'),
                  ),
                ],
                if (demo.previous != null)
                  TextButton(onPressed: () => set(demo.back()), child: const Text('Back')),
                TextButton(onPressed: () => set(demo.restart()), child: const Text('Restart')),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

/// On track, Behind, Ready or Exam passed, as a small coloured label.
class PlanStatusTag extends StatelessWidget {
  const PlanStatusTag(this.health, {super.key});
  final PlanHealth health;

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    final (fg, bg) = switch (health.status) {
      PlanStatus.onTrack => (c.success, c.successWash),
      PlanStatus.behind => (c.warn, c.warnWash),
      PlanStatus.ready => (c.accent, c.accentWash),
      PlanStatus.finished => (c.inkSoft, c.sunken),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.tight, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(Radii.tag)),
      child: Text(health.label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(color: fg, fontWeight: FontWeight.w600)),
    );
  }
}

/// How much of the kit is learnt, with the last milestone reached.
class MasteryBar extends StatelessWidget {
  const MasteryBar({super.key, required this.value});
  final double value;

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    final m = milestone(value);
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Radii.tag),
            child: LinearProgressIndicator(
              value: value.clamp(0, 1).toDouble(),
              minHeight: 6,
              color: c.accent,
              backgroundColor: c.sunken,
            ),
          ),
        ),
        const SizedBox(width: Gap.snug),
        Text(m == 0 ? '${(value * 100).round()}% learnt' : '$m% milestone',
            style: Mono.of(context, size: 12, color: c.inkSoft)),
      ],
    );
  }
}

/// The days in a row with study, or a nudge to start.
class StreakLine extends ConsumerWidget {
  const StreakLine({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = StudyColors.of(context);
    final streak = ref.watch(streakProvider).valueOrNull ?? 0;
    return Row(
      children: [
        Icon(Icons.local_fire_department_outlined, size: 18, color: streak > 0 ? c.warn : c.inkFaint),
        const SizedBox(width: Gap.hair),
        Text(
          streak == 0 ? 'Study today to start a streak' : '$streak-day study streak',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: streak > 0 ? c.ink : c.inkSoft),
        ),
      ],
    );
  }
}
