import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/governance_repository.dart' show ProgressData;
import '../../../state/governance_providers.dart';
import '../../../study/progress.dart';
import '../../widgets/charts.dart';
import '../../widgets/shelves.dart';
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
          appBar: const StudyTopBar(title: 'My progress'),
          body: StudyPage(
            onRefresh: () async {
              ref.invalidate(progressDataProvider);
              try {
                await ref.read(progressDataProvider.future);
              } catch (_) {
                // Shown on the page.
              }
            },
            children: [
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
    final change = recentChange(points);

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
        StatGrid(children: [
          StatTile(value: '${points.length}', label: points.length == 1 ? 'Attempt' : 'Attempts'),
          StatTile(value: '${(avg * 100).round()}%', label: 'Average score'),
          StatTile(
            value: change == null ? 'Not yet' : '${change >= 0 ? '+' : ''}${(change * 100).round()}%',
            label: 'Last 3 against the 3 before',
            detail: change == null ? 'Needs 6 attempts' : (change >= 0 ? 'Going up' : 'Going down'),
            alert: change != null && change < 0,
          ),
        ]),
        const ShelfHeading('Score over time'),
        if (shown.isEmpty)
          const StudyEmptyState('No attempts for this choice yet.', compact: true)
        else
          Panel(
            child: BarChart(
              semanticLabel: 'Scores of your last ${shown.length} attempts',
              maxValue: 100,
              data: [
                for (final p in shown)
                  BarDatum(DateFormat('d/M').format(p.at), p.percent * 100, valueText: '${(p.percent * 100).round()}'),
              ],
            ),
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
