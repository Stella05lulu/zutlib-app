import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/study.dart';
import '../../../state/study_providers.dart';
import '../../widgets/study_widgets.dart';
import '../shared/pdf_viewer_screen.dart';
import 'ai_panel.dart';
import 'editor_sheets.dart';

/// One note: its text, AI help, its summaries, and the decks and quizzes
/// made from it.
class NoteDetailScreen extends ConsumerStatefulWidget {
  const NoteDetailScreen({super.key, required this.noteId});
  final String noteId;

  @override
  ConsumerState<NoteDetailScreen> createState() => _NoteDetailScreenState();
}

class _NoteDetailScreenState extends ConsumerState<NoteDetailScreen> {
  String? _error;

  String get _id => widget.noteId;

  Future<void> _delete(Note note) async {
    final ok = await confirmDelete(context,
        what: 'this note',
        consequence: 'Its summaries are deleted with it. Flashcard decks and quizzes made '
            'from it are kept, so your cards and scores are not lost.');
    if (!ok) return;
    try {
      await studyRepo.deleteNote(note);
      if (!mounted) return;
      refreshStudy(ref);
      context.pop();
    } on Failure catch (f) {
      if (mounted) setState(() => _error = f.message);
    }
  }

  Future<void> _newDeck(Note note) async {
    final title = await askForTitle(context,
        heading: 'New deck from this note',
        confirmLabel: 'Create',
        initial: '${note.title} flashcards',
        maxLength: StudyLimits.deckTitle);
    if (title == null) return;
    try {
      final deck = await studyRepo.createDeck(title, noteId: note.id);
      if (!mounted) return;
      refreshStudy(ref, noteId: note.id);
      unawaited(context.push('/study/deck/${deck.id}'));
    } on Failure catch (f) {
      if (mounted) setState(() => _error = f.message);
    }
  }

  Future<void> _newQuiz(Note note) async {
    final title = await askForTitle(context,
        heading: 'New quiz from this note',
        confirmLabel: 'Create',
        initial: '${note.title} quiz',
        maxLength: StudyLimits.quizTitle);
    if (title == null) return;
    try {
      final quiz = await studyRepo.createQuiz(title, noteId: note.id);
      if (!mounted) return;
      refreshStudy(ref, noteId: note.id);
      unawaited(context.push('/study/quiz/${quiz.id}'));
    } on Failure catch (f) {
      if (mounted) setState(() => _error = f.message);
    }
  }

  Future<void> _refresh() async {
    refreshStudy(ref, noteId: _id);
    ref.invalidate(aiStatusProvider);
    try {
      await ref.read(noteProvider(_id).future);
    } catch (_) {
      // The error state on screen already says what went wrong.
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(noteProvider(_id));
    final note = async.valueOrNull;

    return StudyScope(
      child: Builder(builder: (context) {
        return Scaffold(
          appBar: StudyTopBar(
            title: note?.title ?? 'Note',
            actions: [
              if (note != null) ...[
                IconButton(
                  tooltip: 'Edit note',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => context.push('/study/note/${note.id}/edit'),
                ),
                IconButton(
                  tooltip: 'Delete note',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _delete(note),
                ),
              ],
            ],
          ),
          body: StudyPage(
            onRefresh: _refresh,
            children: [
              if (_error != null) ...[
                InlineNotice(_error!, error: true, onClose: () => setState(() => _error = null)),
                const SizedBox(height: Gap.page),
              ],
              StudyAsync<Note?>(
                value: async,
                onRetry: () => ref.invalidate(noteProvider(_id)),
                skeleton: const TextSkeleton(),
                isEmpty: (n) => n == null,
                empty: const StudyEmptyState('This note no longer exists. It may have been deleted.'),
                data: (n) {
                  final note = n!;
                  return _NoteBody(
                    note: note,
                    onNewDeck: () => _newDeck(note),
                    onNewQuiz: () => _newQuiz(note),
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

class _NoteBody extends ConsumerWidget {
  const _NoteBody({required this.note, required this.onNewDeck, required this.onNewQuiz});
  final Note note;
  final VoidCallback onNewDeck;
  final VoidCallback onNewQuiz;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(note.title, style: t.headlineSmall),
        const SizedBox(height: Gap.tight),
        Wrap(
          spacing: Gap.tight,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (note.courseCode != null) Tag(note.courseCode!),
            Text('Edited ${studyDateTime.format(note.updatedAt)}', style: Mono.of(context, size: 12)),
            if (note.body.isNotEmpty)
              Text('${note.body.length} characters', style: Mono.of(context, size: 12)),
          ],
        ),
        const SizedBox(height: Gap.page),
        if (note.hasPdf || (note.resourceId == null && note.filePath == null && note.body.trim().isEmpty))
          _PdfSource(note: note),
        if (note.body.trim().isNotEmpty) SelectableText(note.body, style: t.bodyLarge),
        const SizedBox(height: Gap.section),
        AiPanel(note: note),
        _SummariesSection(note: note),
        _DecksSection(note: note, onNew: onNewDeck),
        _QuizzesSection(note: note, onNew: onNewQuiz),
      ],
    );
  }
}

class _SummariesSection extends ConsumerWidget {
  const _SummariesSection({required this.note});
  final Note note;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> add() async {
      await editSummary(context, onSave: (body) async {
        await studyRepo.addSummary(note.id, body);
        refreshStudy(ref, noteId: note.id);
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel('Summaries',
            action: TextButton.icon(
              onPressed: add,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Write one'),
            )),
        StudyAsync<List<Summary>>(
          value: ref.watch(summariesProvider(note.id)),
          onRetry: () => ref.invalidate(summariesProvider(note.id)),
          skeleton: const RowsSkeleton(rows: 1),
          isEmpty: (v) => v.isEmpty,
          empty: const StudyEmptyState(
            'No summaries yet. Write your own, or use Summarise above.',
            compact: true,
          ),
          data: (items) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final s in items) ...[
                _SummaryPanel(summary: s, noteId: note.id),
                const SizedBox(height: Gap.tight + 2),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SummaryPanel extends ConsumerWidget {
  const _SummaryPanel({required this.summary, required this.noteId});
  final Summary summary;
  final String noteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = StudyColors.of(context);
    Future<void> edit() async {
      await editSummary(context, initial: summary.body, onSave: (body) async {
        await studyRepo.updateSummary(summary.id, body);
        refreshStudy(ref, noteId: noteId);
      });
    }

    Future<void> delete() async {
      final ok = await confirmDelete(context, what: 'this summary');
      if (!ok) return;
      try {
        await studyRepo.deleteSummary(summary.id);
        refreshStudy(ref, noteId: noteId);
      } on Failure catch (f) {
        if (context.mounted) {
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              content: Text(f.message),
              actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
            ),
          );
        }
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.panel),
        border: Border.all(color: c.line),
      ),
      padding: const EdgeInsets.fromLTRB(Gap.page - 4, Gap.snug, Gap.hair, Gap.page - 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (summary.source == StudySource.ai) ...[const Tag.ai(), const SizedBox(width: Gap.tight)],
              Text(studyDateTime.format(summary.createdAt), style: Mono.of(context, size: 12)),
              const Spacer(),
              IconButton(
                tooltip: 'Edit summary',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.edit_outlined, size: 19),
                onPressed: edit,
              ),
              IconButton(
                tooltip: 'Delete summary',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.delete_outline, size: 19),
                onPressed: delete,
              ),
            ],
          ),
          const SizedBox(height: Gap.hair),
          Padding(
            padding: const EdgeInsets.only(right: Gap.snug),
            child: SelectableText(summary.body,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontSize: 15)),
          ),
        ],
      ),
    );
  }
}

class _DecksSection extends ConsumerWidget {
  const _DecksSection({required this.note, required this.onNew});
  final Note note;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel('Flashcard decks from this note',
              action: TextButton.icon(
                onPressed: onNew,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New deck'),
              )),
          StudyAsync<List<Deck>>(
            value: ref.watch(noteDecksProvider(note.id)),
            onRetry: () => ref.invalidate(noteDecksProvider(note.id)),
            skeleton: const RowsSkeleton(rows: 1, detail: false),
            isEmpty: (v) => v.isEmpty,
            empty: const StudyEmptyState('No decks from this note yet.', compact: true),
            data: (decks) => RowGroup(children: [
              for (final d in decks)
                StudyRow(
                  title: d.title,
                  meta: '${d.cardCount} ${d.cardCount == 1 ? 'card' : 'cards'}',
                  tags: [if (d.source == StudySource.ai) const Tag.ai()],
                  onTap: () => context.push('/study/deck/${d.id}'),
                ),
            ]),
          ),
        ],
      );
}

class _QuizzesSection extends ConsumerWidget {
  const _QuizzesSection({required this.note, required this.onNew});
  final Note note;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel('Quizzes from this note',
              action: TextButton.icon(
                onPressed: onNew,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New quiz'),
              )),
          StudyAsync<List<Quiz>>(
            value: ref.watch(noteQuizzesProvider(note.id)),
            onRetry: () => ref.invalidate(noteQuizzesProvider(note.id)),
            skeleton: const RowsSkeleton(rows: 1, detail: false),
            isEmpty: (v) => v.isEmpty,
            empty: const StudyEmptyState('No quizzes from this note yet.', compact: true),
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
          ),
        ],
      );
}

/// The PDF a note studies: its name, and a button to open it (a link that
/// expires after five minutes).
class _PdfSource extends StatefulWidget {
  const _PdfSource({required this.note});
  final Note note;
  @override
  State<_PdfSource> createState() => _PdfSourceState();
}

class _PdfSourceState extends State<_PdfSource> {
  String? _error;

  Future<void> _open() async {
    final error = await openPdf(context,
        title: widget.note.pdfLabel ?? widget.note.title, loadUrl: () => studyRepo.pdfUrl(widget.note));
    if (mounted) setState(() => _error = error);
  }

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    final t = Theme.of(context).textTheme;
    final n = widget.note;
    if (!n.hasPdf) {
      return Padding(
        padding: const EdgeInsets.only(bottom: Gap.page),
        child: const InlineNotice('The library PDF this note was made from has been removed, so AI has nothing to read. '
            'Add some text to keep using it.'),
      );
    }
    return Container(
      margin: const EdgeInsets.only(bottom: Gap.page),
      padding: const EdgeInsets.fromLTRB(Gap.page - 4, Gap.snug, Gap.snug, Gap.snug),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.panel),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.picture_as_pdf_outlined, color: c.inkSoft, size: 22),
              const SizedBox(width: Gap.snug),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(n.pdfLabel ?? 'PDF', style: t.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                    Text(n.hasUpload ? 'Your uploaded PDF. Only you can see it.' : 'From the ZutLib library.',
                        style: t.bodySmall),
                  ],
                ),
              ),
              TextButton(onPressed: _open, child: const Text('Open')),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: Gap.tight),
            InlineNotice(_error!, error: true),
          ],
          if (n.body.trim().isEmpty) ...[
            const SizedBox(height: Gap.tight),
            Text('AI help below reads this PDF. You can also add your own text with Edit.', style: t.bodySmall),
          ],
        ],
      ),
    );
  }
}
