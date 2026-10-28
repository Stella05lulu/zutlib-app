import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/study.dart';
import '../../../state/study_providers.dart';
import '../../widgets/study_widgets.dart';

/// Taking a quiz: one question at a time, then the result.
///
/// The answers are sent to the database, which checks each one against
/// the stored correct option and saves the score. The result shown here is
/// the database's marking, not the phone's.
class QuizTakeScreen extends ConsumerWidget {
  const QuizTakeScreen({super.key, required this.quizId});
  final String quizId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quiz = ref.watch(quizProvider(quizId)).valueOrNull;
    final questions = ref.watch(questionsProvider(quizId));
    return StudyScope(
      child: Builder(builder: (context) {
        return Scaffold(
          appBar: StudyTopBar(title: quiz?.title ?? 'Quiz'),
          body: StudyPage(
            maxWidth: 640,
            children: [
              StudyAsync<List<QuizQuestion>>(
                value: questions,
                onRetry: () => ref.invalidate(questionsProvider(quizId)),
                skeleton: const QuestionSkeleton(),
                isEmpty: (v) => v.isEmpty,
                empty: StudyEmptyState(
                  'This quiz has no questions yet, so there is nothing to take.',
                  action: OutlinedButton(onPressed: () => context.pop(), child: const Text('Back to the quiz')),
                ),
                data: (list) => _Attempt(quizId: quizId, questions: list),
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _Attempt extends ConsumerStatefulWidget {
  const _Attempt({required this.quizId, required this.questions});
  final String quizId;
  final List<QuizQuestion> questions;

  @override
  ConsumerState<_Attempt> createState() => _AttemptState();
}

class _AttemptState extends ConsumerState<_Attempt> {
  final Map<String, int> _answers = {};
  int _index = 0;
  bool _submitting = false;
  String? _error;
  QuizAttempt? _result;

  List<QuizQuestion> get _qs => widget.questions;

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final attempt = await studyRepo.submitAttempt(widget.quizId, _answers);
      if (!mounted) return;
      refreshStudy(ref, quizId: widget.quizId);
      setState(() {
        _submitting = false;
        _result = attempt;
      });
    } on Failure catch (f) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = f.message;
      });
    }
  }

  void _retake() => setState(() {
        _answers.clear();
        _index = 0;
        _result = null;
        _error = null;
      });

  @override
  Widget build(BuildContext context) {
    final result = _result;
    if (result != null) return _Result(questions: _qs, attempt: result, onRetake: _retake);

    final c = StudyColors.of(context);
    final t = Theme.of(context).textTheme;
    final q = _qs[_index];
    final chosen = _answers[q.id];
    final last = _index == _qs.length - 1;
    final unanswered = _qs.where((x) => !_answers.containsKey(x.id)).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('Question ${_index + 1} of ${_qs.length}', style: Mono.of(context)),
            const Spacer(),
            Text('${_answers.length} answered', style: Mono.of(context, size: 12, color: c.inkFaint)),
          ],
        ),
        const SizedBox(height: Gap.tight),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(value: (_index + 1) / _qs.length, minHeight: 3),
        ),
        const SizedBox(height: Gap.section - 4),
        Text(q.prompt, style: t.titleLarge),
        const SizedBox(height: Gap.page),
        for (var i = 0; i < q.options.length; i++) ...[
          _OptionTile(
            letter: String.fromCharCode(65 + i),
            text: q.options[i],
            selected: chosen == i,
            onTap: _submitting ? null : () => setState(() => _answers[q.id] = i),
          ),
          const SizedBox(height: Gap.tight + 2),
        ],
        if (_error != null) ...[
          const SizedBox(height: Gap.tight),
          InlineNotice(_error!, error: true),
        ],
        const SizedBox(height: Gap.page),
        Row(
          children: [
            if (_index > 0)
              OutlinedButton(
                onPressed: _submitting ? null : () => setState(() => _index--),
                child: const Text('Back'),
              ),
            const Spacer(),
            if (!last)
              FilledButton(
                onPressed: () => setState(() => _index++),
                child: Text(chosen == null ? 'Skip' : 'Next'),
              )
            else
              FilledButton(
                onPressed: _submitting ? null : _submit,
                child: Text(_submitting ? 'Marking' : 'Finish and mark'),
              ),
          ],
        ),
        if (last && unanswered > 0) ...[
          const SizedBox(height: Gap.snug),
          Text(
            unanswered == 1
                ? 'One question has no answer. It will be marked wrong.'
                : '$unanswered questions have no answer. They will be marked wrong.',
            style: t.bodySmall,
          ),
        ],
      ],
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({required this.letter, required this.text, required this.selected, required this.onTap});
  final String letter;
  final String text;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? c.accentWash : c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.control),
          side: BorderSide(color: selected ? c.accent : c.line, width: selected ? 1.5 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.snug + 2, vertical: Gap.row),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 24,
                  child: Text(letter,
                      style: Mono.of(context, weight: FontWeight.w600, color: selected ? c.accent : c.inkFaint)),
                ),
                Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyLarge)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({required this.questions, required this.attempt, required this.onRetake});
  final List<QuizQuestion> questions;
  final QuizAttempt attempt;
  final VoidCallback onRetake;

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    final t = Theme.of(context).textTheme;
    final percent = (100 * attempt.score / attempt.total).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Your score', style: t.titleSmall),
        const SizedBox(height: Gap.hair),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text('${attempt.score}/${attempt.total}',
                style: Mono.of(context, size: 40, weight: FontWeight.w600, color: c.ink)),
            const SizedBox(width: Gap.snug),
            Text('$percent%', style: Mono.of(context, size: 16)),
          ],
        ),
        const SizedBox(height: Gap.tight),
        Text('Marked and saved by the database. Your score history is on the quiz page.',
            style: t.bodySmall),
        const SizedBox(height: Gap.page),
        Wrap(spacing: Gap.tight, runSpacing: Gap.tight, children: [
          FilledButton(onPressed: onRetake, child: const Text('Take it again')),
          OutlinedButton(onPressed: () => context.pop(), child: const Text('Back to the quiz')),
        ]),
        const SectionLabel('Answers'),
        RowGroup(children: [
          for (var i = 0; i < questions.length; i++) _Review(number: i + 1, q: questions[i], chosen: attempt.answers[questions[i].id]),
        ]),
      ],
    );
  }
}

class _Review extends StatelessWidget {
  const _Review({required this.number, required this.q, required this.chosen});
  final int number;
  final QuizQuestion q;
  final int? chosen;

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    final t = Theme.of(context).textTheme;
    final right = chosen == q.correctIndex;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.page - 4, Gap.row, Gap.page - 4, Gap.row + 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('$number', style: Mono.of(context, size: 12)),
              const SizedBox(width: Gap.tight),
              Text(right ? 'Correct' : (chosen == null ? 'Not answered' : 'Wrong'),
                  style: Mono.of(context, size: 12, weight: FontWeight.w600, color: right ? c.sky : c.accent)),
            ],
          ),
          const SizedBox(height: Gap.hair + 2),
          Text(q.prompt, style: t.titleMedium),
          const SizedBox(height: Gap.tight),
          if (!right && chosen != null && chosen! < q.options.length)
            Text('Your answer: ${q.options[chosen!]}', style: t.bodyMedium?.copyWith(color: c.accent)),
          Text('Correct answer: ${q.options[q.correctIndex]}', style: t.bodyMedium?.copyWith(color: c.ink)),
          if (q.explanation != null) ...[
            const SizedBox(height: Gap.hair + 2),
            Text(q.explanation!, style: t.bodySmall),
          ],
        ],
      ),
    );
  }
}
