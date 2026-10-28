// Unit tests for the study assistant's app-side logic: reading rows from
// the database, reading the AI function's answer, and the colour rules.
//
//   flutter test
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zutlib/core/theme/app_theme.dart';
import 'package:zutlib/models/study.dart';

void main() {
  group('Notes', () {
    test('a row from study_notes is read correctly', () {
      final n = Note.fromMap({
        'id': 'n1',
        'title': 'Electric circuits',
        'body': 'Ohm\'s law:\n\n   V = I R',
        'course_code': 'EEE 2021',
        'created_at': '2026-10-01T08:00:00Z',
        'updated_at': '2026-10-02T09:30:00Z',
      });
      expect(n.title, 'Electric circuits');
      expect(n.courseCode, 'EEE 2021');
      expect(n.updatedAt.isAfter(n.createdAt), isTrue);
      expect(n.preview, 'Ohm\'s law: V = I R');
    });

    test('a long note is shortened for the list', () {
      final n = Note.fromMap({
        'id': 'n2',
        'title': 'Long',
        'body': 'word ' * 100,
        'course_code': null,
        'created_at': '2026-10-01T08:00:00Z',
        'updated_at': '2026-10-01T08:00:00Z',
      });
      expect(n.preview.length, lessThanOrEqualTo(143));
      expect(n.preview.endsWith('...'), isTrue);
      expect(n.courseCode, isNull);
    });
  });

  group('Notes on PDFs', () {
    test('a note on an uploaded PDF with no typed text previews the PDF', () {
      final n = Note.fromMap({
        'id': 'n3',
        'title': 'Lecture 3',
        'body': '',
        'course_code': null,
        'created_at': '2026-10-01T08:00:00Z',
        'updated_at': '2026-10-01T08:00:00Z',
        'file_path': 'u/lecture-3.pdf',
        'file_name': 'Lecture 3.pdf',
        'resource_id': null,
        'resource': null,
      });
      expect(n.hasUpload, isTrue);
      expect(n.hasPdf, isTrue);
      expect(n.preview, 'PDF: Lecture 3.pdf');
    });

    test('a note on a library PDF reads the embedded resource', () {
      final n = Note.fromMap({
        'id': 'n4',
        'title': 'ICT 2010 exam 2023',
        'body': '',
        'created_at': '2026-10-01T08:00:00Z',
        'updated_at': '2026-10-01T08:00:00Z',
        'resource_id': 'r1',
        'resource': {'title': 'ICT 2010 Programming in C examination 2023', 'file_path': 'ICT/x.pdf'},
      });
      expect(n.hasLibraryPdf, isTrue);
      expect(n.pdfLabel, 'ICT 2010 Programming in C examination 2023');
    });

    test('a library note whose PDF was removed has no PDF', () {
      final n = Note.fromMap({
        'id': 'n5',
        'title': 'Gone',
        'body': '',
        'created_at': '2026-10-01T08:00:00Z',
        'updated_at': '2026-10-01T08:00:00Z',
        'resource_id': null,
        'resource': null,
      });
      expect(n.hasPdf, isFalse);
      expect(n.preview, '');
    });
  });

  group('Decks and quizzes', () {
    test('the embedded card count is read from PostgREST\'s shape', () {
      final d = Deck.fromMap({
        'id': 'd1',
        'note_id': null,
        'title': 'Circuits flashcards',
        'source': 'ai',
        'created_at': '2026-10-01T08:00:00Z',
        'updated_at': '2026-10-01T08:00:00Z',
        'study_flashcards': [
          {'count': 12}
        ],
      });
      expect(d.cardCount, 12);
      expect(d.source, StudySource.ai);
      expect(d.noteId, isNull);
    });

    test('quiz scores are sorted newest first', () {
      final q = Quiz.fromMap({
        'id': 'q1',
        'note_id': 'n1',
        'title': 'Circuits quiz',
        'source': 'manual',
        'created_at': '2026-10-01T08:00:00Z',
        'updated_at': '2026-10-01T08:00:00Z',
        'study_quiz_questions': [
          {'count': 5}
        ],
        'study_quiz_attempts': [
          {'score': 2, 'total': 5, 'created_at': '2026-10-01T10:00:00Z'},
          {'score': 4, 'total': 5, 'created_at': '2026-10-03T10:00:00Z'},
          {'score': 3, 'total': 5, 'created_at': '2026-10-02T10:00:00Z'},
        ],
      });
      expect(q.questionCount, 5);
      expect(q.latest!.label, '4/5');
      expect(q.scores.map((s) => s.score), [4, 3, 2]);
      expect(q.source, StudySource.manual);
    });

    test('a quiz question keeps its options in order', () {
      final q = QuizQuestion.fromMap({
        'id': 'x',
        'quiz_id': 'q1',
        'prompt': 'V = ?',
        'options': ['I R', 'I / R', 'R / I'],
        'correct_index': 0,
        'explanation': null,
        'position': 2,
      });
      expect(q.options, ['I R', 'I / R', 'R / I']);
      expect(q.correctIndex, 0);
      expect(q.explanation, isNull);
    });

    test('an attempt reads the score the database worked out', () {
      final a = QuizAttempt.fromMap({
        'id': 'a1',
        'quiz_id': 'q1',
        'answers': {'x': 0, 'y': 2},
        'score': 1,
        'total': 2,
        'created_at': '2026-10-01T10:00:00Z',
      });
      expect(a.answers, {'x': 0, 'y': 2});
      expect('${a.score}/${a.total}', '1/2');
    });
  });

  group('AI', () {
    test('every kind survives a round trip to the value the function expects', () {
      for (final k in StudyKind.values) {
        expect(StudyKindX.parse(k.wire), k);
      }
      expect(StudyKindX.parse('essay'), isNull);
    });

    test('a successful generate answer is read', () {
      final r = GenerateResult.tryParse({
        'kind': 'quiz',
        'id': 'q9',
        'cached': true,
        'reused': false,
        'remaining': 7,
      });
      expect(r, isNotNull);
      expect(r!.kind, StudyKind.quiz);
      expect(r.cached, isTrue);
      expect(r.remaining, 7);
    });

    test('an answer without a kind or id is rejected', () {
      expect(GenerateResult.tryParse({'id': 'x'}), isNull);
      expect(GenerateResult.tryParse({'kind': 'summary'}), isNull);
      expect(GenerateResult.tryParse('not a map'), isNull);
    });

    test('the allowance is read from study_ai_status', () {
      final s = AiStatus.fromMap({'used': 3, 'daily_limit': 10, 'remaining': 7});
      expect(s.remaining, 7);
      expect(s.dailyLimit, 10);
    });
  });

  group('Study colours', () {
    List<Color> all(StudyColors c) => [
          c.canvas, c.surface, c.sunken, c.line, c.lineStrong, c.ink, c.inkSoft,
          c.inkFaint, c.sky, c.skyWash, c.accent, c.onAccent, c.accentWash,
        ];

    test('no pure white or pure black in either mode', () {
      for (final c in [...all(StudyColors.light), ...all(StudyColors.dark)]) {
        expect(c.toARGB32(), isNot(0xFFFFFFFF));
        expect(c.toARGB32(), isNot(0xFF000000));
      }
    });

    test('light and dark modes are different palettes', () {
      expect(StudyColors.light.canvas, isNot(StudyColors.dark.canvas));
      expect(StudyColors.light.ink, isNot(StudyColors.dark.ink));
    });

    test('blending between modes gives a colour between the two', () {
      final mid = StudyColors.light.lerp(StudyColors.dark, 0.5);
      expect(mid.canvas, isNot(StudyColors.light.canvas));
      expect(mid.canvas, isNot(StudyColors.dark.canvas));
    });
  });
}
