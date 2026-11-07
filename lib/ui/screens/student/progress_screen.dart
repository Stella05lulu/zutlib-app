import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme.dart' show kNavClearance;
import '../../../core/theme/app_theme.dart';
import '../../../data/governance_repository.dart' show ProgressData;
import '../../../state/governance_providers.dart';
import '../../../study/progress.dart';
import '../../widgets/charts.dart';
import '../../widgets/shelves.dart';
import '../../widgets/section_switch.dart';
import '../../widgets/study_widgets.dart';

/// My progress: scores over time for one kit or one course, and the
/// questions to revise next, each with the rule that picked it.
class ProgressScreen extends ConsumerStatefulWidget {
  const ProgressScreen({super.key});

  @override
  ConsumerState<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends ConsumerState<ProgressScreen> {
  bool _byCourse = false;
  String? _pick; // kit id or normalised course code; null = everything

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(progressDataProvider);
    return StudyScope(
      child: Builder(builder: (context) {
        return Scaffold(
          body: SafeArea(
           bottom: false,
           child: StudyPage(
            // Same width as Kits, so switching between Kits, Plan and
            // Progress does not make the page jump.
            maxWidth: 1080,
            bottom: kNavClearance,
            onRefresh: () async {
              ref.invalidate(progressDataProvider);
              try {
                await ref.read(progressDataProvider.future);
              } catch (_) {
                // Shown on the page.
              }
            },
            children: [
              const SizedBox(height: Gap.tight),
              const SectionHeader(title: 'Study', sections: studySections),
              const SizedBox(height: Gap.page),
              StudyAsync<ProgressData>(
                value: async,
                onRetry: () => ref.invalidate(progressDataProvider),
                skeleton: const RowsSkeleton(rows: 5),
                isEmpty: (d) => d.attempts.isEmpty,
                empty: StudyEmptyState(
                  'Take a test or a quiz in any study kit and your scores will show here.',
                  action: OutlinedButton(onPressed: () => context.go('/study'), child: const Text('Open study kits')),
                ),
                data: (d) => _Body(
                  data: d,
                  byCourse: _byCourse,
                  pick: _pick,
                  onMode: (v) => setState(() {
                    _byCourse = v;
                    _pick = null;
                  }),
                  onPick: (v) => setState(() => _pick = v),
                ),
              ),
            ],
           ),
          ),
        );
      }),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.data,
    required this.byCourse,
    required this.pick,
    required this.onMode,
    required this.onPick,
  });

  final ProgressData data;
  final bool byCourse;
  final String? pick;
  final ValueChanged<bool> onMode;
  final ValueChanged<String?> onPick;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = StudyColors.of(context);

    // The choices: kits that have attempts, or their courses.
    final kitIds = {for (final a in data.attempts) if (a.noteId != null) a.noteId!};
    final courses = <String, String>{
      for (final a in data.attempts)
        if ((a.courseCode ?? '').isNotEmpty) normaliseCode(a.courseCode): a.courseCode!,
    };
    final options = byCourse
        ? [for (final e in courses.entries) (e.key, e.value)]
        : [for (final id in kitIds) (id, data.kits[id]?.$1 ?? 'Kit')];

    final points = byCourse
        ? scoreSeries(data.attempts, courseCode: pick)
        : scoreSeries(data.attempts, noteId: pick);
    final shown = points.length > 12 ? points.sublist(points.length - 12) : points;
    final avg = points.isEmpty ? 0.0 : points.map((p) => p.percent).reduce((a, b) => a + b) / points.length;
    final latest = points.isEmpty ? null : points.last.percent;
    final before = points.length < 2 ? null : points[points.length - 2].percent;
    final pct = (double v) => '${(v * 100).round()}%';

    final scoped = data.attempts.where((a) => pick == null ||
        (byCourse ? normaliseCode(a.courseCode) == pick : a.noteId == pick));
    final revise = reviseNext(scoped, data.questions);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: false, label: Text('By kit')),
            ButtonSegment(value: true, label: Text('By course')),
          ],
          selected: {byCourse},
          onSelectionChanged: (s) => onMode(s.first),
        ),
        const SizedBox(height: Gap.snug),
        if (options.isEmpty)
          Text(byCourse ? 'Give your kits a course code to see scores by course.' : '', style: t.bodySmall)
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              Padding(
                padding: const EdgeInsets.only(right: Gap.tight),
                child: ChoiceChip(label: const Text('All'), selected: pick == null, onSelected: (_) => onPick(null)),
              ),
              for (final (id, label) in options)
                Padding(
                  padding: const EdgeInsets.only(right: Gap.tight),
                  child: ChoiceChip(
                    label: Text(label, overflow: TextOverflow.ellipsis),
                    selected: pick == id,
                    onSelected: (_) => onPick(id),
                  ),
                ),
            ]),
          ),
        const SizedBox(height: Gap.page),
        // Three plain figures: how many tests, the average, and the latest
        // compared with the one before it.
        StatGrid(children: [
          StatTile(value: '${points.length}', label: points.length == 1 ? 'Test taken' : 'Tests taken'),
          StatTile(value: pct(avg), label: 'Average score'),
          StatTile(
            value: latest == null ? '–' : pct(latest),
            label: 'Latest score',
            detail: before == null
                ? 'Take another test to compare'
                : latest! == before
                    ? 'Same as the test before'
                    : '${latest > before ? 'Up' : 'Down'} ${((latest - before).abs() * 100).round()}% on the test before',
            alert: before != null && latest! < before,
          ),
        ]),
        const ShelfHeading('Your test scores'),
        Text('Each bar is one test or quiz, oldest on the left. Taller is better: 100% means every answer was right.',
            style: t.bodySmall?.copyWith(color: c.inkSoft)),
        const SizedBox(height: Gap.tight),
        if (shown.isEmpty)
          const StudyEmptyState('No tests for this choice yet.', compact: true)
        else
          Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              BarChart(
                semanticLabel: 'Scores of your last ${shown.length} tests',
                maxValue: 100,
                barWidth: 40,
                data: [
                  for (final p in shown)
                    BarDatum(DateFormat('d MMM').format(p.at), p.percent * 100, valueText: pct(p.percent)),
                ],
              ),
              if (shown.length == 1) ...[
                const SizedBox(height: Gap.tight),
                Text('Take more tests to see how your scores change over time.',
                    style: t.bodySmall?.copyWith(color: c.inkFaint)),
              ],
            ]),
          ),
        const ShelfHeading('Revise next'),
        if (revise.isEmpty)
          const StudyEmptyState('Nothing stands out. Keep taking tests to stay sharp.', compact: true)
        else
          RowGroup(children: [
            for (final r in revise)
              StudyRow(
                title: r.question.prompt,
                detail: r.reason,
                meta: r.question.noteId == null ? null : data.kits[r.question.noteId]?.$1,
                detailLines: 1,
                trailing: Icon(Icons.chevron_right, size: 20, color: c.inkFaint),
                onTap: r.question.noteId == null ? null : () => context.push('/study/note/${r.question.noteId}'),
              ),
          ]),
        const SizedBox(height: Gap.tight),
        Text('Suggested by simple rules: a question appears when you got it wrong in at least half of '
            'your last four tries.', style: t.bodySmall),
      ],
    );
  }
}
