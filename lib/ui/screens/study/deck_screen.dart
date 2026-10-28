import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/study.dart';
import '../../../state/study_providers.dart';
import '../../widgets/study_widgets.dart';
import 'editor_sheets.dart';

/// A flashcard deck: its cards, and the way into study mode.
class DeckScreen extends ConsumerStatefulWidget {
  const DeckScreen({super.key, required this.deckId});
  final String deckId;

  @override
  ConsumerState<DeckScreen> createState() => _DeckScreenState();
}

class _DeckScreenState extends ConsumerState<DeckScreen> {
  String? _error;

  String get _id => widget.deckId;

  void _refresh(Deck deck) => refreshStudy(ref, deckId: deck.id, noteId: deck.noteId);

  Future<void> _rename(Deck deck) async {
    final title = await askForTitle(context,
        heading: 'Rename deck', confirmLabel: 'Save', initial: deck.title, maxLength: StudyLimits.deckTitle);
    if (title == null) return;
    await _attempt(() => studyRepo.renameDeck(deck.id, title), deck);
  }

  Future<void> _delete(Deck deck) async {
    final ok = await confirmDelete(context, what: 'this deck', consequence: 'All of its cards are deleted too.');
    if (!ok) return;
    await _attempt(() => studyRepo.deleteDeck(deck.id), deck);
    if (mounted && _error == null) context.pop();
  }

  Future<void> _attempt(Future<void> Function() action, Deck deck) async {
    try {
      await action();
      if (!mounted) return;
      setState(() => _error = null);
      _refresh(deck);
    } on Failure catch (f) {
      if (mounted) setState(() => _error = f.message);
    }
  }

  Future<void> _addCard(Deck deck, int nextPosition) => editFlashcard(context, onSave: (front, back) async {
        await studyRepo.addCard(deck.id, front: front, back: back, position: nextPosition);
        _refresh(deck);
      });

  Future<void> _editCard(Deck deck, Flashcard card) => editFlashcard(context, card: card, onSave: (front, back) async {
        await studyRepo.updateCard(card.id, front: front, back: back);
        _refresh(deck);
      });

  Future<void> _deleteCard(Deck deck, Flashcard card) async {
    final ok = await confirmDelete(context, what: 'this card');
    if (!ok) return;
    await _attempt(() => studyRepo.deleteCard(card.id), deck);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(deckProvider(_id));
    final deck = async.valueOrNull;

    return StudyScope(
      child: Builder(builder: (context) {
        return Scaffold(
          appBar: StudyTopBar(
            title: deck?.title ?? 'Flashcards',
            actions: [
              if (deck != null)
                PopupMenuButton<String>(
                  tooltip: 'More',
                  onSelected: (v) => v == 'rename' ? _rename(deck) : _delete(deck),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'rename', child: Text('Rename deck')),
                    PopupMenuItem(value: 'delete', child: Text('Delete deck')),
                  ],
                ),
            ],
          ),
          body: StudyPage(
            onRefresh: () async {
              refreshStudy(ref, deckId: _id);
              try {
                await ref.read(deckProvider(_id).future);
              } catch (_) {
                // Shown by the error state below.
              }
            },
            children: [
              if (_error != null) ...[
                InlineNotice(_error!, error: true, onClose: () => setState(() => _error = null)),
                const SizedBox(height: Gap.page),
              ],
              StudyAsync<Deck?>(
                value: async,
                onRetry: () => ref.invalidate(deckProvider(_id)),
                skeleton: const Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Bone(width: 220, height: 22),
                    SizedBox(height: Gap.snug),
                    Bone(width: 120, height: 11),
                    SizedBox(height: Gap.section),
                    RowsSkeleton(rows: 4),
                  ],
                ),
                isEmpty: (d) => d == null,
                empty: const StudyEmptyState('This deck no longer exists. It may have been deleted.'),
                data: (d) {
                  final deck = d!;
                  return _DeckBody(
                    deck: deck,
                    onAdd: (next) => _addCard(deck, next),
                    onEdit: (card) => _editCard(deck, card),
                    onDelete: (card) => _deleteCard(deck, card),
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

class _DeckBody extends ConsumerWidget {
  const _DeckBody({required this.deck, required this.onAdd, required this.onEdit, required this.onDelete});
  final Deck deck;
  final void Function(int nextPosition) onAdd;
  final void Function(Flashcard card) onEdit;
  final void Function(Flashcard card) onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final cards = ref.watch(cardsProvider(deck.id));
    final list = cards.valueOrNull ?? const <Flashcard>[];
    final next = list.isEmpty ? 0 : list.map((c) => c.position).reduce((a, b) => a > b ? a : b) + 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(deck.title, style: t.headlineSmall),
        const SizedBox(height: Gap.tight),
        Wrap(
          spacing: Gap.tight,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (deck.source == StudySource.ai) const Tag.ai(),
            Text('${list.length} ${list.length == 1 ? 'card' : 'cards'}', style: Mono.of(context, size: 12)),
            _SourceNote(noteId: deck.noteId),
          ],
        ),
        const SizedBox(height: Gap.page),
        Wrap(
          spacing: Gap.tight,
          runSpacing: Gap.tight,
          children: [
            FilledButton.icon(
              onPressed: list.isEmpty ? null : () => context.push('/study/deck/${deck.id}/study'),
              icon: const Icon(Icons.play_arrow_rounded, size: 20),
              label: const Text('Study this deck'),
            ),
            OutlinedButton.icon(
              onPressed: () => onAdd(next),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add a card'),
            ),
          ],
        ),
        const SectionLabel('Cards'),
        StudyAsync<List<Flashcard>>(
          value: cards,
          onRetry: () => ref.invalidate(cardsProvider(deck.id)),
          skeleton: const RowsSkeleton(rows: 4),
          isEmpty: (v) => v.isEmpty,
          empty: const StudyEmptyState(
            'This deck has no cards yet. Add a card with a question on the front and the answer on the back.',
            compact: true,
          ),
          data: (items) => RowGroup(children: [
            for (var i = 0; i < items.length; i++)
              StudyRow(
                title: items[i].front,
                detail: items[i].back,
                detailLines: 3,
                meta: '${i + 1}',
                onTap: () => onEdit(items[i]),
                trailing: IconButton(
                  tooltip: 'Delete card',
                  icon: const Icon(Icons.delete_outline, size: 19),
                  onPressed: () => onDelete(items[i]),
                ),
              ),
          ]),
        ),
      ],
    );
  }
}

/// "From: <note title>", or a plain line when that note was deleted.
class _SourceNote extends ConsumerWidget {
  const _SourceNote({required this.noteId});
  final String? noteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = noteId;
    final style = Theme.of(context).textTheme.bodySmall;
    if (id == null) return Text('Not linked to a note', style: style);
    final note = ref.watch(noteProvider(id)).valueOrNull;
    if (note == null) return const SizedBox.shrink();
    return InkWell(
      onTap: () => context.push('/study/note/$id'),
      child: Text('From: ${note.title}',
          style: style?.copyWith(decoration: TextDecoration.underline)),
    );
  }
}
