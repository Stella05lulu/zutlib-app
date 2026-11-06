import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../state/governance_providers.dart';
import '../../study/audit_stats.dart';
import 'charts.dart';
import 'shelves.dart';
import 'study_widgets.dart';

/// The audit log at a glance: events per day for the last seven days (with
/// the week's total and the busiest day), and what kinds of events they
/// were, each with its count and share. Used on the Overview and at the
/// top of the Audit log screen.
class AuditActivity extends ConsumerWidget {
  const AuditActivity({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(auditStatsProvider);
    return StudyAsync<AuditStats>(
      value: async,
      onRetry: () => ref.invalidate(auditStatsProvider),
      skeleton: const RowsSkeleton(rows: 4),
      isEmpty: (_) => false,
      empty: const SizedBox.shrink(),
      data: (s) => LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth >= 760;
        final activity = _ActivityPanel(stats: s);
        final breakdown = _BreakdownPanel(stats: s);
        if (!wide) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            activity,
            const SizedBox(height: Gap.snug),
            breakdown,
          ]);
        }
        return IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(flex: 5, child: breakdown),
            const SizedBox(width: Gap.snug),
            Expanded(flex: 4, child: activity),
          ]),
        );
      }),
    );
  }
}

class _ActivityPanel extends StatelessWidget {
  const _ActivityPanel({required this.stats});
  final AuditStats stats;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final busiest = stats.busiest;
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Activity', style: t.titleLarge),
              Text('Audit events per day, last 7 days', style: t.bodySmall),
            ]),
          ),
          _Figure(value: '${stats.total}', label: 'this week'),
          if (busiest != null) ...[
            const SizedBox(width: Gap.page),
            _Figure(value: '${busiest.count}', label: 'busiest, ${DateFormat('EEE d').format(busiest.day)}'),
          ],
        ]),
        const SizedBox(height: Gap.page),
        LineChart(
          semanticLabel: 'Audit events per day, last 7 days',
          data: [for (final d in stats.days) BarDatum(DateFormat('EEE d').format(d.day), d.count.toDouble())],
        ),
      ]),
    );
  }
}

class _BreakdownPanel extends StatelessWidget {
  const _BreakdownPanel({required this.stats});
  final AuditStats stats;

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    final t = Theme.of(context).textTheme;
    final mono = Mono.of(context, size: 12.5, color: c.ink).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Event breakdown', style: t.titleLarge),
              Text('What happened this week, by kind of event', style: t.bodySmall),
            ]),
          ),
          _Figure(value: '${stats.total}', label: 'events'),
        ]),
        const SizedBox(height: Gap.snug),
        if (stats.breakdown.isEmpty)
          Text('No audit events in the last 7 days.', style: t.bodyMedium)
        else ...[
          Row(children: [
            Expanded(child: Text('Event', style: t.labelMedium?.copyWith(color: c.inkFaint))),
            SizedBox(width: 48, child: Text('Count', textAlign: TextAlign.right, style: t.labelMedium?.copyWith(color: c.inkFaint))),
            SizedBox(width: 60, child: Text('Share', textAlign: TextAlign.right, style: t.labelMedium?.copyWith(color: c.inkFaint))),
          ]),
          const SizedBox(height: Gap.hair),
          for (final e in stats.breakdown.take(8))
            Semantics(
              label: '${e.label}: ${e.count}, ${percent(e.share)}',
              excludeSemantics: true,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: Gap.tight),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Expanded(child: Text(e.label, style: t.bodyMedium?.copyWith(color: c.ink), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    SizedBox(width: 48, child: Text('${e.count}', textAlign: TextAlign.right, style: mono)),
                    SizedBox(width: 60, child: Text(percent(e.share), textAlign: TextAlign.right, style: mono.copyWith(color: c.accent))),
                  ]),
                  const SizedBox(height: Gap.hair + 1),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.tag),
                    child: LinearProgressIndicator(value: e.share, minHeight: 4, backgroundColor: c.sunken, color: c.accent),
                  ),
                ]),
              ),
            ),
          if (stats.breakdown.length > 8)
            Padding(
              padding: const EdgeInsets.only(top: Gap.tight),
              child: Text('and ${stats.breakdown.length - 8} more kinds', style: t.bodySmall),
            ),
        ],
      ]),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Text(value,
          style: Mono.of(context, size: 22, color: c.ink)
              .copyWith(fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()])),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ]);
  }
}
