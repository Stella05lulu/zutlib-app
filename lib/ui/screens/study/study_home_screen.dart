import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/failure.dart';
import '../../../core/theme.dart' show kNavClearance;
import '../../../core/theme/app_theme.dart';
import '../../../models/study.dart';
import '../../../state/study_providers.dart';
import '../../widgets/study_widgets.dart';
import 'new_note_sheet.dart';

/// The Study tab: the student's notes, flashcard decks and quizzes, one
/// list at a time. Everything here is private to the signed-in student;
/// the database returns nobody else's rows.
class StudyHomeScreen extends ConsumerWidget {
  const StudyHomeScreen({super.key});

  static const _tabs = ['Notes', 'Flashcards', 'Quizzes'];

  Future<void> _newDeck(BuildContext context, WidgetRef ref) async {
    final title = await askForTitle(context,
        heading: 'New flashcard deck', confirmLabel: 'Create', maxLength: StudyLimits.deckTitle);
    if (title == null) return;
    try {
      final deck = await studyRepo.createDeck(title);
      if (!context.mounted) return;
      refreshStudy(ref);
      unawaited(context.push('/study/deck/${deck.id}'));
    } on Failure catch (f) {
      if (context.mounted) ref.read(_homeErrorProvider.notifier).state = f.message;
    }
  }

  Future<void> _newQuiz(BuildContext context, WidgetRef ref) async {
    final title = await askForTitle(context,
        heading: 'New quiz', confirmLabel: 'Create', maxLength: StudyLimits.quizTitle);
    if (title == null) return;
    try {
      final quiz = await studyRepo.createQuiz(title);
      if (!context.mounted) return;
      refreshStudy(ref);
      unawaited(context.push('/study/quiz/${quiz.id}'));
    } on Failure catch (f) {
      if (context.mounted) ref.read(_homeErrorProvider.notifier).state = f.message;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(studyTabProvider);
    final error = ref.watch(_homeErrorProvider);

    Future<void> refresh() async {
      refreshStudy(ref);
      try {
        await Future.wait<Object?>([
          ref.read(notesProvider.future),
          ref.read(decksProvider.future),
          ref.read(quizzesProvider.future),
        ]);
      } catch (_) {
        // Each list shows its own error state; nothing more to do here.
      }
    }

    final newAction = switch (tab) {
      0 => FilledButton.icon(
          onPressed: () => showNewNoteSheet(context),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('New note'),
        ),
      1 => FilledButton.icon(
          onPressed: () => _newDeck(context, ref),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('New deck'),
        ),
      _ => FilledButton.icon(
          onPressed: () => _newQuiz(context, ref),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('New quiz'),
        ),
    };

    return StudyScope(
      child: Builder(builder: (context) {
        final c = StudyColors.of(context);
        final t = Theme.of(context).textTheme;
        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: StudyPage(
              bottom: kNavClearance,
              onRefresh: refresh,
              children: [
                const SizedBox(height: Gap.tight),
                Text('Study', style: t.headlineSmall),
                const SizedBox(height: Gap.hair + 2),
                Text('Your notes, flashcards and quizzes. Only you can see them.',
                    style: t.bodyMedium),
                const SizedBox(height: Gap.page + 4),
                Container(
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
                  child: Row(
                    children: [
                      for (var i = 0; i < _tabs.length; i++)
                        _TabLabel(
                          label: _tabs[i],
                          selected: tab == i,
                          onTap: () => ref.read(studyTabProvider.notifier).state = i,
                        ),
                      const Spacer(),
                    ],
                  ),
                ),
                const SizedBox(height: Gap.page),
                Align(alignment: Alignment.centerLeft, child: newAction),
                if (error != null) ...[
                  const SizedBox(height: Gap.snug),
                  InlineNotice(error,
                      error: true,
                      onClose: () => ref.read(_homeErrorProvider.notifier).state = null),
                ],
                const SizedBox(height: Gap.page),
                switch (tab) {
                  0 => const _NotesList(),
                  1 => const _DecksList(),
                  _ => const _QuizzesList(),
                },
              ],
            ),
          ),
        );
      }),
    );
  }
}

/// A message from the last failed create on this screen, shown inline.
final _homeErrorProvider = StateProvider.autoDispose<String?>((_) => null);

class _TabLabel extends StatelessWidget {
  const _TabLabel({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(2, Gap.snug, 2, Gap.snug - 2),
          margin: const EdgeInsets.only(right: Gap.page + 2),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: selected ? c.accent : c.canvas, width: 2),
            ),
          ),
          child: Text(label,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: selected ? c.ink : c.inkFaint,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  )),
        ),
      ),
    );
  }
}

class _NotesList extends ConsumerWidget {
  const _NotesList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StudyAsync<List<Note>>(
      value: ref.watch(notesProvider),
      onRetry: () => ref.invalidate(notesProvider),
      skeleton: const RowsSkeleton(rows: 5),
      isEmpty: (v) => v.isEmpty,
      empty: StudyEmptyState(
        'You have no notes yet. Upload a PDF, pick one from the library, or type a note, '
        'then let AI summarise it, make flashcards and write a quiz.',
        action: OutlinedButton(
          onPressed: () => showNewNoteSheet(context),
          child: const Text('Start your first note'),
        ),
      ),
      data: (notes) => RowGroup(children: [
        for (final n in notes)
          StudyRow(
            title: n.title,
            detail: n.preview,
            meta: 'Edited ${studyDate.format(n.updatedAt)}',
            tags: [
              if (n.hasPdf) const Tag('PDF', sky: true),
              if (n.courseCode != null) Tag(n.courseCode!),
            ],
            onTap: () => context.push('/study/note/${n.id}'),
          ),
      ]),
    );
  }
}

class _DecksList extends ConsumerWidget {
  const _DecksList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StudyAsync<List<Deck>>(
      value: ref.watch(decksProvider),
      onRetry: () => ref.invalidate(decksProvider),
      skeleton: const RowsSkeleton(rows: 4, detail: false),
      isEmpty: (v) => v.isEmpty,
      empty: const StudyEmptyState(
        'You have no flashcard decks yet. Make one here, or open a note and let AI draft the cards.',
      ),
      data: (decks) => RowGroup(children: [
        for (final d in decks)
          StudyRow(
            title: d.title,
            meta: '${d.cardCount} ${d.cardCount == 1 ? 'card' : 'cards'}',
            tags: [if (d.source == StudySource.ai) const Tag.ai()],
            onTap: () => context.push('/study/deck/${d.id}'),
          ),
      ]),
    );
  }
}

class _QuizzesList extends ConsumerWidget {
  const _QuizzesList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StudyAsync<List<Quiz>>(
      value: ref.watch(quizzesProvider),
      onRetry: () => ref.invalidate(quizzesProvider),
      skeleton: const RowsSkeleton(rows: 4, detail: false),
      isEmpty: (v) => v.isEmpty,
      empty: const StudyEmptyState(
        'You have no quizzes yet. Write one here, or open a note and let AI draft the questions.',
      ),
      data: (quizzes) => RowGroup(children: [
        for (final q in quizzes)
          StudyRow(
            title: q.title,
            meta: [
              '${q.questionCount} ${q.questionCount == 1 ? 'question' : 'questions'}',
              if (q.latest != null) 'last score ${q.latest!.label}',
            ].join('  /  '),
            tags: [if (q.source == StudySource.ai) const Tag.ai()],
            onTap: () => context.push('/study/quiz/${q.id}'),
          ),
      ]),
    );
  }
}
