enum UserRole { student, librarian, admin }

extension UserRoleX on UserRole {
  String get wire => name;
  String get label => switch (this) {
        UserRole.student => 'Student',
        UserRole.librarian => 'Librarian',
        UserRole.admin => 'Administrator',
      };
  bool get isStaff => this != UserRole.student;

  static UserRole parse(String? v) => switch (v) {
        'librarian' => UserRole.librarian,
        'admin' => UserRole.admin,
        _ => UserRole.student,
      };
}

class Profile {
  const Profile({
    required this.id,
    required this.fullName,
    required this.surname,
    required this.role,
    this.studentNumber,
    this.programme,
    this.department,
  });

  final String id;
  final String fullName;
  final String surname;
  final UserRole role;
  final String? studentNumber;
  final String? programme;
  final String? department;

  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.firstLetter();
    return parts.first.firstLetter() + parts.last.firstLetter();
  }

  factory Profile.fromMap(Map<String, dynamic> m) => Profile(
        id: m['id'] as String,
        fullName: (m['full_name'] ?? '') as String,
        surname: (m['surname'] ?? '') as String,
        role: UserRoleX.parse(m['role'] as String?),
        studentNumber: m['student_number'] as String?,
        programme: m['programme'] as String?,
        department: m['department'] as String?,
      );
}

extension on String {
  String firstLetter() => isEmpty ? '' : substring(0, 1).toUpperCase();
}
