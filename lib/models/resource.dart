enum ResourceType { pastPaper, testPaper, lectureNotes, bookLink }

extension ResourceTypeX on ResourceType {
  String get wire => switch (this) {
        ResourceType.pastPaper => 'past_paper',
        ResourceType.testPaper => 'test_paper',
        ResourceType.lectureNotes => 'lecture_notes',
        ResourceType.bookLink => 'book_link',
      };

  String get label => switch (this) {
        ResourceType.pastPaper => 'Past paper',
        ResourceType.testPaper => 'Test paper',
        ResourceType.lectureNotes => 'Lecture notes',
        ResourceType.bookLink => 'Recommended book',
      };

  static ResourceType parse(String v) => switch (v) {
        'test_paper' => ResourceType.testPaper,
        'lecture_notes' => ResourceType.lectureNotes,
        'book_link' => ResourceType.bookLink,
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
    required this.academicYear,
    required this.isPhysical,
    required this.totalCopies,
    required this.availableCopies,
    this.semester,
    this.description,
    this.filePath,
    this.externalUrl,
  });

  final String id;
  final String title;
  final ResourceType type;
  final String department;
  final String courseCode;
  final int academicYear;
  final int? semester;
  final String? description;
  final String? filePath;
  final String? externalUrl;
  final bool isPhysical;
  final int totalCopies;
  final int availableCopies;

  bool get hasDigitalCopy => filePath != null || externalUrl != null;
  bool get canBeBorrowed => isPhysical && availableCopies > 0;

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
        courseCode: m['course_code'] as String,
        academicYear: m['academic_year'] as int,
        semester: m['semester'] as int?,
        description: m['description'] as String?,
        filePath: m['file_path'] as String?,
        externalUrl: m['external_url'] as String?,
        isPhysical: (m['is_physical'] ?? false) as bool,
        totalCopies: (m['total_copies'] ?? 0) as int,
        availableCopies: (m['available_copies'] ?? 0) as int,
      );
}
