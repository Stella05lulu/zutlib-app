import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/study.dart';
import '../../../state/study_providers.dart';
import '../../widgets/study_widgets.dart';
import 'editor_sheets.dart';

/// A quiz: its questions (with the correct answer marked), the way in to
/// take it, and past scores.
class QuizScreen extends ConsumerStatefulWidget {
  const QuizScreen({super.key, required this.quizId});
  final String quizId;

  @override
  ConsumerState<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends ConsumerState<QuizScreen> {
  String? _error;

  String get _id => widget.quizId;

  void _refresh(Quiz quiz) => refreshStudy(ref, quizId: quiz.id, noteId: quiz.noteId);

  Future<void> _attempt(Future<void> Function() action, Quiz quiz) async {
    try {
      await action();
      if (!mounted) return;
      setState(() => _error = null);
      _refresh(quiz);
    } on Failure catch (f) {
      if (mounted) setState(() => _error = f.message);
    }
  }

  Future<void> _rename(Quiz quiz) async {
    final title = await askForTitle(context,
        heading: 'Rename quiz', confirmLabel: 'Save', initial: quiz.title, maxLength: StudyLimits.quizTitle);
    if (title == null) return;
    await _attempt(() => studyRepo.renameQuiz(quiz.id, title), quiz);
  }

  Future<void> _delete(Quiz quiz) async {
    final ok = await confirmDelete(context,
        what: 'this quiz', consequence: 'Its questions and every score you got on it are deleted too.');
    if (!ok) return;
    await _attempt(() => studyRepo.deleteQuiz(quiz.id), quiz);
    if (mounted && _error == null) context.pop();
  }

  Future<void> _addQuestion(Quiz quiz, int nextPosition) => editQuestion(context, onSave: (d) async {
        await studyRepo.addQuestion(quiz.id,
            prompt: d.prompt,
            options: d.options,
            correctIndex: d.correctIndex,
            explanation: d.explanation,
            position: nextPosition);
        _refresh(quiz);
      });

  Future<void> _editQuestion(Quiz quiz, QuizQuestion q) => editQuestion(context, question: q, onSave: (d) async {
        await studyRepo.updateQuestion(q.id,
            prompt: d.prompt, options: d.options, correctIndex: d.correctIndex, explanation: d.explanation);
        _refresh(quiz);
      });

  Future<void> _deleteQuestion(Quiz quiz, QuizQuestion q) async {
    final ok = await confirmDelete(context, what: 'this question');
    if (!ok) return;
    await _attempt(() => studyRepo.deleteQuestion(q.id), quiz);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(quizProvider(_id));
    final quiz = async.valueOrNull;

    return StudyScope(
      child: Builder(builder: (context) {
        return Scaffold(
          appBar: StudyTopBar(
            title: quiz?.title ?? 'Quiz',
            actions: [
              if (quiz != null)
                PopupMenuButton<String>(
                  tooltip: 'More',
                  onSelected: (v) => v == 'rename' ? _rename(quiz) : _delete(quiz),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'rename', child: Text('Rename quiz')),
                    PopupMenuItem(value: 'delete', child: Text('Delete quiz')),
                  ],
                ),
            ],
          ),
          body: StudyPage(
            onRefresh: () async {
              refreshStudy(ref, quizId: _id);
              try {
                await ref.read(quizProvider(_id).future);
              } catch (_) {
                // Shown by the error state below.
              }
            },
            children: [
              if (_error != null) ...[
                InlineNotice(_error!, error: true, onClose: () => setState(() => _error = null)),
                const SizedBox(height: Gap.page),
              ],
              StudyAsync<Quiz?>(
                value: async,
                onRetry: () => ref.invalidate(quizProvider(_id)),
                skeleton: const Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Bone(width: 220, height: 22),
                    SizedBox(height: Gap.snug),
                    Bone(width: 140, height: 11),
                    SizedBox(height: Gap.section),
                    RowsSkeleton(rows: 3),
                  ],
                ),
                isEmpty: (q) => q == null,
                empty: const StudyEmptyState('This quiz no longer exists. It may have been deleted.'),
                data: (q) {
                  final quiz = q!;
                  return _QuizBody(
                    quiz: quiz,
                    onAdd: (next) => _addQuestion(quiz, next),
                    onEdit: (question) => _editQuestion(quiz, question),
                    onDelete: (question) => _deleteQuestion(quiz, question),
                  );
                },
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _QuizBody extends ConsumerWidget {
  const _QuizBody({required this.quiz, required this.onAdd, required this.onEdit, required this.onDelete});
  final Quiz quiz;
  final void Function(int nextPosition) onAdd;
  final void Function(QuizQuestion q) onEdit;
  final void Function(QuizQuestion q) onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final questions = ref.watch(questionsProvider(quiz.id));
    final list = questions.valueOrNull ?? const <QuizQuestion>[];
    final next = list.isEmpty ? 0 : list.map((q) => q.position).reduce((a, b) => a > b ? a : b) + 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(quiz.title, style: t.headlineSmall),
        const SizedBox(height: Gap.tight),
        Wrap(
          spacing: Gap.tight,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (quiz.source == StudySource.ai) const Tag.ai(),
            Text('${list.length} ${list.length == 1 ? 'question' : 'questions'}', style: Mono.of(context, size: 12)),
            if (quiz.noteId == null) Text('Not linked to a note', style: t.bodySmall),
          ],
        ),
        const SizedBox(height: Gap.page),
        Wrap(
          spacing: Gap.tight,
          runSpacing: Gap.tight,
          children: [
            FilledButton.icon(
              onPressed: list.isEmpty ? null : () => context.push('/study/quiz/${quiz.id}/take'),
              icon: const Icon(Icons.play_arrow_rounded, size: 20),
              label: const Text('Take the quiz'),
            ),
            OutlinedButton.icon(
              onPressed: () => onAdd(next),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add a question'),
            ),
          ],
        ),
        if (quiz.scores.isNotEmpty) ...[
          const SectionLabel('Your scores'),
          RowGroup(children: [
            for (final s in quiz.scores.take(5))
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Gap.page - 4, vertical: Gap.snug),
                child: Row(
                  children: [
                    Text(s.label, style: Mono.of(context, size: 14, weight: FontWeight.w600)),
                    const SizedBox(width: Gap.snug),
                    Text('${(100 * s.score / s.total).round()}%', style: Mono.of(context, size: 12)),
                    const Spacer(),
                    Text(studyDateTime.format(s.at), style: Mono.of(context, size: 12)),
                  ],
                ),
              ),
          ]),
        ],
        const SectionLabel('Questions'),
        StudyAsync<List<QuizQuestion>>(
          value: questions,
          onRetry: () => ref.invalidate(questionsProvider(quiz.id)),
          skeleton: const RowsSkeleton(rows: 3),
          isEmpty: (v) => v.isEmpty,
          empty: const StudyEmptyState(
            'This quiz has no questions yet. Add a question with two to six options and mark the correct one.',
            compact: true,
          ),
          data: (items) => RowGroup(children: [
            for (var i = 0; i < items.length; i++)
              _QuestionRow(
                number: i + 1,
                question: items[i],
                onTap: () => onEdit(items[i]),
                onDelete: () => onDelete(items[i]),
              ),
          ]),
        ),
      ],
    );
  }
}

class _QuestionRow extends StatelessWidget {
  const _QuestionRow({required this.number, required this.question, required this.onTap, required this.onDelete});
  final int number;
  final QuizQuestion question;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    final t = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.page - 4, Gap.row, Gap.hair, Gap.row),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 28, child: Text('$number', style: Mono.of(context, size: 13))),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(question.prompt, style: t.titleMedium),
                  const SizedBox(height: Gap.tight),
                  for (var i = 0; i < question.options.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Gap.hair),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 22,
                            child: Text(String.fromCharCode(65 + i),
                                style: Mono.of(context, size: 12,
                                    color: i == question.correctIndex ? c.sky : c.inkFaint)),
                          ),
                          Expanded(
                            child: Text(question.options[i],
                                style: t.bodyMedium?.copyWith(
                                  color: i == question.correctIndex ? c.ink : c.inkSoft,
                                  fontWeight: i == question.correctIndex ? FontWeight.w600 : FontWeight.w400,
                                )),
                          ),
                          if (i == question.correctIndex) const Tag('ANSWER', sky: true),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Delete question',
              icon: const Icon(Icons.delete_outline, size: 19),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}
