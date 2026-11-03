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
import 'editor_sheets.dart';
import 'kit_widgets.dart';

/// The kit's flashcards in three views: the list of terms, the deck to
/// study (rate each card red, yellow or green), and the games.
class KitFlashcardsTab extends ConsumerStatefulWidget {
  const KitFlashcardsTab({super.key, required this.kit, required this.onChanged});
  final KitData kit;
  final VoidCallback onChanged;

  @override
  ConsumerState<KitFlashcardsTab> createState() => _KitFlashcardsTabState();
}

class _KitFlashcardsTabState extends ConsumerState<KitFlashcardsTab> {
  int _view = 1; // 0 list, 1 deck, 2 games
  String? _error;

  Future<Deck> _ensureDeck() async {
    final kit = widget.kit;
    return kit.deck ?? await studyRepo.createDeck(kit.note.title, noteId: kit.note.id);
  }

  Future<void> _addCard() => editFlashcard(context, onSave: (front, back) async {
        final deck = await _ensureDeck();
        await studyRepo.addCard(deck.id, front: front, back: back, position: widget.kit.cards.length);
        widget.onChanged();
      });

  Future<void> _editCard(Flashcard card) => editFlashcard(context, card: card, onSave: (front, back) async {
        await studyRepo.updateCard(card.id, front: front, back: back);
        widget.onChanged();
      });

  Future<void> _deleteCard(Flashcard card) async {
    final ok = await confirmDelete(context, what: 'this card');
    if (!ok) return;
    try {
      await studyRepo.deleteCard(card.id);
      widget.onChanged();
    } on Failure catch (f) {
      if (mounted) setState(() => _error = f.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final kit = widget.kit;
    if (kit.cards.isEmpty) {
      return StudyPage(children: [
        KitEmpty(
          icon: Icons.style_outlined,
          title: 'No flashcards yet',
          sentence: 'Flashcards hold a term on the front and its meaning on the back. The games use them too.',
          actions: [
            if (kit.note.hasMaterials)
              FilledButton.icon(
                onPressed: () => buildKitWithAi(context, ref, kit.note.id),
                icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                label: const Text('Build with AI'),
              ),
            OutlinedButton.icon(
              onPressed: _addCard,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add a card'),
            ),
          ],
        ),
      ]);
    }

    return StudyPage(
      children: [
        Row(
          children: [
            KitSegments(labels: const ['List', 'Deck', 'Games'], index: _view, onChanged: (i) => setState(() => _view = i)),
            const Spacer(),
            if (_view == 0)
              OutlinedButton.icon(
                onPressed: _addCard,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add'),
              ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: Gap.snug),
          InlineNotice(_error!, error: true, onClose: () => setState(() => _error = null)),
        ],
        const SizedBox(height: Gap.page),
        switch (_view) {
          0 => _CardList(cards: kit.cards, boxes: kit.boxes, onEdit: _editCard, onDelete: _deleteCard),
          1 => _Deck(kit: kit, onChanged: widget.onChanged),
          _ => _Games(kit: kit),
        },
      ],
    );
  }
}

// ------------------------------------------------------------------ list

class _CardList extends StatelessWidget {
  const _CardList({required this.cards, required this.boxes, required this.onEdit, required this.onDelete});
  final List<Flashcard> cards;
  final Map<String, int> boxes;
  final ValueChanged<Flashcard> onEdit;
  final ValueChanged<Flashcard> onDelete;

  @override
  Widget build(BuildContext context) => RowGroup(children: [
        for (final card in cards)
          StudyRow(
            title: card.front,
            detail: card.back,
            tags: [Tag(CardBoxX.fromInt(boxes[card.id]).label)],
            trailing: PopupMenuButton<String>(
              tooltip: 'Card options',
              icon: const Icon(Icons.more_horiz),
              onSelected: (v) => v == 'edit' ? onEdit(card) : onDelete(card),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ),
      ]);
}

// ------------------------------------------------------------------ deck

class _Deck extends StatefulWidget {
  const _Deck({required this.kit, required this.onChanged});
  final KitData kit;
  final VoidCallback onChanged;

  @override
  State<_Deck> createState() => _DeckState();
}

class _DeckState extends State<_Deck> {
  int _index = 0;
  bool _flipped = false;
  late Map<String, int> _boxes = {...widget.kit.boxes};
  String? _error;

  List<Flashcard> get _cards => widget.kit.cards;

  @override
  void didUpdateWidget(_Deck old) {
    super.didUpdateWidget(old);
    if (old.kit.cards.length != widget.kit.cards.length) {
      _boxes = {...widget.kit.boxes};
      _index = _index.clamp(0, max(0, widget.kit.cards.length - 1));
      _flipped = false;
    }
  }

  void _go(int delta) => setState(() {
        _index = (_index + delta) % _cards.length;
        if (_index < 0) _index += _cards.length;
        _flipped = false;
      });

  void _rate(CardRating rating) {
    final card = _cards[_index];
    final next = nextBox(CardBoxX.fromInt(_boxes[card.id]), rating);
    setState(() => _boxes[card.id] = next.index);
    unawaited(studyRepo.rateCard(card.id, next).catchError((Object e) {
      if (mounted) setState(() => _error = e is Failure ? e.message : 'Your progress could not be saved.');
    }));
    _go(1);
  }

  Future<void> _reset() async {
    try {
      await studyRepo.resetBoxes([for (final c in _cards) c.id]);
      if (!mounted) return;
      setState(() {
        _boxes = {};
        _index = 0;
        _flipped = false;
      });
      widget.onChanged();
    } on Failure catch (f) {
      if (mounted) setState(() => _error = f.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    final t = Theme.of(context).textTheme;
    final counts = boxCounts(_cards.map((x) => x.id), _boxes);
    final card = _cards[_index.clamp(0, _cards.length - 1)];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: Gap.snug),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(Radii.panel),
                  border: Border.all(color: c.line),
                ),
                child: Row(
                  children: [
                    for (final b in CardBox.values)
                      Expanded(
                        child: Column(
                          children: [
                            Text('${counts[b]}', style: Mono.of(context, size: 20, weight: FontWeight.w600, color: c.ink)),
                            const SizedBox(height: 2),
                            Text(b.label, style: t.bodySmall),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            IconButton(tooltip: 'Start the deck again', icon: const Icon(Icons.restart_alt), onPressed: _reset),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: Gap.snug),
          InlineNotice(_error!, error: true, onClose: () => setState(() => _error = null)),
        ],
        const SizedBox(height: Gap.page),
        _FlipCard(
          key: ValueKey(card.id),
          front: card.front,
          back: card.back,
          flipped: _flipped,
          box: CardBoxX.fromInt(_boxes[card.id]),
          onTap: () => setState(() => _flipped = !_flipped),
        ),
        const SizedBox(height: Gap.snug),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton.outlined(tooltip: 'Previous card', icon: const Icon(Icons.arrow_back), onPressed: () => _go(-1)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.page),
              child: Text('${_index + 1} / ${_cards.length}', style: Mono.of(context, size: 14, color: c.ink)),
            ),
            IconButton.outlined(tooltip: 'Next card', icon: const Icon(Icons.arrow_forward), onPressed: () => _go(1)),
          ],
        ),
        const SizedBox(height: Gap.page),
        Text(_flipped ? 'How well did you know it?' : 'Tap the card to see the answer, then rate it.',
            style: t.bodyMedium, textAlign: TextAlign.center),
        const SizedBox(height: Gap.snug),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _Rate(label: 'Again', icon: Icons.close, color: c.danger, wash: c.dangerWash, onTap: () => _rate(CardRating.again)),
            const SizedBox(width: Gap.page),
            _Rate(label: 'Not sure', icon: Icons.remove, color: c.warn, wash: c.warnWash, onTap: () => _rate(CardRating.unsure)),
            const SizedBox(width: Gap.page),
            _Rate(label: 'Got it', icon: Icons.check, color: c.success, wash: c.successWash, onTap: () => _rate(CardRating.gotIt)),
          ],
        ),
      ],
    );
  }
}

/// A card that turns over when tapped.
class _FlipCard extends StatelessWidget {
  const _FlipCard({
    super.key,
    required this.front,
    required this.back,
    required this.flipped,
    required this.box,
    required this.onTap,
  });
  final String front, back;
  final bool flipped;
  final CardBox box;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    final t = Theme.of(context).textTheme;

    Widget face(String text, {required bool isBack}) => Container(
          constraints: const BoxConstraints(minHeight: 260),
          padding: const EdgeInsets.all(Gap.section),
          decoration: BoxDecoration(
            color: isBack ? c.accentWash : c.surface,
            borderRadius: BorderRadius.circular(Radii.panel + 6),
            border: Border.all(color: isBack ? c.accent : c.lineStrong, width: 1.5),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(isBack ? 'MEANING' : 'TERM',
                  style: Mono.of(context, size: 11, weight: FontWeight.w600, color: isBack ? c.accent : c.inkFaint)),
              const SizedBox(height: Gap.snug),
              Text(
                text,
                textAlign: TextAlign.center,
                style: isBack ? t.bodyLarge?.copyWith(fontSize: 18) : t.headlineSmall?.copyWith(fontSize: 26),
              ),
              const SizedBox(height: Gap.snug),
              Text(box.label, style: t.bodySmall),
            ],
          ),
        );

    return Semantics(
      button: true,
      label: flipped ? 'Meaning: $back. Tap to see the term.' : 'Term: $front. Tap to see the meaning.',
      child: GestureDetector(
        onTap: onTap,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(end: flipped ? pi : 0.0),
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeInOut,
          builder: (context, angle, _) {
            final showBack = angle > pi / 2;
            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0012)
                ..rotateY(angle),
              child: showBack
                  ? Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.rotationY(pi),
                      child: face(back, isBack: true),
                    )
                  : face(front, isBack: false),
            );
          },
        ),
      ),
    );
  }
}

class _Rate extends StatelessWidget {
  const _Rate({required this.label, required this.icon, required this.color, required this.wash, required this.onTap});
  final String label;
  final IconData icon;
  final Color color, wash;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Tooltip(
            message: label,
            child: Material(
              color: wash,
              shape: CircleBorder(side: BorderSide(color: color, width: 1.5)),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                child: SizedBox(width: 58, height: 58, child: Icon(icon, color: color, size: 28)),
              ),
            ),
          ),
          const SizedBox(height: Gap.hair + 2),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}

// ------------------------------------------------------------------ games

class _Games extends StatelessWidget {
  const _Games({required this.kit});
  final KitData kit;

  @override
  Widget build(BuildContext context) {
    final deck = kit.deck!;
    final enough = kit.cards.length >= 2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!enough) ...[
          const InlineNotice('The games need at least two cards. Add another card in the List view.'),
          const SizedBox(height: Gap.snug),
        ],
        _GameTile(
          icon: Icons.join_inner,
          title: 'Matching',
          detail: 'Match each term to its meaning as fast as you can.',
          onTap: enough ? () => context.push('/study/deck/${deck.id}/game/matching') : null,
        ),
        const SizedBox(height: Gap.snug),
        _GameTile(
          icon: Icons.rule,
          title: 'True or false',
          detail: 'Does the meaning fit the term? Answer fast for bonus points.',
          onTap: enough ? () => context.push('/study/deck/${deck.id}/game/true_false') : null,
        ),
      ],
    );
  }
}

class _GameTile extends StatelessWidget {
  const _GameTile({required this.icon, required this.title, required this.detail, required this.onTap});
  final IconData icon;
  final String title, detail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    final t = Theme.of(context).textTheme;
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.panel + 2),
        side: BorderSide(color: c.ink, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Gap.page),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(color: c.ink, borderRadius: BorderRadius.circular(Radii.panel)),
                child: Icon(icon, color: c.canvas, size: 28),
              ),
              const SizedBox(width: Gap.page - 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: t.titleLarge),
                    const SizedBox(height: 2),
                    Text(detail, style: t.bodyMedium),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: onTap == null ? c.lineStrong : c.ink),
            ],
          ),
        ),
      ),
    );
  }
}
