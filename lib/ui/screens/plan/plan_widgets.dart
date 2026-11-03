import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../../state/plan_providers.dart';
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

  Future<void> _toggle(bool done) async {
    setState(() => _busy = true);
    try {
      await planRepo.setCheck(widget.view.plan.id, dateOnly(DateTime.now()), widget.task.key, !done);
      ref.invalidate(todayChecksProvider);
    } on Failure catch (f) {
      if (mounted) showMessage(context, f.message, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    final t = Theme.of(context).textTheme;
    final task = widget.task;
    final done = widget.view.done(task);
    final autoDone = done && !widget.view.ticked.contains(task.key);
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
              onChanged: _busy || autoDone ? null : (_) => _toggle(done),
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
