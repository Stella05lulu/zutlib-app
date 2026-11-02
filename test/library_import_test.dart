// Unit tests for the librarian imports: every row is checked on its own,
// a bad row is reported with its reason, and good rows are kept.
//
//   flutter test
import 'package:flutter_test/flutter_test.dart';

import 'package:zutlib/data/library_import.dart';
import 'package:zutlib/models/profile.dart';
import 'package:zutlib/models/resource.dart';

void main() {
  group('ISBN', () {
    test('hyphens and spaces are removed', () {
      expect(cleanIsbn('978-0-13-468599-1'), '9780134685991');
      expect(cleanIsbn(' 0-13-814757-4 '), '0138147574');
    });
    test('a final X is kept', () => expect(cleanIsbn('0-8044-2957-x'), '080442957X'));
    test('empty means no ISBN', () => expect(cleanIsbn('  '), isNull));
    test('the wrong number of digits is refused', () {
      expect(() => cleanIsbn('12345'), throwsFormatException);
    });
  });

  group('Books CSV', () {
    test('good rows are accepted and bad rows say why', () {
      final parsed = parseBooksCsv('$kBookCsvHeader\n'
          'Digital Design,M. Morris Mano,978-0-13-277420-8,Engineering,EEE 3010,6th,3\n'
          'No Author,,,ICT,,,2\n'
          'Wrong Department,Someone,,Medicine,,,1\n'
          'Bad Copies,Someone,,ICT,,,many\n'
          'Bad ISBN,Someone,123,ICT,,,1\n');
      expect(parsed.fileProblem, isNull);
      expect(parsed.rows.length, 5);
      expect(parsed.rows.first.isOk, isTrue);
      expect(parsed.rows.first.value!.isbn, '9780132774208');
      expect(parsed.rows.first.value!.toRow()['available_copies'], 3);
      expect(parsed.rows[1].problem, contains('author'));
      expect(parsed.rows[2].problem, contains('department'));
      expect(parsed.rows[3].problem, contains('whole number'));
      expect(parsed.rows[4].problem, contains('ISBN'));
      expect(parsed.rows.map((r) => r.line), [2, 3, 4, 5, 6]);
    });

    test('columns may come in any order', () {
      final parsed = parseBooksCsv('total_copies,department,author,title\n2,ICT,Ian Sommerville,Software Engineering\n');
      expect(parsed.rows.single.value!.title, 'Software Engineering');
    });

    test('a missing column is reported for the whole file', () {
      final parsed = parseBooksCsv('title,author\nX,Y\n');
      expect(parsed.fileProblem, contains('department'));
      expect(parsed.rows, isEmpty);
    });
  });

  group('Papers CSV', () {
    const files = {'ict2010-2023.pdf', 'eee2021-2024.pdf'};

    test('each row must name a picked PDF exactly once', () {
      final parsed = parsePapersCsv('$kPaperCsvHeader\n'
          'ict2010-2023.pdf,ICT,ICT 2010,Programming in C,2023,exam\n'
          'missing.pdf,ICT,ICT 2010,Programming in C,2022,exam\n'
          'ict2010-2023.pdf,ICT,ICT 2010,Programming in C,2023,exam\n'
          'eee2021-2024.pdf,Engineering,EEE 2021,Electric Circuits,2024,quiz\n', files);
      expect(parsed.rows[0].isOk, isTrue);
      expect(parsed.rows[0].value!.title, 'ICT 2010 Programming in C examination 2023');
      expect(parsed.rows[0].value!.toRow('x.pdf')['type'], 'past_paper');
      expect(parsed.rows[1].problem, contains('no picked PDF'));
      expect(parsed.rows[2].problem, contains('twice'));
      expect(parsed.rows[3].problem, contains('exam, test or notes'));
    });

    test('a test paper is stored as a test paper', () {
      final parsed = parsePapersCsv('$kPaperCsvHeader\neee2021-2024.pdf,Engineering,EEE 2021,Electric Circuits,2024,test\n', files);
      expect(parsed.rows.single.value!.toRow('p.pdf')['type'], 'test_paper');
    });

    test('lecture notes are stored as lecture notes, with their topic in the title', () {
      final parsed = parsePapersCsv('$kPaperCsvHeader\neee2021-2024.pdf,Engineering,EEE 2021,Electric Circuits,2024,notes\n', files);
      final notes = parsed.rows.single.value!;
      expect(notes.toRow('n.pdf')['type'], 'lecture_notes');
      expect(notes.title, 'EEE 2021 Electric Circuits lecture notes 2024');
      const withTopic = PaperDraft(
          department: 'ICT', courseCode: 'ICT 2010', courseTitle: 'Programming in C',
          academicYear: 2024, kind: PaperKind.notes, topic: 'Week 3: Pointers');
      expect(withTopic.title, 'ICT 2010 Programming in C lecture notes 2024: Week 3: Pointers');
    });

    test('a year out of range is refused', () {
      final parsed = parsePapersCsv('$kPaperCsvHeader\neee2021-2024.pdf,Engineering,EEE 2021,Electric Circuits,1850,test\n', files);
      expect(parsed.rows.single.problem, contains('academic year'));
    });
  });

  group('Accounts and catalogue rows', () {
    test('account status is read and only active counts as active', () {
      Profile p(String status) => Profile.fromMap({'id': 'x', 'full_name': 'A B', 'role': 'student', 'status': status});
      expect(p('pending').isActive, isFalse);
      expect(p('suspended').status, AccountStatus.suspended);
      expect(p('active').isActive, isTrue);
      expect(p('something new').status, AccountStatus.pending);
    });

    test('an invited account that has not chosen a password is flagged', () {
      final p = Profile.fromMap({'id': 'x', 'full_name': 'A', 'role': 'librarian', 'status': 'active', 'must_set_password': true});
      expect(p.mustSetPassword, isTrue);
      expect(p.role, UserRole.librarian);
    });

    test('a library book has no year and no course code', () {
      final r = Resource.fromMap({
        'id': 'b', 'title': 'Sample: Clean Code', 'type': 'book', 'department': 'ICT',
        'course_code': null, 'academic_year': null, 'is_physical': true,
        'total_copies': 2, 'available_copies': 0, 'author': 'Robert C. Martin', 'is_sample': true,
      });
      expect(r.type, ResourceType.book);
      expect(r.academicYear, isNull);
      expect(r.courseCode, '');
      expect(r.isSample, isTrue);
      expect(r.canBeBorrowed, isFalse);
    });

    test('a retired book cannot be borrowed even with copies on the shelf', () {
      final r = Resource.fromMap({
        'id': 'b', 'title': 'Old', 'type': 'book', 'department': 'ICT', 'is_physical': true,
        'total_copies': 2, 'available_copies': 2, 'author': 'X', 'retired_at': '2026-10-01T10:00:00Z',
      });
      expect(r.isRetired, isTrue);
      expect(r.canBeBorrowed, isFalse);
    });

    test('a past paper knows it has a PDF to study', () {
      final r = Resource.fromMap({
        'id': 'p', 'title': 'Paper', 'type': 'past_paper', 'department': 'ICT', 'course_code': 'ICT 2010',
        'academic_year': 2023, 'file_path': 'ICT/ICT2010/x.PDF',
      });
      expect(r.hasPdf, isTrue);
    });
  });

  group('Recommended books', () {
    LinkDraft link(String url) => LinkDraft(
        title: 'The C Programming Language', department: 'ICT', courseCode: 'ICT 2010',
        academicYear: 2024, url: url, author: 'Kernighan and Ritchie');

    test('a web address is accepted and stored as a book link', () {
      final l = link('https://example.org/c-book');
      expect(l.problems(), isEmpty);
      expect(l.toRow()['type'], 'book_link');
      expect(l.toRow()['external_url'], 'https://example.org/c-book');
      expect(l.toRow()['is_physical'], isFalse);
    });

    test('anything but an http or https address is refused', () {
      for (final bad in ['', 'example.org', 'javascript:alert(1)', 'ftp://example.org/x', 'https://']) {
        expect(link(bad).problems(), isNotEmpty, reason: bad);
      }
    });
  });
}
