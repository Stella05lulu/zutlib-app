/// ZUT's three schools, fixed in code. Resources record the department the
/// paper itself names, because shared courses carry a different code in
/// each department.
const kDepartments = ['Business', 'Engineering', 'ICT'];

enum ResourceType { pastPaper, testPaper, lectureNotes, bookLink, book }

extension ResourceTypeX on ResourceType {
  String get wire => switch (this) {
        ResourceType.pastPaper => 'past_paper',
        ResourceType.testPaper => 'test_paper',
        ResourceType.lectureNotes => 'lecture_notes',
        ResourceType.bookLink => 'book_link',
        ResourceType.book => 'book',
      };

  String get label => switch (this) {
        ResourceType.pastPaper => 'Past paper',
        ResourceType.testPaper => 'Test paper',
        ResourceType.lectureNotes => 'Lecture notes',
        ResourceType.bookLink => 'Recommended book',
        ResourceType.book => 'Library book',
      };

  bool get isPaper => this == ResourceType.pastPaper || this == ResourceType.testPaper;

  static ResourceType parse(String v) => switch (v) {
        'test_paper' => ResourceType.testPaper,
        'lecture_notes' => ResourceType.lectureNotes,
        'book_link' => ResourceType.bookLink,
        'book' => ResourceType.book,
        _ => ResourceType.pastPaper,
      };
}

class Resource {
  const Resource({
    required this.id,
    required this.title,
    required this.type,
    required this.department,
    required this.courseCode,
    required this.isPhysical,
    required this.totalCopies,
    required this.availableCopies,
    this.academicYear,
    this.semester,
    this.description,
    this.filePath,
    this.externalUrl,
    this.author,
    this.isbn,
    this.edition,
    this.courseTitle,
    this.isSample = false,
    this.retiredAt,
  });

  final String id;
  final String title;
  final ResourceType type;
  final String department;

  /// Empty for a book with no course.
  final String courseCode;

  /// Null for a book.
  final int? academicYear;
  final int? semester;
  final String? description;
  final String? filePath;
  final String? externalUrl;
  final bool isPhysical;
  final int totalCopies;
  final int availableCopies;
  final String? author;
  final String? isbn;
  final String? edition;
  final String? courseTitle;

  /// Demonstration data, shown with a "Sample" label everywhere.
  final bool isSample;

  /// Set when a book is retired: it leaves the catalogue but its borrowing
  /// history stays.
  final DateTime? retiredAt;

  bool get isRetired => retiredAt != null;
  bool get hasDigitalCopy => filePath != null || externalUrl != null;
  bool get hasPdf => filePath != null && filePath!.toLowerCase().endsWith('.pdf');
  bool get canBeBorrowed => isPhysical && availableCopies > 0 && !isRetired;

  String get availabilityLabel {
    if (!isPhysical) return 'Digital only';
    if (availableCopies == 0) return 'All $totalCopies copies on loan';
    return '$availableCopies of $totalCopies available';
  }

  factory Resource.fromMap(Map<String, dynamic> m) => Resource(
        id: m['id'] as String,
        title: m['title'] as String,
        type: ResourceTypeX.parse(m['type'] as String),
        department: m['department'] as String,
        courseCode: (m['course_code'] ?? '') as String,
        academicYear: m['academic_year'] as int?,
        semester: m['semester'] as int?,
        description: m['description'] as String?,
        filePath: m['file_path'] as String?,
        externalUrl: m['external_url'] as String?,
        isPhysical: (m['is_physical'] ?? false) as bool,
        totalCopies: (m['total_copies'] ?? 0) as int,
        availableCopies: (m['available_copies'] ?? 0) as int,
        author: m['author'] as String?,
        isbn: m['isbn'] as String?,
        edition: m['edition'] as String?,
        courseTitle: m['course_title'] as String?,
        isSample: (m['is_sample'] ?? false) as bool,
        retiredAt: m['retired_at'] == null
            ? null
            : DateTime.parse(m['retired_at'] as String).toLocal(),
      );
}
