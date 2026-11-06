/// The rules behind Smart Study, the flashcard deck, the two games and
/// test building. Plain Dart with no Flutter or Supabase, so every rule is
/// covered by test/practice_test.dart.
library;

import 'dart:math';

// ------------------------------------------------------------------ deck

/// Where a flashcard sits. Stored as 0 to 3 in study_card_progress.box.
enum CardBox { learning, reviewing, known, mastered }

extension CardBoxX on CardBox {
  String get label => switch (this) {
        CardBox.learning => 'Learning',
        CardBox.reviewing => 'Reviewing',
        CardBox.known => 'Known',
        CardBox.mastered => 'Mastered',
      };

  static CardBox fromInt(int? v) => CardBox.values[(v ?? 0).clamp(0, 3)];
}

/// The three buttons under a card: red, yellow and green.
enum CardRating { again, unsure, gotIt }

extension CardRatingX on CardRating {
  /// What the button says, so its meaning never depends on colour.
  String get label => switch (this) {
        CardRating.again => "Didn't know",
        CardRating.unsure => 'Almost',
        CardRating.gotIt => 'Knew it',
      };
}

/// Red ("Didn't know") sends a card back to Learning. Yellow ("Almost")
/// puts it in Reviewing. Green ("Knew it") makes a Learning or Reviewing
/// card Known straight away, and a Known card Mastered, so knowing a card
/// shows in the counts the first time.
CardBox nextBox(CardBox current, CardRating rating) => switch (rating) {
      CardRating.again => CardBox.learning,
      CardRating.unsure => CardBox.reviewing,
      CardRating.gotIt => current.index < CardBox.known.index ? CardBox.known : CardBox.mastered,
    };

/// The card to show after [current]: the next one in order that is not yet
/// Mastered, so a session works through what still needs practice. When
/// every card is Mastered it simply moves on.
int nextCardIndex(List<String> cardIds, Map<String, int> boxes, int current) {
  final n = cardIds.length;
  if (n == 0) return 0;
  for (var step = 1; step <= n; step++) {
    final i = (current + step) % n;
    if ((boxes[cardIds[i]] ?? 0) < CardBox.mastered.index) return i;
  }
  return (current + 1) % n;
}

/// How many of [cardIds] sit in each box. A card never rated is Learning.
Map<CardBox, int> boxCounts(Iterable<String> cardIds, Map<String, int> boxes) {
  final out = {for (final b in CardBox.values) b: 0};
  for (final id in cardIds) {
    final b = CardBoxX.fromInt(boxes[id]);
    out[b] = out[b]! + 1;
  }
  return out;
}

/// The share of a deck that is Known or Mastered, from 0 to 1.
double deckMastery(Iterable<String> cardIds, Map<String, int> boxes) {
  final ids = cardIds.toList();
  if (ids.isEmpty) return 0;
  final done = ids.where((id) => (boxes[id] ?? 0) >= CardBox.known.index).length;
  return done / ids.length;
}

// ------------------------------------------------------------------ smart study

/// Each question earns 0 to 3 stars; 3 means mastered and it is not asked
/// again. Right the first time: 3 stars at once. A miss leaves 1 star and
/// the question comes back later in the same level, until it has been
/// answered right twice more. So only the questions a student gets wrong
/// are repeated.
abstract final class Stars {
  static const max = 3;

  static int afterAnswer(int current, {required bool correct}) {
    if (!correct) return 1;
    if (current <= 0) return max;
    return min(current + 1, max);
  }

  static bool mastered(int? stars) => (stars ?? 0) >= max;
}

/// Difficulty 1 to 3 as a word.
String difficultyName(int d) => switch (d) { 1 => 'Easy', 3 => 'Hard', _ => 'Medium' };

/// Where a student is in Smart Study for one kit. The levels follow the
/// questions' difficulty: easy questions first, then medium, then hard.
/// A level with no questions is skipped.
class SmartLevel {
  const SmartLevel({
    required this.level,
    required this.levels,
    required this.progress,
    required this.mastery,
    required this.complete,
    this.difficulty = 2,
    this.left = 0,
  });

  /// 1 for the first level that has questions, and so on.
  final int level;

  /// How many levels this kit has (1 to 3).
  final int levels;

  /// How far through the current level, from 0 to 1.
  final double progress;

  /// Mastered questions out of all of them, from 0 to 1.
  final double mastery;

  final bool complete;

  /// The difficulty the current level asks (1 easy, 2 medium, 3 hard).
  final int difficulty;

  /// Questions still to master in the current level.
  final int left;

  /// One star for each level finished.
  int get starsShown => complete ? levels : level - 1;

  int get percent => (progress * 100).floor();

  String get name => difficultyName(difficulty);
}

int _diff(Map<String, int> difficulty, String id) => (difficulty[id] ?? 2).clamp(1, 3);

/// The level a student is on. [difficulty] maps question id to 1, 2 or 3;
/// without it every question counts as medium (one level).
SmartLevel smartLevel(Iterable<String> questionIds, Map<String, int> stars, {Map<String, int> difficulty = const {}}) {
  final ids = questionIds.toList();
  if (ids.isEmpty) return const SmartLevel(level: 1, levels: 1, progress: 0, mastery: 0, complete: false);
  final mastered = ids.where((id) => Stars.mastered(stars[id])).length;
  final mastery = mastered / ids.length;
  final buckets = [
    for (final d in const [1, 2, 3])
      if (ids.any((id) => _diff(difficulty, id) == d)) d,
  ];
  for (var i = 0; i < buckets.length; i++) {
    final inLevel = ids.where((id) => _diff(difficulty, id) == buckets[i]).toList();
    final open = inLevel.where((id) => !Stars.mastered(stars[id])).length;
    if (open > 0) {
      return SmartLevel(
        level: i + 1,
        levels: buckets.length,
        progress: (inLevel.length - open) / inLevel.length,
        mastery: mastery,
        complete: false,
        difficulty: buckets[i],
        left: open,
      );
    }
  }
  return SmartLevel(level: buckets.length, levels: buckets.length, progress: 1, mastery: 1, complete: true, difficulty: buckets.last);
}

/// The next question to practise, from the current level only: questions
/// never asked come first (in random order), then the ones answered wrong.
/// The question just asked is not repeated straight away when there is any
/// other choice. Null when every question is mastered, or there are none.
String? pickNextQuestion(
  List<String> questionIds,
  Map<String, int> stars,
  List<String> recent,
  Random rng, {
  Map<String, int> difficulty = const {},
}) {
  final level = smartLevel(questionIds, stars, difficulty: difficulty);
  if (level.complete) return null;
  final open = questionIds
      .where((id) => _diff(difficulty, id) == level.difficulty && !Stars.mastered(stars[id]))
      .toList();
  final last = recent.isEmpty ? null : recent.last;
  final notLast = open.where((id) => id != last).toList();
  final pool = notLast.isEmpty ? open : notLast;
  final unseen = pool.where((id) => (stars[id] ?? 0) == 0).toList();
  final from = unseen.isNotEmpty ? unseen : pool;
  // No questions at all (a kit whose build failed) is not an error.
  if (from.isEmpty) return null;
  return from[rng.nextInt(from.length)];
}

// ------------------------------------------------------------------ games

/// A card as the games need it.
typedef GameCard = ({String id, String term, String definition});

/// One tile on the matching board.
class MatchTile {
  const MatchTile({required this.cardId, required this.text, required this.isTerm});
  final String cardId;
  final String text;
  final bool isTerm;

  String get key => '${isTerm ? 't' : 'd'}:$cardId';
}

/// A board of [pairs] terms and their definitions, shuffled together.
List<MatchTile> matchingBoard(List<GameCard> cards, int pairs, Random rng) {
  final chosen = [...cards]..shuffle(rng);
  final take = chosen.take(min(pairs, chosen.length));
  final tiles = [
    for (final c in take) ...[
      MatchTile(cardId: c.id, text: c.term, isTerm: true),
      MatchTile(cardId: c.id, text: c.definition, isTerm: false),
    ],
  ]..shuffle(rng);
  return tiles;
}

/// Two tiles match when they are the term and definition of one card.
bool tilesMatch(MatchTile a, MatchTile b) => a.cardId == b.cardId && a.isTerm != b.isTerm;

/// Matching score: 100 a pair, minus 2 a second and 20 a mistake, never
/// below 10 a pair, so finishing always scores something.
int matchingScore({required int pairs, required int seconds, required int mistakes}) {
  final raw = pairs * 100 - seconds * 2 - mistakes * 20;
  return max(raw, pairs * 10);
}

/// One true-or-false round: a term shown with its own definition or
/// another card's.
class TrueFalseRound {
  const TrueFalseRound({required this.term, required this.definition, required this.isTrue});
  final String term;
  final String definition;
  final bool isTrue;
}

/// [rounds] rounds, about half of them true. Needs two cards or more.
List<TrueFalseRound> trueFalseRounds(List<GameCard> cards, int rounds, Random rng) {
  if (cards.length < 2) return const [];
  final out = <TrueFalseRound>[];
  for (var i = 0; i < rounds; i++) {
    final card = cards[rng.nextInt(cards.length)];
    final truthful = rng.nextBool();
    if (truthful) {
      out.add(TrueFalseRound(term: card.term, definition: card.definition, isTrue: true));
    } else {
      final others = cards.where((c) => c.id != card.id).toList();
      final other = others[rng.nextInt(others.length)];
      out.add(TrueFalseRound(term: card.term, definition: other.definition, isTrue: false));
    }
  }
  return out;
}

/// True-or-false score: 100 a right answer plus up to 50 for answering
/// within 3 seconds.
int trueFalseScore(Iterable<({bool correct, int millis})> answers) {
  var total = 0;
  for (final a in answers) {
    if (!a.correct) continue;
    final bonus = a.millis >= 3000 ? 0 : ((3000 - a.millis) / 60).round();
    total += 100 + bonus;
  }
  return min(total, 10000);
}

// ------------------------------------------------------------------ tests

/// A question as the test builder needs it.
typedef TestQuestion = ({String id, int difficulty});

/// How many questions in [questions] suit [difficulty] ('easy', 'mixed'
/// or 'hard').
int questionsAvailable(List<TestQuestion> questions, String difficulty) =>
    _suitable(questions, difficulty).length;

List<TestQuestion> _suitable(List<TestQuestion> questions, String difficulty) => switch (difficulty) {
      'easy' => questions.where((q) => q.difficulty <= 1).toList(),
      'hard' => questions.where((q) => q.difficulty >= 3).toList(),
      _ => questions,
    };

/// Up to [count] question ids at the chosen difficulty, in random order.
/// When there are not enough at that level, the nearest level fills in.
List<String> pickTestQuestions(List<TestQuestion> questions, int count, String difficulty, Random rng) {
  final first = [..._suitable(questions, difficulty)]..shuffle(rng);
  final picked = first.take(count).map((q) => q.id).toList();
  if (picked.length < count && difficulty != 'mixed') {
    final rest = questions.where((q) => !picked.contains(q.id)).toList()
      ..sort((a, b) => difficulty == 'easy'
          ? a.difficulty.compareTo(b.difficulty)
          : b.difficulty.compareTo(a.difficulty));
    picked.addAll(rest.take(count - picked.length).map((q) => q.id));
  }
  return picked;
}

/// 75 seconds becomes "1:15"; 3725 seconds becomes "1:02:05".
String clockLabel(int seconds) {
  final s = max(seconds, 0);
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = (s % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$sec' : '$m:$sec';
}
