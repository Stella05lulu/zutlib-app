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

/// Red sends a card back to Learning, yellow keeps it in Reviewing, and
/// green moves it one box up, to Mastered at most.
CardBox nextBox(CardBox current, CardRating rating) => switch (rating) {
      CardRating.again => CardBox.learning,
      CardRating.unsure => CardBox.reviewing,
      CardRating.gotIt => CardBox.values[min(current.index + 1, CardBox.mastered.index)],
    };

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

/// Each question earns 0 to 3 stars. A right answer or a thumbs up adds a
/// star; a wrong answer or a thumbs down takes the question back to none.
abstract final class Stars {
  static const max = 3;

  static int afterAnswer(int current, {required bool correct}) =>
      correct ? min(current + 1, max) : 0;
}

/// Where a student is in Smart Study for one kit.
class SmartLevel {
  const SmartLevel({required this.level, required this.progress, required this.mastery});

  /// 1 to 3 while practising; 4 once every question has 3 stars.
  final int level;

  /// How far through the current level, from 0 to 1.
  final double progress;

  /// Stars earned out of all the stars there are, from 0 to 1.
  final double mastery;

  bool get complete => level > 3;

  /// The stars shown next to the level bar: one per level finished.
  int get starsShown => min(level - 1, 3);

  int get percent => (progress * 100).floor();
}

/// Three levels, each a third of all the stars in the kit.
SmartLevel smartLevel(Iterable<String> questionIds, Map<String, int> stars) {
  final ids = questionIds.toList();
  if (ids.isEmpty) return const SmartLevel(level: 1, progress: 0, mastery: 0);
  final earned = ids.fold<int>(0, (sum, id) => sum + (stars[id] ?? 0).clamp(0, Stars.max));
  final mastery = earned / (ids.length * Stars.max);
  if (mastery >= 1) return const SmartLevel(level: 4, progress: 1, mastery: 1);
  final level = (mastery * 3).floor() + 1;
  final progress = (mastery * 3 - (level - 1)).clamp(0.0, 1.0);
  return SmartLevel(level: level, progress: progress, mastery: mastery);
}

/// The next question to practise: one with the fewest stars, avoiding the
/// last few asked when there is any choice. Null when all have 3 stars.
String? pickNextQuestion(
  List<String> questionIds,
  Map<String, int> stars,
  List<String> recent,
  Random rng,
) {
  final open = questionIds.where((id) => (stars[id] ?? 0) < Stars.max).toList();
  if (open.isEmpty) return null;
  final fresh = open.where((id) => !recent.contains(id)).toList();
  final pool = fresh.isEmpty ? open : fresh;
  final fewest = pool.map((id) => stars[id] ?? 0).reduce(min);
  final candidates = pool.where((id) => (stars[id] ?? 0) == fewest).toList();
  return candidates[rng.nextInt(candidates.length)];
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
