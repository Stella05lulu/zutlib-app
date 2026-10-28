import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/study.dart';
import '../../../state/study_providers.dart';
import '../../widgets/study_widgets.dart';

/// Study mode: one card at a time. The student reads the front, reveals
/// the back, and says whether they knew it. Cards they did not know come
/// round again in the next pass, until every card has been known once.
/// Nothing is saved; this is practice.
class DeckStudyScreen extends ConsumerWidget {
  const DeckStudyScreen({super.key, required this.deckId});
  final String deckId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deck = ref.watch(deckProvider(deckId)).valueOrNull;
    final cards = ref.watch(cardsProvider(deckId));
    return StudyScope(
      child: Builder(builder: (context) {
        return Scaffold(
          appBar: StudyTopBar(title: deck == null ? 'Study' : 'Study: ${deck.title}'),
          body: StudyPage(
            maxWidth: 620,
            children: [
              StudyAsync<List<Flashcard>>(
                value: cards,
                onRetry: () => ref.invalidate(cardsProvider(deckId)),
                skeleton: const FlashcardSkeleton(),
                isEmpty: (v) => v.isEmpty,
                empty: StudyEmptyState(
                  'This deck has no cards to study yet.',
                  action: OutlinedButton(onPressed: () => context.pop(), child: const Text('Back to the deck')),
                ),
                data: (list) => _Session(cards: list),
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _Session extends StatefulWidget {
  const _Session({required this.cards});
  final List<Flashcard> cards;

  @override
  State<_Session> createState() => _SessionState();
}

class _SessionState extends State<_Session> {
  late List<Flashcard> _queue;
  final List<Flashcard> _again = [];
  int _index = 0;
  int _round = 1;
  int _knewFirstTime = 0;
  bool _showBack = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _queue = List.of(widget.cards);
  }

  void _restart({bool shuffle = false}) {
    setState(() {
      _queue = List.of(widget.cards);
      if (shuffle) _queue.shuffle();
      _again.clear();
      _index = 0;
      _round = 1;
      _knewFirstTime = 0;
      _showBack = false;
      _finished = false;
    });
  }

  void _answer(bool knew) {
    setState(() {
      if (knew && _round == 1) _knewFirstTime++;
      if (!knew) _again.add(_queue[_index]);
      _showBack = false;
      if (_index + 1 < _queue.length) {
        _index++;
      } else if (_again.isNotEmpty) {
        _queue = List.of(_again);
        _again.clear();
        _index = 0;
        _round++;
      } else {
        _finished = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    final t = Theme.of(context).textTheme;

    if (_finished) {
      final total = widget.cards.length;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Deck finished', style: t.headlineSmall),
          const SizedBox(height: Gap.snug),
          Text.rich(TextSpan(style: t.bodyLarge, children: [
            const TextSpan(text: 'You knew '),
            TextSpan(text: '$_knewFirstTime of $total', style: Mono.of(context, size: 16, weight: FontWeight.w600, color: c.ink)),
            const TextSpan(text: ' cards on the first pass.'),
          ])),
          if (_round > 1) ...[
            const SizedBox(height: Gap.tight),
            Text('The rest took $_round passes in all.', style: t.bodyMedium),
          ],
          const SizedBox(height: Gap.section),
          Wrap(spacing: Gap.tight, runSpacing: Gap.tight, children: [
            FilledButton(onPressed: () => _restart(shuffle: true), child: const Text('Study again, shuffled')),
            OutlinedButton(onPressed: () => context.pop(), child: const Text('Back to the deck')),
          ]),
        ],
      );
    }

    final card = _queue[_index];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('${_index + 1} / ${_queue.length}', style: Mono.of(context)),
            if (_round > 1) ...[
              const SizedBox(width: Gap.snug),
              Text('Pass $_round: the cards you did not know', style: t.bodySmall),
            ],
            const Spacer(),
            TextButton(onPressed: () => _restart(shuffle: true), child: const Text('Shuffle')),
          ],
        ),
        const SizedBox(height: Gap.tight),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: (_index + (_showBack ? 0.5 : 0)) / _queue.length,
            minHeight: 3,
          ),
        ),
        const SizedBox(height: Gap.page),
        Semantics(
          button: !_showBack,
          label: _showBack ? 'Answer' : 'Question. Tap to show the answer.',
          child: GestureDetector(
            onTap: _showBack ? null : () => setState(() => _showBack = true),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Container(
                key: ValueKey('${card.id}-$_showBack'),
                constraints: const BoxConstraints(minHeight: 260),
                padding: const EdgeInsets.fromLTRB(Gap.section, Gap.page, Gap.section, Gap.section),
                decoration: BoxDecoration(
                  color: _showBack ? c.skyWash : c.surface,
                  borderRadius: BorderRadius.circular(Radii.panel),
                  border: Border.all(color: _showBack ? c.sky : c.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_showBack ? 'ANSWER' : 'QUESTION',
                        style: Mono.of(context, size: 11, weight: FontWeight.w600, color: _showBack ? c.sky : c.inkFaint)),
                    const SizedBox(height: Gap.page),
                    Text(_showBack ? card.back : card.front,
                        style: t.titleLarge?.copyWith(fontWeight: _showBack ? FontWeight.w500 : FontWeight.w600)),
                    if (_showBack) ...[
                      const SizedBox(height: Gap.page),
                      Text(card.front, style: t.bodySmall),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: Gap.page),
        if (!_showBack)
          FilledButton(onPressed: () => setState(() => _showBack = true), child: const Text('Show answer'))
        else
          Row(
            children: [
              Expanded(
                child: OutlinedButton(onPressed: () => _answer(false), child: const Text('Not yet')),
              ),
              const SizedBox(width: Gap.tight),
              Expanded(
                child: FilledButton(onPressed: () => _answer(true), child: const Text('I knew it')),
              ),
            ],
          ),
      ],
    );
  }
}
