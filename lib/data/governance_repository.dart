import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/failure.dart';
import '../core/supabase.dart';
import '../models/resource.dart';
import '../study/progress.dart';
import 'admin_repository.dart' show AuditEntry;

// ------------------------------------------------------------------ models

/// System settings (0018). Read by every active account, changed only by a
/// super admin through admin_set_settings.
class SystemSettings {
  const SystemSettings({
    required this.loanDays,
    required this.maxActiveBorrows,
    required this.registrationOpen,
    this.updatedAt,
  });

  final int loanDays;
  final int maxActiveBorrows;
  final bool registrationOpen;
  final DateTime? updatedAt;

  factory SystemSettings.fromMap(Map<String, dynamic> m) => SystemSettings(
        loanDays: (m['loan_days'] as num?)?.toInt() ?? 14,
        maxActiveBorrows: (m['max_active_borrows'] as num?)?.toInt() ?? 3,
        registrationOpen: (m['registration_open'] ?? true) as bool,
        updatedAt: m['updated_at'] == null ? null : DateTime.parse(m['updated_at'] as String).toLocal(),
      );
}

class Announcement {
  const Announcement({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    this.department,
    this.endsOn,
    this.isSample = false,
  });

  final String id;
  final String title;
  final String body;
  final String? department;
  final DateTime? endsOn;
  final DateTime createdAt;
  final bool isSample;

  /// Ended announcements stay visible to administrators only.
  bool get hasEnded {
    final now = DateTime.now();
    return endsOn != null && endsOn!.isBefore(DateTime(now.year, now.month, now.day));
  }

  factory Announcement.fromMap(Map<String, dynamic> m) => Announcement(
        id: m['id'] as String,
        title: (m['title'] ?? '') as String,
        body: (m['body'] ?? '') as String,
        department: m['department'] as String?,
        endsOn: m['ends_on'] == null ? null : DateTime.parse(m['ends_on'] as String),
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
        isSample: (m['is_sample'] ?? false) as bool,
      );
}

class AdminBadges {
  const AdminBadges({this.pendingUsers = 0, this.openInvitations = 0, this.overdue = 0});
  final int pendingUsers, openInvitations, overdue;

  factory AdminBadges.fromMap(Map<String, dynamic> m) {
    int n(String k) => (m[k] as num?)?.toInt() ?? 0;
    return AdminBadges(pendingUsers: n('pending_users'), openInvitations: n('open_invitations'), overdue: n('overdue'));
  }
}

/// One bar of the borrowing trend.
class TrendPoint {
  const TrendPoint(this.start, this.count);
  final DateTime start;
  final int count;
}

class PendingPerson {
  const PendingPerson({required this.id, required this.fullName, this.email, this.department, this.createdAt});
  final String id, fullName;
  final String? email, department;
  final DateTime? createdAt;
}

/// Everything on the admin Overview, from admin_dashboard (0021).
class AdminDashboardData {
  const AdminDashboardData({
    required this.monthly,
    required this.totalUsers,
    required this.pending,
    required this.activeBorrows,
    required this.overdue,
    required this.resources,
    required this.trend,
    required this.statuses,
    required this.departments,
    required this.pendingPeople,
    required this.audit,
  });

  final bool monthly;
  final int totalUsers, pending, activeBorrows, overdue, resources;
  final List<TrendPoint> trend;
  final Map<String, int> statuses;
  final List<(String, int)> departments;
  final List<PendingPerson> pendingPeople;
  final List<AuditEntry> audit;

  factory AdminDashboardData.fromMap(Map<String, dynamic> m) {
    final stats = (m['stats'] as Map?)?.cast<String, dynamic>() ?? const {};
    int n(String k) => (stats[k] as num?)?.toInt() ?? 0;
    return AdminDashboardData(
      monthly: m['period'] == 'month',
      totalUsers: n('total_users'),
      pending: n('pending'),
      activeBorrows: n('active_borrows'),
      overdue: n('overdue'),
      resources: n('resources'),
      trend: [
        for (final t in (m['trend'] as List? ?? const []))
          TrendPoint(DateTime.parse((t as Map)['start'] as String), (t['count'] as num).toInt()),
      ],
      statuses: {
        for (final e in ((m['statuses'] as Map?) ?? const {}).entries) e.key as String: (e.value as num).toInt(),
      },
      departments: [
        for (final d in (m['departments'] as List? ?? const []))
          (((d as Map)['department'] ?? 'Other') as String, (d['count'] as num).toInt()),
      ],
      pendingPeople: [
        for (final p in (m['pending_users'] as List? ?? const []))
          PendingPerson(
            id: (p as Map)['id'] as String,
            fullName: (p['full_name'] ?? '') as String,
            email: p['email'] as String?,
            department: p['department'] as String?,
            createdAt: p['created_at'] == null ? null : DateTime.parse(p['created_at'] as String).toLocal(),
          ),
      ],
      audit: [
        for (final a in (m['audit'] as List? ?? const []))
          AuditEntry(
            action: ((a as Map)['action'] ?? '') as String,
            targetId: (a['target_id'] ?? '') as String,
            at: DateTime.parse(a['occurred_at'] as String).toLocal(),
            actorName: a['actor_name'] as String?,
            detail: (a['detail'] as Map?)?.cast<String, dynamic>() ?? const {},
          ),
      ],
    );
  }
}

/// One row on librarian Today.
class TodayItem {
  const TodayItem({required this.id, required this.title, this.studentName, this.date, this.status, this.detail});
  final String id, title;
  final String? studentName, status, detail;
  final DateTime? date;
}

class LibraryToday {
  const LibraryToday({
    required this.waiting,
    required this.waitingCount,
    required this.collections,
    required this.collectionsCount,
    required this.overdue,
    required this.overdueCount,
    required this.lowStock,
    required this.lowStockCount,
  });

  final List<TodayItem> waiting, collections, overdue, lowStock;
  final int waitingCount, collectionsCount, overdueCount, lowStockCount;

  factory LibraryToday.fromMap(Map<String, dynamic> m) {
    DateTime? d(Object? v) => v == null ? null : DateTime.parse(v as String).toLocal();
    List<TodayItem> list(String k, TodayItem Function(Map) f) =>
        [for (final x in (m[k] as List? ?? const [])) f(x as Map)];
    int n(String k) => (m[k] as num?)?.toInt() ?? 0;
    return LibraryToday(
      waiting: list('waiting', (x) => TodayItem(
          id: x['id'] as String, title: (x['title'] ?? '') as String, studentName: x['student_name'] as String?,
          date: d(x['requested_at']), status: x['status'] as String?)),
      waitingCount: n('waiting_count'),
      collections: list('collections', (x) => TodayItem(
          id: x['id'] as String, title: (x['title'] ?? '') as String, studentName: x['student_name'] as String?,
          date: d(x['collection_date']))),
      collectionsCount: n('collections_count'),
      overdue: list('overdue', (x) => TodayItem(
          id: x['id'] as String, title: (x['title'] ?? '') as String, studentName: x['student_name'] as String?,
          date: d(x['due_date']))),
      overdueCount: n('overdue_count'),
      lowStock: list('low_stock', (x) => TodayItem(
          id: x['id'] as String, title: (x['title'] ?? '') as String, detail: x['author'] as String?)),
      lowStockCount: n('low_stock_count'),
    );
  }
}

/// A kit's source (0020). The kit's original source, kept on the kit
/// itself, is shown as one too, with [isMain] set.
class KitSource {
  const KitSource({
    required this.kind,
    required this.label,
    this.id,
    this.filePath,
    this.resourceId,
    this.youtubeUrl,
    this.body,
    this.bytes = 0,
    this.isMain = false,
  });

  /// 'upload', 'library', 'youtube' or 'text'.
  final String kind;
  final String label;
  final String? id;
  final String? filePath;
  final String? resourceId;
  final String? youtubeUrl;
  final String? body;
  final int bytes;
  final bool isMain;

  String get kindLabel => switch (kind) {
        'upload' => 'Uploaded PDF',
        'library' => 'Library PDF',
        'youtube' => 'YouTube video',
        _ => 'Typed text',
      };

  factory KitSource.fromMap(Map<String, dynamic> m) => KitSource(
        id: m['id'] as String?,
        kind: (m['kind'] ?? 'text') as String,
        label: (m['label'] ?? '') as String,
        filePath: m['file_path'] as String?,
        resourceId: m['resource_id'] as String?,
        youtubeUrl: m['youtube_url'] as String?,
        body: m['body'] as String?,
        bytes: (m['file_bytes'] as num?)?.toInt() ?? 0,
      );
}

/// What View as returns (0021). Read only; private study data is never in it.
class ViewAsData {
  const ViewAsData(this.raw);
  final Map<String, dynamic> raw;

  Map<String, dynamic> get profile => (raw['profile'] as Map?)?.cast<String, dynamic>() ?? const {};
  String get name => (profile['full_name'] ?? '') as String;
  String get role => (profile['role'] ?? 'student') as String;
  List<Map<String, dynamic>> list(String key) =>
      [for (final x in (raw[key] as List? ?? const [])) (x as Map).cast<String, dynamic>()];
  LibraryToday? get library =>
      raw['library'] is Map ? LibraryToday.fromMap((raw['library'] as Map).cast<String, dynamic>()) : null;
}

// ------------------------------------------------------------------ repository

/// Settings, announcements, saved items, dashboards, View as and kit
/// sources. Every rule is enforced by the database (0018 to 0021); this only
/// reads and asks.
class GovernanceRepository {
  const GovernanceRepository();

  static const kitMaxSources = 10; // 0022_bigger_kits.sql
  static const kitMaxBytes = 30 * 1024 * 1024;

  static Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on PostgrestException catch (e) {
      if (e.code == '22023' || e.code == '42501' || e.code == 'P0002' || e.code == '23514' || e.code == '54000') {
        throw Failure(e.message);
      }
      throw Failure.from(e);
    } catch (e) {
      if (e is Failure) rethrow;
      throw Failure.from(e);
    }
  }

  static Map<String, dynamic> _map(Object? v) => (v as Map).cast<String, dynamic>();

  // ------------------------------------------------------------- settings
  Future<SystemSettings> settings() => _guard(() async {
        final row = await db.from('settings').select().maybeSingle();
        return row == null
            ? const SystemSettings(loanDays: 14, maxActiveBorrows: 3, registrationOpen: true)
            : SystemSettings.fromMap(row);
      });

  Future<SystemSettings> saveSettings({
    required int loanDays,
    required int maxActiveBorrows,
    required bool registrationOpen,
    String? reason,
  }) =>
      _guard(() async {
        final row = await db.rpc('admin_set_settings', params: {
          'p_loan_days': loanDays,
          'p_max_active_borrows': maxActiveBorrows,
          'p_registration_open': registrationOpen,
          'p_reason': reason,
        });
        return SystemSettings.fromMap(_map(row is List ? row.first : row));
      });

  /// Asked by the sign-up screen before anyone is signed in.
  Future<bool> registrationOpen() async {
    try {
      return (await db.rpc('registration_open')) != false;
    } catch (_) {
      // If the question cannot be asked, let the sign-up itself decide.
      return true;
    }
  }

  // ------------------------------------------------------------- announcements
  Future<List<Announcement>> announcements({int limit = 50}) => _guard(() async {
        final rows = await db.from('announcements').select().order('created_at', ascending: false).limit(limit);
        return [for (final r in rows) Announcement.fromMap(r)];
      });

  Future<void> saveAnnouncement({
    String? id,
    required String title,
    required String body,
    String? department,
    DateTime? endsOn,
  }) =>
      _guard(() async {
        await db.rpc('admin_save_announcement', params: {
          'p_id': id,
          'p_title': title.trim(),
          'p_body': body.trim(),
          'p_department': department,
          'p_ends_on': endsOn == null ? null : _isoDate(endsOn),
        });
      });

  Future<void> removeAnnouncement(String id) =>
      _guard(() async => db.rpc('admin_remove_announcement', params: {'p_id': id}));

  // ------------------------------------------------------------- saved
  Future<List<Resource>> saved() => _guard(() async {
        final rows = await db
            .from('saved_resources')
            .select('created_at, resource:resources(*)')
            .order('created_at', ascending: false)
            .limit(500);
        return [
          for (final r in rows)
            if (r['resource'] is Map && (r['resource'] as Map)['retired_at'] == null)
              Resource.fromMap(_map(r['resource'])),
        ];
      });

  Future<void> save(String resourceId) => _guard(() async {
        try {
          await db.from('saved_resources').insert({'resource_id': resourceId});
        } on PostgrestException catch (e) {
          if (e.code != '23505') rethrow; // Already saved.
        }
      });

  Future<void> unsave(String resourceId) =>
      _guard(() async => db.from('saved_resources').delete().eq('resource_id', resourceId));

  /// Newest catalogue items, for "Recently added" on Home.
  Future<List<Resource>> recent({int limit = 12}) => _guard(() async {
        final rows = await db
            .from('resources')
            .select()
            .isFilter('retired_at', null)
            .order('created_at', ascending: false)
            .limit(limit);
        return [for (final r in rows) Resource.fromMap(r)];
      });

  // ------------------------------------------------------------- dashboards
  Future<AdminBadges> badges() => _guard(() async => AdminBadges.fromMap(_map(await db.rpc('admin_badges'))));

  Future<AdminDashboardData> dashboard({bool monthly = false}) => _guard(() async =>
      AdminDashboardData.fromMap(_map(await db.rpc('admin_dashboard', params: {'p_period': monthly ? 'month' : 'week'}))));

  Future<LibraryToday> today() => _guard(() async => LibraryToday.fromMap(_map(await db.rpc('librarian_today'))));

  // ------------------------------------------------------------- audit log
  /// [category] is an action prefix such as 'admin.' or 'borrow.'; [search]
  /// matches the action name.
  Future<List<AuditEntry>> audit({String? category, String search = '', int limit = 200}) => _guard(() async {
        var q = db
            .from('audit_entries')
            .select('action,target_id,detail,occurred_at,actor:profiles!audit_entries_actor_id_fkey(full_name)');
        if (category != null) q = q.like('action', '$category%');
        final s = search.trim().replaceAll(RegExp(r'[,()%*]'), ' ').trim();
        if (s.isNotEmpty) q = q.ilike('action', '%${s.replaceAll(' ', '_')}%');
        final rows = await q.order('occurred_at', ascending: false).limit(limit);
        return [for (final r in rows) AuditEntry.fromMap(r)];
      });

  /// (label, when) for every audit entry of the last seven days, for the
  /// activity chart and breakdown.
  Future<List<(String, DateTime)>> auditWeek() => _guard(() async {
        final since = DateTime.now().toUtc().subtract(const Duration(days: 7)).toIso8601String();
        final rows = await db
            .from('audit_entries')
            .select('action,occurred_at')
            .gte('occurred_at', since)
            .order('occurred_at', ascending: false)
            .limit(2000);
        return [
          for (final r in rows)
            (
              AuditEntry(action: (r['action'] ?? '') as String, targetId: '', at: DateTime.now()).label,
              DateTime.parse(r['occurred_at'] as String).toLocal(),
            ),
        ];
      });

  // ------------------------------------------------------------- view as
  Future<ViewAsData> viewAsStart(String userId) =>
      _guard(() async => ViewAsData(_map(await db.rpc('view_as_start', params: {'p_target': userId}))));

  Future<ViewAsData> viewAsData(String userId) =>
      _guard(() async => ViewAsData(_map(await db.rpc('view_as_data', params: {'p_target': userId}))));

  Future<void> viewAsEnd(String userId) => _guard(() async => db.rpc('view_as_end', params: {'p_target': userId}));

  // ------------------------------------------------------------- kit sources
  Future<List<KitSource>> kitSources(String noteId) => _guard(() async {
        final rows = await db
            .from('study_note_sources')
            .select('id,kind,label,file_path,resource_id,youtube_url,body,file_bytes')
            .eq('note_id', noteId)
            .order('position');
        return [for (final r in rows) KitSource.fromMap(r)];
      });

  Future<void> addTextSource(String noteId, {required String label, required String body}) =>
      _guard(() async => db.from('study_note_sources').insert({
            'note_id': noteId, 'kind': 'text', 'label': label.trim(), 'body': body.trim(),
          }));

  Future<void> addVideoSource(String noteId, String youtubeUrl) =>
      _guard(() async => db.from('study_note_sources').insert({
            'note_id': noteId, 'kind': 'youtube', 'label': 'YouTube video', 'youtube_url': youtubeUrl,
          }));

  Future<void> addLibrarySource(String noteId, Resource r) =>
      _guard(() async => db.from('study_note_sources').insert({
            'note_id': noteId, 'kind': 'library', 'label': r.title.length > 120 ? r.title.substring(0, 120) : r.title,
            'resource_id': r.id,
          }));

  /// Uploads to the student's own folder, then records the source. The
  /// database checks the folder, the count and the 30 MB total.
  Future<void> addUploadSource(String noteId, {required Uint8List bytes, required String fileName}) =>
      _guard(() async {
        final uid = currentUserId;
        if (uid == null) throw const Failure('Sign in again.');
        if (bytes.length < 5 || String.fromCharCodes(bytes.sublist(0, 5)) != '%PDF-') {
          throw const Failure('That file is not a PDF.');
        }
        final safe = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
        final stem = (safe.toLowerCase().endsWith('.pdf') ? safe.substring(0, safe.length - 4) : safe);
        final path = '$uid/${DateTime.now().millisecondsSinceEpoch}_${stem.length > 80 ? stem.substring(0, 80) : stem}.pdf';
        await db.storage.from('study-files').uploadBinary(path, bytes,
            fileOptions: const FileOptions(contentType: 'application/pdf'));
        try {
          final label = fileName.length > 120 ? fileName.substring(0, 120) : fileName;
          await db.from('study_note_sources').insert({
            'note_id': noteId, 'kind': 'upload', 'label': label, 'file_path': path, 'file_name': label,
          });
        } catch (e) {
          try {
            await db.storage.from('study-files').remove([path]);
          } catch (_) {
            // The source was not added; the stray file is in the student's own folder.
          }
          rethrow;
        }
      });

  /// A short-lived link to an uploaded source PDF (the student's own folder).
  Future<String> sourcePdfUrl(KitSource s) =>
      _guard(() async => db.storage.from('study-files').createSignedUrl(s.filePath!, 300));

  Future<void> removeSource(String noteId, KitSource s) => _guard(() async {
        if (s.isMain) {
          await db.rpc('study_remove_main_source', params: {'p_note': noteId});
          return;
        }
        await db.from('study_note_sources').delete().eq('id', s.id!);
        if (s.kind == 'upload' && s.filePath != null) {
          try {
            await db.storage.from('study-files').remove([s.filePath!]);
          } catch (_) {
            // The source is gone; the file stays in the student's own folder.
          }
        }
      });
}

/// A student's own attempts and the questions in them, for My progress.
class ProgressData {
  const ProgressData({required this.attempts, required this.questions, required this.kits});
  final List<AttemptRecord> attempts;
  final Map<String, QuestionInfo> questions;

  /// Kit id to its title and course code.
  final Map<String, (String, String?)> kits;
}

extension ProgressFetch on GovernanceRepository {
  /// Everything is the student's own: row level security returns nothing else.
  Future<ProgressData> progress() => GovernanceRepository._guard(() async {
        final loaded = await Future.wait<List<Map<String, dynamic>>>([
          db.from('study_notes').select('id,title,course_code'),
          db.from('study_tests').select('id,note_id'),
          db.from('study_quizzes').select('id,note_id'),
          db.from('study_test_attempts').select('test_id,score,total,answers,created_at')
              .order('created_at', ascending: false).limit(400),
          db.from('study_quiz_attempts').select('quiz_id,score,total,answers,created_at')
              .order('created_at', ascending: false).limit(400),
        ]);
        final kits = {
          for (final n in loaded[0]) n['id'] as String: ((n['title'] ?? '') as String, n['course_code'] as String?),
        };
        final testNote = {for (final t in loaded[1]) t['id'] as String: t['note_id'] as String?};
        final quizNote = {for (final q in loaded[2]) q['id'] as String: q['note_id'] as String?};

        AttemptRecord record(Map<String, dynamic> r, String? noteId) => AttemptRecord(
              at: DateTime.parse(r['created_at'] as String).toLocal(),
              score: (r['score'] as num).toInt(),
              total: (r['total'] as num).toInt(),
              answers: {
                for (final e in ((r['answers'] as Map?) ?? const {}).entries)
                  if (e.value is num) e.key as String: (e.value as num).toInt(),
              },
              noteId: noteId,
              courseCode: noteId == null ? null : kits[noteId]?.$2,
            );
        final attempts = [
          for (final r in loaded[3]) record(r, testNote[r['test_id']]),
          for (final r in loaded[4]) record(r, quizNote[r['quiz_id']]),
        ];

        final ids = {for (final a in attempts) ...a.answers.keys}.toList();
        final questions = <String, QuestionInfo>{};
        for (var i = 0; i < ids.length; i += 150) {
          final chunk = ids.sublist(i, i + 150 > ids.length ? ids.length : i + 150);
          final rows = await db.from('study_quiz_questions').select('id,prompt,correct_index,quiz_id').inFilter('id', chunk);
          for (final q in rows) {
            questions[q['id'] as String] = QuestionInfo(
              id: q['id'] as String,
              prompt: (q['prompt'] ?? '') as String,
              correctIndex: (q['correct_index'] as num).toInt(),
              noteId: quizNote[q['quiz_id']],
            );
          }
        }
        return ProgressData(attempts: attempts, questions: questions, kits: kits);
      });
}

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

const governanceRepo = GovernanceRepository();
