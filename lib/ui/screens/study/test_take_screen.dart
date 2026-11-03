import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/study.dart';
import '../../../state/study_providers.dart';
import '../../../study/practice.dart';
import '../../widgets/study_widgets.dart';
import '../../../state/plan_providers.dart' show accountRepo;

/// Taking a test: one question at a time against the clock. When time
/// runs out the test is handed in as it stands. The database marks it;
/// the results show what was right, what was wrong, and why.
class TestTakeScreen extends ConsumerWidget {
  const TestTakeScreen({super.key, required this.testId});
  final String testId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final testAsync = ref.watch(testProvider(testId));
    final test = testAsync.valueOrNull;
    final questionsAsync = test == null ? null : ref.watch(questionsProvider(test.quizId));

    return StudyScope(
      child: Builder(builder: (context) {
        if (testAsync.hasError || (questionsAsync?.hasError ?? false)) {
          return Scaffold(
            appBar: const StudyTopBar(title: 'Test'),
            body: StudyPage(children: [
              StudyErrorState(
                message: '${testAsync.error ?? questionsAsync?.error}',
                onRetry: () => ref.invalidate(testProvider(testId)),
              ),
            ]),
          );
        }
        if (testAsync.hasValue && test == null) {
          return const Scaffold(
            appBar: StudyTopBar(title: 'Test'),
            body: StudyPage(children: [StudyEmptyState('This test could not be found. It may have been deleted.')]),
          );
        }
        final all = questionsAsync?.valueOrNull;
        if (test == null || all == null) {
          return const Scaffold(
            appBar: StudyTopBar(title: 'Test'),
            body: StudyPage(children: [QuestionSkeleton()]),
          );
        }
        final byId = {for (final q in all) q.id: q};
        final questions = [for (final id in test.questionIds) if (byId[id] != null) byId[id]!];
        if (questions.isEmpty) {
          return Scaffold(
            appBar: StudyTopBar(title: test.title),
            body: const StudyPage(children: [
              StudyEmptyState('Every question in this test has been deleted from the question bank.'),
            ]),
          );
        }
        return _TestRun(test: test, questions: questions);
      }),
    );
  }
}

class _TestRun extends ConsumerStatefulWidget {
  const _TestRun({required this.test, required this.questions});
  final StudyTest test;
  final List<QuizQuestion> questions;

  @override
  ConsumerState<_TestRun> createState() => _TestRunState();
}

class _TestRunState extends ConsumerState<_TestRun> {
  final _answers = <String, int>{};
  int _index = 0;
  int _elapsed = 0;
  Timer? _clock;
  bool _submitting = false;
  TestAttempt? _result;
  String? _error;

  int get _limit => widget.test.timeLimitSeconds;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    _clock?.cancel();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _result != null) return;
      setState(() => _elapsed++);
      if (_limit > 0 && _elapsed >= _limit && !_submitting) unawaited(_submit());
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final attempt = await studyRepo.submitTest(widget.test.id, _answers, _elapsed);
      unawaited(accountRepo.logEvent('test_taken'));
      if (!mounted) return;
      _clock?.cancel();
      setState(() => _result = attempt);
      ref.invalidate(testProvider(widget.test.id));
      final noteId = widget.test.noteId;
      if (noteId != null) ref.invalidate(testsProvider(noteId));
    } on Failure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _confirmSubmit() async {
    final blank = widget.questions.length - _answers.length;
    if (blank == 0) return _submit();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StudyScope(
        child: AlertDialog(
          title: const Text('Hand in the test?'),
          content: Text('$blank ${blank == 1 ? 'question is' : 'questions are'} not answered and will count as wrong.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep going')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Hand in')),
          ],
        ),
      ),
    );
    if (ok == true) await _submit();
  }

  void _again() {
    setState(() {
      _answers.clear();
      _index = 0;
      _elapsed = 0;
      _result = null;
      _error = null;
    });
    _start();
  }

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    final t = Theme.of(context).textTheme;
    final result = _result;
    final remaining = _limit > 0 ? _limit - _elapsed : null;
    final clock = remaining != null ? clockLabel(remaining) : clockLabel(_elapsed);
    final hurry = remaining != null && remaining <= 60;

    return PopScope(
      canPop: result != null || _answers.isEmpty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await showDialog<bool>(
          context: context,
          builder: (ctx) => StudyScope(
            child: AlertDialog(
              title: const Text('Leave the test?'),
              content: const Text('Your answers are not saved until you hand the test in.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Stay')),
                TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Leave')),
              ],
            ),
          ),
        );
        if (leave == true && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: StudyTopBar(
          title: widget.test.title,
          actions: [
            if (result == null)
              Padding(
                padding: const EdgeInsets.only(right: Gap.snug),
                child: Row(
                  children: [
                    Icon(Icons.timer_outlined, size: 18, color: hurry ? c.danger : c.inkSoft),
                    const SizedBox(width: 4),
                    Text(clock, style: Mono.of(context, size: 15, weight: FontWeight.w600, color: hurry ? c.danger : c.ink)),
                  ],
                ),
              ),
          ],
        ),
        body: result != null ? _results(context, result) : _question(context, t, c),
      ),
    );
  }

  Widget _question(BuildContext context, TextTheme t, StudyColors c) {
    final q = widget.questions[_index];
    final last = _index == widget.questions.length - 1;
    return StudyPage(
      children: [
        Text('Question ${_index + 1} of ${widget.questions.length}', style: Mono.of(context, size: 12.5)),
        const SizedBox(height: Gap.tight),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: (_index + 1) / widget.questions.length,
            minHeight: 6,
            color: c.accent,
          ),
        ),
        const SizedBox(height: Gap.section),
        Text(q.prompt, style: t.titleLarge?.copyWith(fontSize: 21, height: 1.4)),
        const SizedBox(height: Gap.page),
        for (var i = 0; i < q.options.length; i++) ...[
          _Choice(
            letter: String.fromCharCode(65 + i),
            text: q.options[i],
            selected: _answers[q.id] == i,
            onTap: _submitting ? null : () => setState(() => _answers[q.id] = i),
          ),
          const SizedBox(height: Gap.tight + 2),
        ],
        if (_error != null) ...[
          const SizedBox(height: Gap.snug),
          InlineNotice(_error!, error: true),
        ],
        const SizedBox(height: Gap.page),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _index == 0 ? null : () => setState(() => _index--),
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Back'),
            ),
            const Spacer(),
            if (!last)
              FilledButton.icon(
                onPressed: () => setState(() => _index++),
                icon: const Icon(Icons.arrow_forward, size: 18),
                label: const Text('Next'),
              )
            else
              FilledButton(
                onPressed: _submitting ? null : _confirmSubmit,
                child: Text(_submitting ? 'Marking' : 'Hand in test'),
              ),
          ],
        ),
        const SizedBox(height: Gap.page),
        Wrap(
          spacing: Gap.tight,
          runSpacing: Gap.tight,
          children: [
            for (var i = 0; i < widget.questions.length; i++)
              InkWell(
                onTap: () => setState(() => _index = i),
                borderRadius: BorderRadius.circular(Radii.control),
                child: Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _answers.containsKey(widget.questions[i].id) ? c.accentWash : c.surface,
                    borderRadius: BorderRadius.circular(Radii.control),
                    border: Border.all(color: i == _index ? c.accent : c.line, width: i == _index ? 1.5 : 1),
                  ),
                  child: Text('${i + 1}', style: Mono.of(context, size: 12.5, color: c.ink)),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _results(BuildContext context, TestAttempt r) {
    final c = StudyColors.of(context);
    final t = Theme.of(context).textTheme;
    final good = r.fraction >= 0.7;
    return StudyPage(
      children: [
        Container(
          padding: const EdgeInsets.all(Gap.section),
          decoration: BoxDecoration(
            color: good ? c.successWash : c.accentWash,
            borderRadius: BorderRadius.circular(Radii.panel + 4),
          ),
          child: Column(
            children: [
              Text('${r.percent}%', style: Mono.of(context, size: 48, weight: FontWeight.w700, color: good ? c.success : c.accent)),
              const SizedBox(height: Gap.hair),
              Text('${r.score} of ${r.total} correct in ${clockLabel(r.secondsTaken)}', style: t.titleMedium),
              const SizedBox(height: Gap.hair),
              Text(good ? 'Well done. Keep it fresh with Smart study.' : 'Review the answers below, then try again.',
                  style: t.bodyMedium, textAlign: TextAlign.center),
              const SizedBox(height: Gap.page),
              Wrap(
                spacing: Gap.tight,
                runSpacing: Gap.tight,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(onPressed: _again, icon: const Icon(Icons.replay), label: const Text('Take it again')),
                  OutlinedButton(onPressed: () => Navigator.of(context).maybePop(), child: const Text('Back to the kit')),
                ],
              ),
            ],
          ),
        ),
        const SectionLabel('Answers'),
        for (var i = 0; i < widget.questions.length; i++)
          _Review(number: i + 1, question: widget.questions[i], chosen: r.answers[widget.questions[i].id]),
      ],
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({required this.letter, required this.text, required this.selected, required this.onTap});
  final String letter, text;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    final t = Theme.of(context).textTheme;
    return Material(
      color: selected ? c.accentWash : c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.control + 2),
        side: BorderSide(color: selected ? c.accent : c.line, width: selected ? 1.5 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.snug, vertical: Gap.row),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? c.accent : c.sunken,
                  shape: BoxShape.circle,
                ),
                child: Text(letter,
                    style: Mono.of(context, size: 12.5, weight: FontWeight.w600, color: selected ? c.onAccent : c.inkSoft)),
              ),
              const SizedBox(width: Gap.snug),
              Expanded(child: Text(text, style: t.bodyLarge)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Review extends StatelessWidget {
  const _Review({required this.number, required this.question, required this.chosen});
  final int number;
  final QuizQuestion question;
  final int? chosen;

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    final t = Theme.of(context).textTheme;
    final right = chosen == question.correctIndex;
    return Container(
      margin: const EdgeInsets.only(bottom: Gap.snug),
      padding: const EdgeInsets.all(Gap.page - 4),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.panel),
        border: Border(left: BorderSide(color: right ? c.success : c.danger, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(right ? Icons.check_circle_outline : Icons.cancel_outlined, size: 18, color: right ? c.success : c.danger),
              const SizedBox(width: Gap.hair + 2),
              Text(right ? 'Question $number: right' : chosen == null ? 'Question $number: not answered' : 'Question $number: wrong',
                  style: Mono.of(context, size: 12, weight: FontWeight.w600, color: right ? c.success : c.danger)),
            ],
          ),
          const SizedBox(height: Gap.tight),
          Text(question.prompt, style: t.titleMedium),
          const SizedBox(height: Gap.tight),
          if (!right && chosen != null && chosen! < question.options.length)
            Text('Your answer: ${question.options[chosen!]}', style: t.bodyMedium?.copyWith(color: c.danger)),
          Text('Right answer: ${question.options[question.correctIndex]}',
              style: t.bodyMedium?.copyWith(color: c.success, fontWeight: FontWeight.w600)),
          if ((question.explanation ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: Gap.hair + 2),
            Text(question.explanation!, style: t.bodyMedium),
          ],
        ],
      ),
    );
  }
}
