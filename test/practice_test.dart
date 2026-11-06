// The rules behind Smart Study, the deck, the games and tests.
//
//   flutter test
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:zutlib/models/study.dart';
import 'package:zutlib/study/practice.dart';

void main() {
  group('Flashcard boxes', () {
    test('red sends a card back to Learning from anywhere', () {
      for (final b in CardBox.values) {
        expect(nextBox(b, CardRating.again), CardBox.learning);
      }
    });

    test('"Knew it" makes a card Known at once, then Mastered', () {
      expect(nextBox(CardBox.learning, CardRating.gotIt), CardBox.known);
      expect(nextBox(CardBox.reviewing, CardRating.gotIt), CardBox.known);
      expect(nextBox(CardBox.known, CardRating.gotIt), CardBox.mastered);
      expect(nextBox(CardBox.mastered, CardRating.gotIt), CardBox.mastered);
    });

    test('every button says what it does', () {
      expect([for (final r in CardRating.values) r.label], ["Didn't know", 'Almost', 'Knew it']);
    });

    test('the next card skips cards already Mastered', () {
      final ids = ['a', 'b', 'c', 'd'];
      expect(nextCardIndex(ids, {'b': 3, 'c': 3}, 0), 3);
      expect(nextCardIndex(ids, {'a': 3}, 3), 1);
      // All mastered: just move on.
      expect(nextCardIndex(ids, {'a': 3, 'b': 3, 'c': 3, 'd': 3}, 1), 2);
    });

    test('yellow keeps a card in Reviewing', () {
      expect(nextBox(CardBox.learning, CardRating.unsure), CardBox.reviewing);
      expect(nextBox(CardBox.mastered, CardRating.unsure), CardBox.reviewing);
    });

    test('a card never rated counts as Learning', () {
      final counts = boxCounts(['a', 'b', 'c'], {'b': 2});
      expect(counts[CardBox.learning], 2);
      expect(counts[CardBox.known], 1);
      expect(deckMastery(['a', 'b', 'c', 'd'], {'b': 2, 'c': 3}), 0.5);
    });
  });

  group('Smart Study', () {
    test('right the first time masters a question; a miss needs two more right answers', () {
      expect(Stars.afterAnswer(0, correct: true), 3);
      expect(Stars.afterAnswer(0, correct: false), 1);
      expect(Stars.afterAnswer(1, correct: true), 2);
      expect(Stars.afterAnswer(2, correct: true), 3);
      expect(Stars.afterAnswer(2, correct: false), 1);
      expect(Stars.mastered(3), isTrue);
      expect(Stars.mastered(2), isFalse);
    });

    final diff = {'e1': 1, 'e2': 1, 'm1': 2, 'h1': 3};
    final ids = diff.keys.toList();

    test('levels follow difficulty: easy, then medium, then hard', () {
      final start = smartLevel(ids, {}, difficulty: diff);
      expect(start.level, 1);
      expect(start.levels, 3);
      expect(start.name, 'Easy');
      expect(start.left, 2);
      final half = smartLevel(ids, {'e1': 3}, difficulty: diff);
      expect(half.percent, 50);
      final medium = smartLevel(ids, {'e1': 3, 'e2': 3}, difficulty: diff);
      expect(medium.level, 2);
      expect(medium.name, 'Medium');
      expect(medium.starsShown, 1);
      final done = smartLevel(ids, {'e1': 3, 'e2': 3, 'm1': 3, 'h1': 3}, difficulty: diff);
      expect(done.complete, isTrue);
      expect(done.starsShown, 3);
      expect(done.mastery, 1);
    });

    test('a level with no questions is skipped', () {
      final l = smartLevel(['m', 'h'], {}, difficulty: {'m': 2, 'h': 3});
      expect(l.levels, 2);
      expect(l.name, 'Medium');
    });

    test('a question answered right is never asked again', () {
      final rng = Random(3);
      for (var i = 0; i < 50; i++) {
        final next = pickNextQuestion(ids, {'e1': 3}, const [], rng, difficulty: diff);
        expect(next, 'e2');
      }
    });

    test('new questions come before missed ones, and the last one asked waits', () {
      final rng = Random(4);
      // e1 was missed (1 star), e2 is new: e2 first.
      expect(pickNextQuestion(ids, {'e1': 1}, const [], rng, difficulty: diff), 'e2');
      // Both missed, e2 just asked: e1 next.
      expect(pickNextQuestion(ids, {'e1': 1, 'e2': 1}, ['e2'], rng, difficulty: diff), 'e1');
      // Only e2 left in the level: it comes back even though it was just asked.
      expect(pickNextQuestion(ids, {'e1': 3, 'e2': 1}, ['e2'], rng, difficulty: diff), 'e2');
    });

    test('medium questions are not asked until the easy ones are mastered', () {
      final rng = Random(5);
      for (var i = 0; i < 30; i++) {
        final next = pickNextQuestion(ids, {'e1': 1}, const [], rng, difficulty: diff);
        expect(next, anyOf('e1', 'e2'));
      }
    });

    test('there is no next question once every one is mastered', () {
      expect(pickNextQuestion(['a'], {'a': 3}, const [], Random(1)), isNull);
    });

    test('a kit with no questions gives no question instead of crashing', () {
      expect(pickNextQuestion(const [], const {}, const [], Random(1)), isNull);
    });
  });

  group('Games', () {
    final cards = [
      for (var i = 0; i < 8; i++) (id: 'c$i', term: 'Term $i', definition: 'Definition $i'),
    ];

    test('a matching board holds each chosen term with its own definition', () {
      final tiles = matchingBoard(cards, 6, Random(2));
      expect(tiles.length, 12);
      final terms = tiles.where((t) => t.isTerm).map((t) => t.cardId).toSet();
      final defs = tiles.where((t) => !t.isTerm).map((t) => t.cardId).toSet();
      expect(terms, defs);
    });

    test('only a term and its own definition match', () {
      const term = MatchTile(cardId: 'x', text: 'T', isTerm: true);
      const def = MatchTile(cardId: 'x', text: 'D', isTerm: false);
      const other = MatchTile(cardId: 'y', text: 'D2', isTerm: false);
      expect(tilesMatch(term, def), isTrue);
      expect(tilesMatch(term, other), isFalse);
      expect(tilesMatch(term, term), isFalse);
    });

    test('a matching score never drops below 10 a pair', () {
      expect(matchingScore(pairs: 6, seconds: 30, mistakes: 1), 600 - 60 - 20);
      expect(matchingScore(pairs: 6, seconds: 9999, mistakes: 50), 60);
    });

    test('a false round shows another card\'s definition', () {
      final rounds = trueFalseRounds(cards, 40, Random(3));
      expect(rounds.length, 40);
      for (final r in rounds) {
        final own = cards.firstWhere((c) => c.term == r.term).definition;
        expect(r.definition == own, r.isTrue);
      }
      expect(rounds.any((r) => r.isTrue), isTrue);
      expect(rounds.any((r) => !r.isTrue), isTrue);
    });

    test('true or false needs two cards', () {
      expect(trueFalseRounds(cards.take(1).toList(), 5, Random(1)), isEmpty);
    });

    test('fast right answers earn a bonus, wrong ones nothing', () {
      expect(trueFalseScore([(correct: true, millis: 0), (correct: false, millis: 100), (correct: true, millis: 5000)]),
          150 + 100);
    });
  });

  group('Tests', () {
    final qs = [
      (id: 'e1', difficulty: 1), (id: 'e2', difficulty: 1),
      (id: 'm1', difficulty: 2), (id: 'h1', difficulty: 3), (id: 'h2', difficulty: 3),
    ];

    test('a hard test takes hard questions first, then the nearest level', () {
      final picked = pickTestQuestions(qs, 3, 'hard', Random(4));
      expect(picked.length, 3);
      expect(picked.take(2).toSet(), {'h1', 'h2'});
      expect(picked.last, 'm1');
    });

    test('an easy test of two is all easy', () {
      expect(pickTestQuestions(qs, 2, 'easy', Random(5)).toSet(), {'e1', 'e2'});
    });

    test('a test never repeats a question or exceeds the bank', () {
      final picked = pickTestQuestions(qs, 50, 'mixed', Random(6));
      expect(picked.length, 5);
      expect(picked.toSet().length, 5);
    });

    test('clock labels', () {
      expect(clockLabel(75), '1:15');
      expect(clockLabel(5), '0:05');
      expect(clockLabel(3725), '1:02:05');
    });
  });

  group('YouTube links', () {
    test('every common form becomes the one stored form', () {
      const want = 'https://www.youtube.com/watch?v=dQw4w9WgXcQ';
      for (final link in [
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        'youtube.com/watch?v=dQw4w9WgXcQ&t=42s',
        'https://youtu.be/dQw4w9WgXcQ?si=abc',
        'https://m.youtube.com/watch?v=dQw4w9WgXcQ',
        'https://www.youtube.com/shorts/dQw4w9WgXcQ',
      ]) {
        expect(normaliseYoutubeUrl(link), want, reason: link);
      }
    });

    test('anything else is refused', () {
      for (final link in ['', 'https://vimeo.com/123', 'https://www.youtube.com/watch?v=short', 'not a link']) {
        expect(normaliseYoutubeUrl(link), isNull, reason: link);
      }
    });
  });
}
