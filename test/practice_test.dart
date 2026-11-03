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

    test('green moves a card up one box and stops at Mastered', () {
      expect(nextBox(CardBox.learning, CardRating.gotIt), CardBox.reviewing);
      expect(nextBox(CardBox.known, CardRating.gotIt), CardBox.mastered);
      expect(nextBox(CardBox.mastered, CardRating.gotIt), CardBox.mastered);
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
    test('a right answer adds a star up to 3; a wrong one resets', () {
      expect(Stars.afterAnswer(0, correct: true), 1);
      expect(Stars.afterAnswer(3, correct: true), 3);
      expect(Stars.afterAnswer(2, correct: false), 0);
    });

    test('levels are thirds of all the stars', () {
      final ids = ['a', 'b', 'c'];
      expect(smartLevel(ids, {}).level, 1);
      expect(smartLevel(ids, {}).percent, 0);
      final mid = smartLevel(ids, {'a': 3, 'b': 1}); // 4 of 9 stars
      expect(mid.level, 2);
      expect(mid.starsShown, 1);
      expect(mid.percent, 33);
      final done = smartLevel(ids, {'a': 3, 'b': 3, 'c': 3});
      expect(done.complete, isTrue);
      expect(done.starsShown, 3);
    });

    test('the next question has the fewest stars and was not just asked', () {
      final rng = Random(1);
      final next = pickNextQuestion(['a', 'b', 'c'], {'a': 0, 'b': 2, 'c': 0}, ['a'], rng);
      expect(next, 'c');
    });

    test('there is no next question once every one has 3 stars', () {
      expect(pickNextQuestion(['a'], {'a': 3}, const [], Random(1)), isNull);
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
