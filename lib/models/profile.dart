import 'resource.dart' show kDepartments;

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

/// Where an account stands. Only an active account can use the app; the
/// database enforces this in every policy (0012_accounts_roles_library).
enum AccountStatus { pending, active, rejected, suspended }

extension AccountStatusX on AccountStatus {
  String get wire => name;
  String get label => switch (this) {
        AccountStatus.pending => 'Waiting for approval',
        AccountStatus.active => 'Active',
        AccountStatus.rejected => 'Rejected',
        AccountStatus.suspended => 'Suspended',
      };

  static AccountStatus parse(String? v) => switch (v) {
        'active' => AccountStatus.active,
        'rejected' => AccountStatus.rejected,
        'suspended' => AccountStatus.suspended,
        _ => AccountStatus.pending,
      };
}

/// The three ZUT schools a student can belong to (the same list the
/// catalogue uses).
const kStudentDepartments = kDepartments;

class Profile {
  const Profile({
    required this.id,
    required this.fullName,
    required this.role,
    this.status = AccountStatus.active,
    this.email,
    this.department,
    this.mustSetPassword = false,
    this.createdAt,
  });

  final String id;
  final String fullName;
  final UserRole role;
  final AccountStatus status;
  final String? email;
  final String? department;

  /// True for an invited account that has not chosen a password yet.
  final bool mustSetPassword;
  final DateTime? createdAt;

  bool get isActive => status == AccountStatus.active;

  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.firstLetter();
    return parts.first.firstLetter() + parts.last.firstLetter();
  }

  factory Profile.fromMap(Map<String, dynamic> m) => Profile(
        id: m['id'] as String,
        fullName: (m['full_name'] ?? '') as String,
        role: UserRoleX.parse(m['role'] as String?),
        status: AccountStatusX.parse(m['status'] as String?),
        email: m['email'] as String?,
        department: m['department'] as String?,
        mustSetPassword: (m['must_set_password'] ?? false) as bool,
        createdAt: m['created_at'] == null
            ? null
            : DateTime.parse(m['created_at'] as String).toLocal(),
      );
}

extension on String {
  String firstLetter() => isEmpty ? '' : substring(0, 1).toUpperCase();
}
