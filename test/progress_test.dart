// My progress rules (lib/study/progress.dart).
//
//   flutter test test/progress_test.dart
import 'package:flutter_test/flutter_test.dart';

import 'package:zutlib/study/progress.dart';

AttemptRecord attempt(DateTime at, Map<String, int> answers, {int score = 1, int total = 2, String? note, String? course}) =>
    AttemptRecord(at: at, score: score, total: total, answers: answers, noteId: note, courseCode: course);

void main() {
  const q1 = QuestionInfo(id: 'q1', prompt: 'What is Ohm\'s law?', correctIndex: 0);
  const q2 = QuestionInfo(id: 'q2', prompt: 'Unit of power?', correctIndex: 1);
  const q3 = QuestionInfo(id: 'q3', prompt: 'Unit of charge?', correctIndex: 2);
  const questions = {'q1': q1, 'q2': q2, 'q3': q3};
  DateTime d(int day) => DateTime(2026, 10, day, 10);

  group('scoreSeries', () {
    test('oldest first, as percentages', () {
      final s = scoreSeries([
        attempt(d(3), {}, score: 3, total: 4),
        attempt(d(1), {}, score: 1, total: 4),
      ]);
      expect(s.map((p) => p.percent), [0.25, 0.75]);
    });

    test('filters by kit and by course, whatever the spacing of the code', () {
      final all = [
        attempt(d(1), {}, note: 'a', course: 'EEE 2011'),
        attempt(d(2), {}, note: 'b', course: 'ICT 1131'),
      ];
      expect(scoreSeries(all, noteId: 'a').length, 1);
      expect(scoreSeries(all, courseCode: 'eee2011').length, 1);
      expect(scoreSeries(all, courseCode: 'BUS 1000'), isEmpty);
    });

    test('recentChange compares the last three with the three before', () {
      final pts = [for (var i = 0; i < 6; i++) ScorePoint(d(i + 1), i < 3 ? 0.5 : 0.8)];
      expect(recentChange(pts), closeTo(0.3, 1e-9));
      expect(recentChange(pts.take(5).toList()), isNull);
    });
  });

  group('reviseNext', () {
    test('a question wrong in 3 of the last 4 tries comes first, with the reason', () {
      final attempts = [
        attempt(d(1), {'q1': 0, 'q2': 0}), // q1 right, q2 wrong
        attempt(d(2), {'q1': 1, 'q2': 1}), // q1 wrong, q2 right
        attempt(d(3), {'q1': 1}),
        attempt(d(4), {'q1': 2}),
        attempt(d(5), {'q1': 0}),
      ];
      final out = reviseNext(attempts, questions);
      expect(out.first.question.id, 'q1');
      expect(out.first.reason, 'Wrong in 3 of your last 4 tries');
      expect(out.any((x) => x.question.id == 'q2'), isTrue);
    });

    test('only the last four tries count', () {
      final attempts = [
        for (var i = 1; i <= 4; i++) attempt(d(i), {'q3': 0}), // wrong four times
        for (var i = 5; i <= 8; i++) attempt(d(i), {'q3': 2}), // then right four times
      ];
      expect(reviseNext(attempts, questions), isEmpty);
    });

    test('a question answered right more often than wrong is not suggested', () {
      final attempts = [
        attempt(d(1), {'q2': 0}),
        attempt(d(2), {'q2': 1}),
        attempt(d(3), {'q2': 1}),
      ];
      expect(reviseNext(attempts, questions), isEmpty);
    });

    test('always wrong beats sometimes wrong; reasons read naturally', () {
      final attempts = [
        attempt(d(1), {'q1': 1, 'q2': 0}),
        attempt(d(2), {'q1': 1, 'q2': 1}),
        attempt(d(3), {'q3': 0}),
      ];
      final out = reviseNext(attempts, questions);
      expect(out.map((x) => x.question.id).toList(), ['q1', 'q3', 'q2']);
      expect(out[0].reason, 'Wrong in all of your last 2 tries');
      expect(out[1].reason, 'Wrong the only time you tried it');
      expect(out[2].reason, 'Wrong in 1 of your last 2 tries');
    });

    test('deleted questions are ignored and the list is capped', () {
      final attempts = [attempt(d(1), {'gone': 0, 'q1': 3})];
      final out = reviseNext(attempts, questions, limit: 1);
      expect(out.length, 1);
      expect(out.first.question.id, 'q1');
    });
  });

  group('attemptStreak', () {
    final now = DateTime(2026, 10, 10, 18);
    test('counts back from today', () {
      expect(attemptStreak([DateTime(2026, 10, 10, 9), DateTime(2026, 10, 9), DateTime(2026, 10, 8)], now), 3);
    });
    test('nothing yet today still keeps yesterday\'s streak', () {
      expect(attemptStreak([DateTime(2026, 10, 9), DateTime(2026, 10, 8)], now), 2);
    });
    test('a gap ends it', () {
      expect(attemptStreak([DateTime(2026, 10, 10), DateTime(2026, 10, 8)], now), 1);
      expect(attemptStreak(const [], now), 0);
    });
  });
}
