import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/study.dart';
import '../../../state/study_providers.dart';
import '../../../study/practice.dart';
import '../../widgets/study_widgets.dart';
import 'kit_widgets.dart';

/// Make a timed test from the kit's question bank (how many questions,
/// how hard, how long), and see every test taken so far.
class KitTestTab extends ConsumerStatefulWidget {
  const KitTestTab({super.key, required this.kit, required this.onChanged});
  final KitData kit;
  final VoidCallback onChanged;

  @override
  ConsumerState<KitTestTab> createState() => _KitTestTabState();
}

class _KitTestTabState extends ConsumerState<KitTestTab> {
  static const _levels = ['easy', 'mixed', 'hard'];
  static const _times = [0, 5, 10, 15, 20, 30, 45, 60];

  int _count = 10;
  int _level = 1;
  int _minutes = 10;
  bool _busy = false;
  String? _error;

  List<TestQuestion> get _bank => [for (final q in widget.kit.questions) (id: q.id, difficulty: q.difficulty)];

  Future<void> _create(int existing) async {
    final kit = widget.kit;
    final quiz = kit.quiz;
    if (quiz == null) return;
    final count = min(_count, _bank.length);
    final ids = pickTestQuestions(_bank, count, _levels[_level], Random());
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final test = await studyRepo.createTest(
        noteId: kit.note.id,
        quizId: quiz.id,
        title: 'Practice test ${existing + 1}',
        questionIds: ids,
        difficulty: _levels[_level],
        timeLimitSeconds: _minutes * 60,
      );
      if (!mounted) return;
      ref.invalidate(testsProvider(kit.note.id));
      unawaited(context.push('/study/test/${test.id}'));
    } on Failure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(StudyTest test) async {
    final ok = await confirmDelete(context, what: test.title, consequence: 'Its scores are deleted too.');
    if (!ok) return;
    try {
      await studyRepo.deleteTest(test.id);
      ref.invalidate(testsProvider(widget.kit.note.id));
    } on Failure catch (f) {
      if (mounted) setState(() => _error = f.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    final t = Theme.of(context).textTheme;
    final kit = widget.kit;

    if (kit.questions.isEmpty) {
      return StudyPage(children: [
        KitEmpty(
          icon: Icons.assignment_outlined,
          title: 'No questions to test you on yet',
          sentence: 'Tests are drawn from the kit\'s question bank. Build the kit with AI, or write questions in Smart study.',
          actions: [
            if (kit.note.hasMaterials)
              FilledButton.icon(
                onPressed: () => buildKitWithAi(context, ref, kit.note.id),
                icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                label: const Text('Build with AI'),
              ),
          ],
        ),
      ]);
    }

    final available = questionsAvailable(_bank, _levels[_level]);
    final maxCount = min(100, _bank.length);
    final count = _count.clamp(1, maxCount);
    final testsAsync = ref.watch(testsProvider(kit.note.id));
    final existing = testsAsync.valueOrNull?.length ?? 0;

    return StudyPage(
      onRefresh: () async => ref.invalidate(testsProvider(kit.note.id)),
      children: [
        Text('Create test', style: t.headlineSmall),
        const SizedBox(height: Gap.page),
        Container(
          padding: const EdgeInsets.all(Gap.page),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(Radii.panel),
            border: Border.all(color: c.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Heading(icon: Icons.quiz_outlined, text: 'Questions'),
              const SizedBox(height: Gap.tight),
              Row(
                children: [
                  Expanded(child: Text('Multiple choice', style: t.bodyLarge)),
                  IconButton.outlined(
                    tooltip: 'Fewer',
                    icon: const Icon(Icons.remove, size: 18),
                    // Steps of 5 above 10, so a 60-question exam is a few taps.
                    onPressed: count > 1 ? () => setState(() => _count = count > 10 ? count - 5 : count - 1) : null,
                  ),
                  SizedBox(
                    width: 48,
                    child: Text('$count', textAlign: TextAlign.center, style: Mono.of(context, size: 17, color: c.ink)),
                  ),
                  IconButton.outlined(
                    tooltip: 'More',
                    icon: const Icon(Icons.add, size: 18),
                    onPressed: count < maxCount
                        ? () => setState(() => _count = min(maxCount, count >= 10 ? count + 5 : count + 1))
                        : null,
                  ),
                ],
              ),
              Text('${_bank.length} questions in this kit', style: t.bodySmall),
              const SizedBox(height: Gap.page),
              const _Heading(icon: Icons.speed_outlined, text: 'Difficulty'),
              Slider(
                value: _level.toDouble(),
                min: 0,
                max: 2,
                divisions: 2,
                label: ['Easy', 'Mixed', 'Hard'][_level],
                onChanged: (v) => setState(() => _level = v.round()),
              ),
              Row(
                children: [
                  Text('Easy', style: t.bodySmall),
                  const Spacer(),
                  Text('Mixed', style: t.bodySmall),
                  const Spacer(),
                  Text('Hard', style: t.bodySmall),
                ],
              ),
              if (_level != 1 && available < count) ...[
                const SizedBox(height: Gap.tight),
                Text(
                  'Only $available ${_level == 0 ? 'easy' : 'hard'} ${available == 1 ? 'question' : 'questions'}; '
                  'the nearest level fills the rest.',
                  style: t.bodySmall,
                ),
              ],
              const SizedBox(height: Gap.page),
              Row(
                children: [
                  const _Heading(icon: Icons.timer_outlined, text: 'Time limit'),
                  const Spacer(),
                  DropdownButton<int>(
                    value: _minutes,
                    underline: const SizedBox.shrink(),
                    borderRadius: BorderRadius.circular(Radii.control),
                    items: [
                      for (final m in _times)
                        DropdownMenuItem(value: m, child: Text(m == 0 ? 'No limit' : '$m min')),
                    ],
                    onChanged: (v) => setState(() => _minutes = v ?? _minutes),
                  ),
                ],
              ),
              const SizedBox(height: Gap.page),
              if (_error != null) ...[
                InlineNotice(_error!, error: true, onClose: () => setState(() => _error = null)),
                const SizedBox(height: Gap.snug),
              ],
              Center(
                child: FilledButton.icon(
                  onPressed: _busy ? null : () => _create(existing),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(_busy ? 'Making the test' : 'Create test'),
                ),
              ),
            ],
          ),
        ),
        const SectionLabel('Your tests'),
        StudyAsync<List<StudyTest>>(
          value: testsAsync,
          onRetry: () => ref.invalidate(testsProvider(kit.note.id)),
          skeleton: const RowsSkeleton(rows: 2, detail: false),
          isEmpty: (v) => v.isEmpty,
          empty: const StudyEmptyState('No tests have been created for this study kit yet.', compact: true),
          data: (tests) => RowGroup(children: [
            for (final test in tests)
              StudyRow(
                title: test.title,
                meta: [
                  '${test.questionIds.length} questions',
                  switch (test.difficulty) { 'easy' => 'easy', 'hard' => 'hard', _ => 'mixed' },
                  test.timeLimitSeconds == 0 ? 'no time limit' : '${test.timeLimitSeconds ~/ 60} min',
                  if (test.best != null) 'best ${test.best!.percent}%',
                  '${test.attempts.length} ${test.attempts.length == 1 ? 'attempt' : 'attempts'}',
                ].join('  /  '),
                onTap: () => context.push('/study/test/${test.id}'),
                trailing: PopupMenuButton<String>(
                  tooltip: 'Test options',
                  icon: const Icon(Icons.more_horiz),
                  onSelected: (_) => _delete(test),
                  itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Delete'))],
                ),
              ),
          ]),
        ),
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: c.accent),
        const SizedBox(width: Gap.tight),
        Text(text, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}
