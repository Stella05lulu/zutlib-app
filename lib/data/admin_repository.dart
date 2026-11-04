import '../core/failure.dart';
import '../core/supabase.dart';
import '../models/profile.dart';
import 'auth_repository.dart' show kLoginCallbackRedirect;

/// Counts for the administrator's dashboard, from admin_overview().
class AdminOverview {
  const AdminOverview({
    required this.pendingStudents,
    required this.activeStudents,
    required this.suspendedAccounts,
    required this.librarians,
    required this.admins,
    required this.books,
    required this.sampleBooks,
    required this.papers,
    required this.samplePapers,
    required this.openRequests,
    required this.overdueRequests,
  });

  final int pendingStudents, activeStudents, suspendedAccounts, librarians, admins;
  final int books, sampleBooks, papers, samplePapers, openRequests, overdueRequests;

  factory AdminOverview.fromMap(Map<String, dynamic> m) {
    int n(String k) => (m[k] as num?)?.toInt() ?? 0;
    return AdminOverview(
      pendingStudents: n('pending_students'),
      activeStudents: n('active_students'),
      suspendedAccounts: n('suspended_accounts'),
      librarians: n('librarians'),
      admins: n('admins'),
      books: n('books'),
      sampleBooks: n('sample_books'),
      papers: n('papers'),
      samplePapers: n('sample_papers'),
      openRequests: n('open_requests'),
      overdueRequests: n('overdue_requests'),
    );
  }
}

/// One line of the audit log.
class AuditEntry {
  const AuditEntry({
    required this.action,
    required this.targetId,
    required this.at,
    this.actorName,
    this.detail = const {},
  });

  final String action;
  final String targetId;
  final DateTime at;
  final String? actorName;
  final Map<String, dynamic> detail;

  /// "admin.approve" -> "Approved", in plain words.
  String get label => switch (action) {
        'admin.approve' => 'Approved an account',
        'admin.reject' => 'Rejected an account',
        'admin.suspend' => 'Suspended an account',
        'admin.reactivate' => 'Reactivated an account',
        'admin.set_role' => 'Changed a role',
        'admin.create' => 'Created an account',
        'admin.test_invite' => 'Sent a test invite',
        'admin.resend_invite' => 'Resent an invite',
        'admin.remove' => 'Removed an account',
        'system.restore_super_admin' => 'Super admin restored from the dashboard',
        _ => action.replaceAll('.', ' ').replaceAll('_', ' '),
      };

  factory AuditEntry.fromMap(Map<String, dynamic> m) {
    final actor = m['actor'];
    return AuditEntry(
      action: (m['action'] ?? '') as String,
      targetId: (m['target_id'] ?? '') as String,
      at: DateTime.parse(m['occurred_at'] as String).toLocal(),
      actorName: actor is Map ? actor['full_name'] as String? : null,
      detail: (m['detail'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }
}

/// What an administrator can do. Reading uses row level security (only an
/// active admin may read every profile and the audit log). Every change goes
/// through the admin-users Edge Function, which checks the caller is an
/// admin and writes the audit log; no profile is ever edited from the app.
class AdminRepository {
  const AdminRepository();

  static const _profileColumns =
      'id,full_name,role,status,email,department,must_set_password,created_at';

  Future<AdminOverview> overview() async {
    try {
      final rows = (await db.rpc('admin_overview')) as List;
      if (rows.isEmpty) throw const Failure('The dashboard returned no figures.');
      return AdminOverview.fromMap(rows.first as Map<String, dynamic>);
    } catch (e) {
      throw Failure.from(e);
    }
  }

  Future<List<Profile>> users({AccountStatus? status, String search = ''}) async {
    try {
      var q = db.from('profiles').select(_profileColumns);
      if (status != null) q = q.eq('status', status.wire);
      final s = search.trim().replaceAll(RegExp(r'[,()%]'), ' ').trim();
      if (s.isNotEmpty) q = q.or('full_name.ilike.%$s%,email.ilike.%$s%');
      final rows = await q.order('created_at', ascending: false).limit(300);
      return [for (final r in rows) Profile.fromMap(r)];
    } catch (e) {
      throw Failure.from(e);
    }
  }

  Future<List<AuditEntry>> audit({int limit = 50}) async {
    try {
      final rows = await db
          .from('audit_entries')
          .select('action,target_id,detail,occurred_at,actor:profiles!audit_entries_actor_id_fkey(full_name)')
          .or('action.like.admin.%,action.like.system.%')
          .order('occurred_at', ascending: false)
          .limit(limit);
      return [for (final r in rows) AuditEntry.fromMap(r)];
    } catch (e) {
      throw Failure.from(e);
    }
  }

  Future<Map<String, dynamic>> _call(Map<String, dynamic> body) async {
    try {
      final res = await db.functions.invoke('admin-users', body: {
        ...body,
        'redirect_to': kLoginCallbackRedirect,
      });
      final data = res.data;
      return data is Map ? data.cast<String, dynamic>() : const {};
    } catch (e) {
      throw Failure.from(e);
    }
  }

  /// Invites a person by email. They choose their own password from the
  /// email; the account is approved with [role] straight away. Returns the
  /// message to show.
  Future<String> createAccount({
    required String email,
    required String fullName,
    required UserRole role,
    String? department,
  }) async {
    final data = await _call({
      'action': 'create',
      'email': email.trim(),
      'full_name': fullName.trim(),
      'role': role.wire,
      if (department != null) 'department': department,
    });
    return (data['message'] ?? 'Invite sent.') as String;
  }

  /// Checks email delivery by sending an invite to [email]. The account it
  /// makes is suspended and can do nothing.
  Future<String> sendTestInvite(String email) async {
    final data = await _call({'action': 'test_invite', 'email': email.trim()});
    return (data['message'] ?? 'Test invite sent.') as String;
  }

  Future<String> resendInvite(String userId) async {
    final data = await _call({'action': 'resend_invite', 'user_id': userId});
    return (data['message'] ?? 'Invite sent again.') as String;
  }

  Future<void> approve(String userId) => _call({'action': 'approve', 'user_id': userId});
  Future<void> reject(String userId) => _call({'action': 'reject', 'user_id': userId});
  Future<void> suspend(String userId) => _call({'action': 'suspend', 'user_id': userId});
  Future<void> reactivate(String userId) => _call({'action': 'reactivate', 'user_id': userId});
  Future<void> setRole(String userId, UserRole role) =>
      _call({'action': 'set_role', 'user_id': userId, 'role': role.wire});

  /// Super admin only. The account is kept (status "removed"), so it can be
  /// restored; [reason] goes into the audit log.
  Future<void> remove(String userId, String reason) =>
      _call({'action': 'remove', 'user_id': userId, 'reason': reason});
}
