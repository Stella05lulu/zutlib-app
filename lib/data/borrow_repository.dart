import '../core/failure.dart';
import '../core/supabase.dart';
import '../models/borrow_request.dart';
import '../models/profile.dart';

const _select = '*, resources(title, course_code, department)';

class StaffOverview {
  const StaffOverview({this.pending = 0, this.collected = 0, this.overdue = 0, this.resources = 0});
  final int pending, collected, overdue, resources;
}

class BorrowRepository {
  const BorrowRepository();

  Future<List<BorrowRequest>> mine() async {
    final id = currentUserId;
    if (id == null) return const [];
    try {
      final rows = await db.from('borrow_requests')
          .select(_select).eq('student_id', id).order('requested_at', ascending: false);
      return (rows as List).map((e) => BorrowRequest.fromMap(e)).toList();
    } catch (e) {
      throw Failure.from(e);
    }
  }

  Future<List<BorrowRequest>> queue({Set<BorrowStatus>? statuses}) async {
    try {
      var q = db.from('borrow_requests').select(_select);
      if (statuses != null && statuses.isNotEmpty) {
        q = q.inFilter('status', statuses.map((s) => s.wire).toList());
      }
      final rows = await q.order('requested_at', ascending: true);
      return (rows as List).map((e) => BorrowRequest.fromMap(e)).toList();
    } catch (e) {
      throw Failure.from(e);
    }
  }

  Future<void> apply({
    required String resourceId,
    required Profile student,
    DateTime? collectionDate,
  }) async {
    try {
      await db.from('borrow_requests').insert({
        'resource_id': resourceId,
        'student_id': student.id,
        'student_name': student.fullName,
        'student_number': student.studentNumber ?? '',
        'programme': student.programme,
        'collection_date': collectionDate?.toIso8601String().substring(0, 10),
      });
    } catch (e) {
      final f = Failure.from(e);
      if (f.message.contains('already exists')) {
        throw const Failure('You already have a live request for this item.');
      }
      throw f;
    }
  }

  Future<void> cancel(String requestId) async {
    try {
      await db.from('borrow_requests')
          .update({'status': 'cancelled', 'cancelled_at': DateTime.now().toIso8601String()})
          .eq('id', requestId);
    } catch (e) {
      throw Failure.from(e);
    }
  }

  /// Staff never write a status directly. The edge function validates the
  /// transition, moves the copy count in the same breath, and writes the
  /// audit record, so a modified client cannot reach a state it should not.
  Future<void> decide({
    required String requestId,
    required String action,
    String? reason,
  }) async {
    try {
      await db.functions.invoke('decide-request', body: {
        'request_id': requestId,
        'action': action,
        if (reason != null) 'reason': reason,
      });
    } catch (e) {
      throw Failure.from(e);
    }
  }

  Future<StaffOverview> overview() async {
    try {
      final rows = await db.rpc('staff_overview');
      final list = rows as List;
      if (list.isEmpty) return const StaffOverview();
      final m = list.first as Map<String, dynamic>;
      return StaffOverview(
        pending: (m['pending'] ?? 0) as int,
        collected: (m['collected'] ?? 0) as int,
        overdue: (m['overdue'] ?? 0) as int,
        resources: (m['resources'] ?? 0) as int,
      );
    } catch (e) {
      throw Failure.from(e);
    }
  }
}
