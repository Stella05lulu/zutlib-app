import '../core/csv.dart';
import '../models/resource.dart' show kDepartments;

/// Reading and checking librarian imports before anything is sent: a CSV
/// of books, and a CSV describing a batch of past paper PDFs. Every row is
/// checked on its own, so one bad row is reported and skipped instead of
/// stopping the whole import. The database checks the same rules again.

/// The departments a book or paper can belong to.
const kLibraryDepartments = kDepartments;

/// One row of an import: either a usable value or the reason it was refused.
class ImportRow<T> {
  const ImportRow.ok(this.line, T this.value) : problem = null;
  const ImportRow.bad(this.line, String this.problem) : value = null;

  /// The line in the file (the header is line 1).
  final int line;
  final T? value;
  final String? problem;

  bool get isOk => value != null;
}

/// Digits only (and a final X); null when empty. Throws FormatException
/// when it cannot be a 10 or 13 digit ISBN.
String? cleanIsbn(String raw) {
  final s = raw.toUpperCase().replaceAll(RegExp(r'[^0-9X]'), '');
  if (s.isEmpty) return null;
  if (!RegExp(r'^([0-9]{9}[0-9X]|[0-9]{13})$').hasMatch(s)) {
    throw const FormatException('ISBN must have 10 or 13 digits');
  }
  return s;
}

class BookDraft {
  const BookDraft({
    required this.title,
    required this.author,
    required this.department,
    required this.totalCopies,
    this.isbn,
    this.courseCode,
    this.edition,
  });

  final String title;
  final String author;
  final String department;
  final int totalCopies;
  final String? isbn;
  final String? courseCode;
  final String? edition;

  /// Problems with this book, or an empty list when it is fine.
  List<String> problems() => [
        if (title.trim().isEmpty) 'title is missing',
        if (title.length > 300) 'title is longer than 300 characters',
        if (author.trim().isEmpty) 'author is missing',
        if (author.length > 200) 'author is longer than 200 characters',
        if (!kLibraryDepartments.contains(department)) 'department must be ICT, Engineering or Business',
        if (totalCopies < 1 || totalCopies > 1000) 'total copies must be from 1 to 1000',
        if ((edition ?? '').length > 40) 'edition is longer than 40 characters',
      ];

  Map<String, dynamic> toRow() => {
        'title': title.trim(),
        'type': 'book',
        'department': department,
        'author': author.trim(),
        'isbn': isbn,
        'course_code': (courseCode ?? '').trim().isEmpty ? null : courseCode!.trim(),
        'edition': (edition ?? '').trim().isEmpty ? null : edition!.trim(),
        'is_physical': true,
        'total_copies': totalCopies,
        'available_copies': totalCopies,
      };
}

/// The header row an import file must have; columns may be in any order.
List<int>? _columns(List<String> header, List<String> required, List<String> optional,
    void Function(String) missing) {
  final h = header.map((c) => c.trim().toLowerCase()).toList();
  final out = <int>[];
  for (final name in [...required, ...optional]) {
    final i = h.indexOf(name);
    if (i < 0 && required.contains(name)) {
      missing(name);
      return null;
    }
    out.add(i);
  }
  return out;
}

const kBookCsvHeader = 'title,author,isbn,department,course_code,edition,total_copies';

/// Reads a books CSV with the header [kBookCsvHeader].
({List<ImportRow<BookDraft>> rows, String? fileProblem}) parseBooksCsv(String text) {
  final table = parseCsv(text);
  if (table.isEmpty) return (rows: const [], fileProblem: 'The file is empty.');
  String? missingColumn;
  final cols = _columns(table.first, ['title', 'author', 'department', 'total_copies'],
      ['isbn', 'course_code', 'edition'], (m) => missingColumn = m);
  if (cols == null) {
    return (rows: const [], fileProblem: 'The file has no "$missingColumn" column. The header must be: $kBookCsvHeader');
  }
  String cell(List<String> r, int i) => i >= 0 && i < r.length ? r[i].trim() : '';

  final rows = <ImportRow<BookDraft>>[];
  for (var n = 1; n < table.length; n++) {
    final r = table[n];
    final line = n + 1;
    final copies = int.tryParse(cell(r, cols[3]));
    if (copies == null) {
      rows.add(ImportRow.bad(line, 'total copies must be a whole number'));
      continue;
    }
    String? isbn;
    try {
      isbn = cleanIsbn(cell(r, cols[4]));
    } on FormatException catch (e) {
      rows.add(ImportRow.bad(line, e.message));
      continue;
    }
    final book = BookDraft(
      title: cell(r, cols[0]),
      author: cell(r, cols[1]),
      department: cell(r, cols[2]),
      totalCopies: copies,
      isbn: isbn,
      courseCode: cell(r, cols[5]),
      edition: cell(r, cols[6]),
    );
    final problems = book.problems();
    rows.add(problems.isEmpty ? ImportRow.ok(line, book) : ImportRow.bad(line, problems.join('; ')));
  }
  return (rows: rows, fileProblem: null);
}

enum PaperKind { exam, test, notes }

extension PaperKindX on PaperKind {
  /// The word used in a title, and in the CSV's paper_type column.
  String get word => switch (this) {
        PaperKind.exam => 'examination',
        PaperKind.test => 'test',
        PaperKind.notes => 'lecture notes',
      };

  String get wire => switch (this) {
        PaperKind.exam => 'past_paper',
        PaperKind.test => 'test_paper',
        PaperKind.notes => 'lecture_notes',
      };
}

class PaperDraft {
  const PaperDraft({
    required this.department,
    required this.courseCode,
    required this.courseTitle,
    required this.academicYear,
    required this.kind,
    this.topic,
    this.fileName,
  });

  final String department;
  final String courseCode;
  final String courseTitle;
  final int academicYear;
  final PaperKind kind;

  /// What a set of lecture notes covers, such as "Week 3: Pointers".
  final String? topic;

  /// The PDF this row describes, in a bulk upload.
  final String? fileName;

  /// The title without a topic.
  String get baseTitle => '${courseCode.trim().toUpperCase()} ${courseTitle.trim()} ${kind.word} $academicYear';

  String get title {
    final t = topic?.trim() ?? '';
    return t.isEmpty ? baseTitle : '$baseTitle: $t';
  }

  /// The topic inside a stored title made by [title], or null when the
  /// title was written some other way.
  String? topicIn(String storedTitle) =>
      storedTitle.startsWith('$baseTitle: ') ? storedTitle.substring(baseTitle.length + 2) : null;

  List<String> problems() => [
        if (!kLibraryDepartments.contains(department)) 'department must be ICT, Engineering or Business',
        if (courseCode.trim().isEmpty) 'course code is missing',
        if (courseCode.length > 20) 'course code is longer than 20 characters',
        if (courseTitle.trim().isEmpty) 'course title is missing',
        if (courseTitle.length > 200) 'course title is longer than 200 characters',
        if (academicYear < 1990 || academicYear > 2100) 'academic year must be between 1990 and 2100',
        if ((topic ?? '').length > 120) 'topic is longer than 120 characters',
      ];

  Map<String, dynamic> toRow(String filePath) => {
        'title': title,
        'type': kind.wire,
        'department': department,
        'course_code': courseCode.trim(),
        'course_title': courseTitle.trim(),
        'academic_year': academicYear,
        'file_path': filePath,
        'is_physical': false,
        'total_copies': 0,
        'available_copies': 0,
      };
}

const kPaperCsvHeader = 'file,department,course_code,course_title,academic_year,paper_type';

/// Reads the CSV that goes with a bulk paper upload. Each row names one of
/// the picked PDFs in [fileNames].
({List<ImportRow<PaperDraft>> rows, String? fileProblem}) parsePapersCsv(
    String text, Set<String> fileNames) {
  final table = parseCsv(text);
  if (table.isEmpty) return (rows: const [], fileProblem: 'The file is empty.');
  String? missingColumn;
  final cols = _columns(
      table.first,
      ['file', 'department', 'course_code', 'course_title', 'academic_year', 'paper_type'],
      const [],
      (m) => missingColumn = m);
  if (cols == null) {
    return (rows: const [], fileProblem: 'The file has no "$missingColumn" column. The header must be: $kPaperCsvHeader');
  }
  String cell(List<String> r, int i) => i < r.length ? r[i].trim() : '';

  final rows = <ImportRow<PaperDraft>>[];
  final seen = <String>{};
  for (var n = 1; n < table.length; n++) {
    final r = table[n];
    final line = n + 1;
    final file = cell(r, cols[0]);
    if (!fileNames.contains(file)) {
      rows.add(ImportRow.bad(line, 'no picked PDF is called "$file"'));
      continue;
    }
    if (!seen.add(file)) {
      rows.add(ImportRow.bad(line, '"$file" is listed twice'));
      continue;
    }
    final year = int.tryParse(cell(r, cols[4]));
    final type = cell(r, cols[5]).toLowerCase();
    if (year == null) {
      rows.add(ImportRow.bad(line, 'academic year must be a number'));
      continue;
    }
    final kind = switch (type) {
      'exam' => PaperKind.exam,
      'test' => PaperKind.test,
      'notes' => PaperKind.notes,
      _ => null,
    };
    if (kind == null) {
      rows.add(ImportRow.bad(line, 'paper type must be exam, test or notes'));
      continue;
    }
    final paper = PaperDraft(
      department: cell(r, cols[1]),
      courseCode: cell(r, cols[2]),
      courseTitle: cell(r, cols[3]),
      academicYear: year,
      kind: kind,
      fileName: file,
    );
    final problems = paper.problems();
    rows.add(problems.isEmpty ? ImportRow.ok(line, paper) : ImportRow.bad(line, problems.join('; ')));
  }
  return (rows: rows, fileProblem: null);
}

/// Why [raw] cannot be a recommended book's link, or null when it can. Only
/// web addresses are allowed, so a link can never run script in the app.
String? linkProblem(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (raw.trim().isEmpty) return 'link is missing';
  if (uri == null || !(uri.isScheme('http') || uri.isScheme('https')) || uri.host.isEmpty) {
    return 'link must be a web address starting with https://';
  }
  if (raw.length > 2000) return 'link is longer than 2000 characters';
  return null;
}

/// A recommended book: a reading-list entry for a course that links to the
/// book online. The library holds no copy, so it cannot be borrowed.
class LinkDraft {
  const LinkDraft({
    required this.title,
    required this.department,
    required this.courseCode,
    required this.academicYear,
    required this.url,
    this.author,
  });

  final String title;
  final String department;
  final String courseCode;
  final int academicYear;
  final String url;
  final String? author;

  List<String> problems() => [
        if (title.trim().isEmpty) 'title is missing',
        if (title.length > 300) 'title is longer than 300 characters',
        if ((author ?? '').length > 200) 'author is longer than 200 characters',
        if (!kLibraryDepartments.contains(department)) 'department must be ICT, Engineering or Business',
        if (courseCode.trim().isEmpty) 'course code is missing',
        if (courseCode.length > 20) 'course code is longer than 20 characters',
        if (academicYear < 1990 || academicYear > 2100) 'academic year must be between 1990 and 2100',
        if (linkProblem(url) case final p?) p,
      ];

  Map<String, dynamic> toRow() => {
        'title': title.trim(),
        'type': 'book_link',
        'department': department,
        'course_code': courseCode.trim(),
        'academic_year': academicYear,
        'author': (author ?? '').trim().isEmpty ? null : author!.trim(),
        'external_url': url.trim(),
        'is_physical': false,
        'total_copies': 0,
        'available_copies': 0,
      };
}
