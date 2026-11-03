import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/study.dart';
import '../../../state/study_providers.dart';
import '../../../study/practice.dart';
import '../../widgets/study_widgets.dart';

/// The two flashcard games, Matching and True or false, with a start
/// screen, instructions and a scoreboard of the best ten games.
class KitGameScreen extends ConsumerWidget {
  const KitGameScreen({super.key, required this.deckId, required this.game});
  final String deckId;
  final GameKind game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardsAsync = ref.watch(cardsProvider(deckId));
    return StudyScope(
      child: Scaffold(
        appBar: StudyTopBar(title: game.label),
        body: StudyAsync<List<Flashcard>>(
          value: cardsAsync,
          onRetry: () => ref.invalidate(cardsProvider(deckId)),
          skeleton: const StudyPage(children: [RowsSkeleton(rows: 3, detail: false)]),
          isEmpty: (v) => v.length < 2,
          empty: const StudyPage(children: [
            StudyEmptyState('The games need at least two flashcards in this deck.'),
          ]),
          data: (cards) => _GameHost(
            deckId: deckId,
            game: game,
            cards: [for (final c in cards) (id: c.id, term: c.front, definition: c.back)],
          ),
        ),
      ),
    );
  }
}

enum _Phase { start, playing, done }

class _GameHost extends ConsumerStatefulWidget {
  const _GameHost({required this.deckId, required this.game, required this.cards});
  final String deckId;
  final GameKind game;
  final List<GameCard> cards;

  @override
  ConsumerState<_GameHost> createState() => _GameHostState();
}

class _GameHostState extends ConsumerState<_GameHost> {
  _Phase _phase = _Phase.start;
  int _round = 0; // changes the key so each game starts fresh
  int? _score;
  int _seconds = 0;
  String? _error;

  ({String deckId, GameKind game}) get _key => (deckId: widget.deckId, game: widget.game);

  Future<void> _finished(int score, int seconds) async {
    setState(() {
      _phase = _Phase.done;
      _score = score;
      _seconds = seconds;
    });
    try {
      await studyRepo.saveGameScore(widget.deckId, widget.game, score, seconds);
      ref.invalidate(gameScoresProvider(_key));
    } on Failure catch (f) {
      if (mounted) setState(() => _error = f.message);
    }
  }

  void _play() => setState(() {
        _phase = _Phase.playing;
        _round++;
        _error = null;
      });

  Future<void> _scoreboard() => showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        builder: (_) => StudyScope(child: _Scoreboard(scoreKey: _key)),
      );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = StudyColors.of(context);
    final matching = widget.game == GameKind.matching;

    if (_phase == _Phase.playing) {
      return matching
          ? _Matching(key: ValueKey(_round), cards: widget.cards, onDone: _finished)
          : _TrueFalse(key: ValueKey(_round), cards: widget.cards, onDone: _finished);
    }

    return StudyPage(
      children: [
        if (_phase == _Phase.done && _score != null) ...[
          Container(
            padding: const EdgeInsets.all(Gap.section),
            decoration: BoxDecoration(color: c.accentWash, borderRadius: BorderRadius.circular(Radii.panel + 4)),
            child: Column(
              children: [
                Text('$_score', style: Mono.of(context, size: 48, weight: FontWeight.w700, color: c.accent)),
                Text('points in ${clockLabel(_seconds)}', style: t.titleMedium),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: Gap.snug),
            InlineNotice(_error!, error: true),
          ],
          const SizedBox(height: Gap.page),
        ],
        Center(
          child: Column(
            children: [
              Icon(matching ? Icons.join_inner : Icons.rule, size: 40, color: c.ink),
              const SizedBox(height: Gap.tight),
              Text(widget.game.label, style: t.headlineSmall),
              const SizedBox(height: Gap.page),
              SizedBox(
                width: 220,
                child: FilledButton(
                  style: FilledButton.styleFrom(shape: const StadiumBorder()),
                  onPressed: _play,
                  child: Text(_phase == _Phase.done ? 'Play again' : 'New game'),
                ),
              ),
              const SizedBox(height: Gap.tight),
              SizedBox(
                width: 220,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(shape: const StadiumBorder()),
                  onPressed: _scoreboard,
                  child: const Text('Scoreboard'),
                ),
              ),
            ],
          ),
        ),
        const SectionLabel('Instructions'),
        for (final line in matching
            ? const [
                'Tap a term, then tap the meaning that goes with it.',
                'A wrong pair flashes red and costs 20 points. Keep trying.',
                'Clear every pair as quickly as you can for a high score.',
              ]
            : const [
                'Each round shows a term with a meaning.',
                'Tap True if the meaning belongs to the term, False if it does not.',
                'Right answers score 100, with up to 50 more for answering within 3 seconds.',
              ])
          Padding(
            padding: const EdgeInsets.only(bottom: Gap.tight),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 8, right: Gap.snug),
                  child: Container(width: 6, height: 6, decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle)),
                ),
                Expanded(child: Text(line, style: t.bodyLarge)),
              ],
            ),
          ),
      ],
    );
  }
}

class _Scoreboard extends ConsumerWidget {
  const _Scoreboard({required this.scoreKey});
  final ({String deckId, GameKind game}) scoreKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.page, Gap.page, Gap.page, Gap.section),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Scoreboard', style: t.titleLarge),
          const SizedBox(height: Gap.snug),
          StudyAsync<List<GameScore>>(
            value: ref.watch(gameScoresProvider(scoreKey)),
            onRetry: () => ref.invalidate(gameScoresProvider(scoreKey)),
            skeleton: const RowsSkeleton(rows: 3, detail: false),
            isEmpty: (v) => v.isEmpty,
            empty: const StudyEmptyState('Play to see your best scores here.', compact: true),
            data: (scores) => RowGroup(children: [
              for (var i = 0; i < scores.length; i++)
                StudyRow(
                  title: '${i + 1}.  ${scores[i].score} points',
                  meta: '${clockLabel(scores[i].seconds)}  /  ${studyDate.format(scores[i].at)}',
                ),
            ]),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ matching

class _Matching extends StatefulWidget {
  const _Matching({super.key, required this.cards, required this.onDone});
  final List<GameCard> cards;
  final void Function(int score, int seconds) onDone;

  @override
  State<_Matching> createState() => _MatchingState();
}

class _MatchingState extends State<_Matching> {
  late final List<MatchTile> _tiles = matchingBoard(widget.cards, 6, Random());
  late final int _pairs = _tiles.length ~/ 2;
  final _cleared = <String>{};
  final _watch = Stopwatch()..start();
  Timer? _tick;
  MatchTile? _picked;
  Set<String> _wrong = {};
  int _mistakes = 0;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _tap(MatchTile tile) {
    if (_cleared.contains(tile.key) || _wrong.isNotEmpty) return;
    final first = _picked;
    if (first == null || first.key == tile.key) {
      setState(() => _picked = first?.key == tile.key ? null : tile);
      return;
    }
    if (first.isTerm == tile.isTerm) {
      setState(() => _picked = tile);
      return;
    }
    if (tilesMatch(first, tile)) {
      setState(() {
        _cleared.addAll([first.key, tile.key]);
        _picked = null;
      });
      if (_cleared.length == _tiles.length) {
        _watch.stop();
        _tick?.cancel();
        final seconds = _watch.elapsed.inSeconds;
        widget.onDone(matchingScore(pairs: _pairs, seconds: seconds, mistakes: _mistakes), seconds);
      }
    } else {
      setState(() {
        _wrong = {first.key, tile.key};
        _mistakes++;
        _picked = null;
      });
      Timer(const Duration(milliseconds: 650), () {
        if (mounted) setState(() => _wrong = {});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    final t = Theme.of(context).textTheme;
    return LayoutBuilder(builder: (context, box) {
      final columns = box.maxWidth >= 720 ? 4 : box.maxWidth >= 460 ? 3 : 2;
      return StudyPage(
        maxWidth: 960,
        children: [
          Row(
            children: [
              Text('${_cleared.length ~/ 2} of $_pairs pairs', style: Mono.of(context, size: 13, color: c.ink)),
              const Spacer(),
              Icon(Icons.timer_outlined, size: 18, color: c.inkSoft),
              const SizedBox(width: 4),
              Text(clockLabel(_watch.elapsed.inSeconds), style: Mono.of(context, size: 14, color: c.ink)),
            ],
          ),
          const SizedBox(height: Gap.page),
          GridView.count(
            crossAxisCount: columns,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: Gap.tight + 2,
            crossAxisSpacing: Gap.tight + 2,
            childAspectRatio: 1.25,
            children: [
              for (final tile in _tiles)
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 250),
                  opacity: _cleared.contains(tile.key) ? 0 : 1,
                  child: IgnorePointer(
                    ignoring: _cleared.contains(tile.key),
                    child: Material(
                      color: _wrong.contains(tile.key)
                          ? c.dangerWash
                          : _picked?.key == tile.key
                              ? c.accentWash
                              : tile.isTerm
                                  ? c.surface
                                  : c.sunken,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(Radii.panel),
                        side: BorderSide(
                          color: _wrong.contains(tile.key)
                              ? c.danger
                              : _picked?.key == tile.key
                                  ? c.accent
                                  : c.line,
                          width: _picked?.key == tile.key || _wrong.contains(tile.key) ? 2 : 1,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => _tap(tile),
                        child: Padding(
                          padding: const EdgeInsets.all(Gap.tight + 2),
                          child: Center(
                            child: Text(
                              tile.text,
                              textAlign: TextAlign.center,
                              maxLines: 6,
                              overflow: TextOverflow.ellipsis,
                              style: tile.isTerm
                                  ? t.titleMedium
                                  : t.bodySmall?.copyWith(color: c.ink, fontSize: 12.5),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      );
    });
  }
}

// ------------------------------------------------------------------ true or false

class _TrueFalse extends StatefulWidget {
  const _TrueFalse({super.key, required this.cards, required this.onDone});
  final List<GameCard> cards;
  final void Function(int score, int seconds) onDone;

  @override
  State<_TrueFalse> createState() => _TrueFalseState();
}

class _TrueFalseState extends State<_TrueFalse> {
  static const _rounds = 10;
  late final List<TrueFalseRound> _list = trueFalseRounds(widget.cards, _rounds, Random());
  final _answers = <({bool correct, int millis})>[];
  final _total = Stopwatch()..start();
  final _round = Stopwatch()..start();
  int _index = 0;
  bool? _lastCorrect;

  void _answer(bool saidTrue) {
    if (_lastCorrect != null) return;
    final r = _list[_index];
    final correct = saidTrue == r.isTrue;
    _answers.add((correct: correct, millis: _round.elapsedMilliseconds));
    setState(() => _lastCorrect = correct);
    Timer(Duration(milliseconds: correct ? 500 : 1400), () {
      if (!mounted) return;
      if (_index + 1 >= _list.length) {
        _total.stop();
        widget.onDone(trueFalseScore(_answers), _total.elapsed.inSeconds);
        return;
      }
      setState(() {
        _index++;
        _lastCorrect = null;
      });
      _round
        ..reset()
        ..start();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    final t = Theme.of(context).textTheme;
    final r = _list[_index];
    final score = trueFalseScore(_answers);
    final answered = _lastCorrect != null;
    return StudyPage(
      children: [
        Row(
          children: [
            Text('Round ${_index + 1} of ${_list.length}', style: Mono.of(context, size: 13, color: c.ink)),
            const Spacer(),
            Text('$score points', style: Mono.of(context, size: 13, weight: FontWeight.w600, color: c.accent)),
          ],
        ),
        const SizedBox(height: Gap.tight),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(value: (_index + 1) / _list.length, minHeight: 6, color: c.accent),
        ),
        const SizedBox(height: Gap.section),
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(Gap.section),
          decoration: BoxDecoration(
            color: !answered ? c.surface : _lastCorrect! ? c.successWash : c.dangerWash,
            borderRadius: BorderRadius.circular(Radii.panel + 6),
            border: Border.all(
              color: !answered ? c.lineStrong : _lastCorrect! ? c.success : c.danger,
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Text('TERM', style: Mono.of(context, size: 11, weight: FontWeight.w600, color: c.inkFaint)),
              const SizedBox(height: Gap.tight),
              Text(r.term, textAlign: TextAlign.center, style: t.headlineSmall),
              const SizedBox(height: Gap.page),
              Text('MEANING', style: Mono.of(context, size: 11, weight: FontWeight.w600, color: c.inkFaint)),
              const SizedBox(height: Gap.tight),
              Text(r.definition, textAlign: TextAlign.center, style: t.bodyLarge),
              if (answered) ...[
                const SizedBox(height: Gap.page),
                Text(
                  _lastCorrect!
                      ? 'Right'
                      : r.isTrue
                          ? 'Wrong: that meaning does belong to the term.'
                          : 'Wrong: that meaning belongs to a different term.',
                  textAlign: TextAlign.center,
                  style: t.titleMedium?.copyWith(color: _lastCorrect! ? c.success : c.danger),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: Gap.section),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 56,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: c.success, foregroundColor: c.surface),
                  onPressed: answered ? null : () => _answer(true),
                  icon: const Icon(Icons.check),
                  label: const Text('True'),
                ),
              ),
            ),
            const SizedBox(width: Gap.snug),
            Expanded(
              child: SizedBox(
                height: 56,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: c.danger, foregroundColor: c.surface),
                  onPressed: answered ? null : () => _answer(false),
                  icon: const Icon(Icons.close),
                  label: const Text('False'),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
