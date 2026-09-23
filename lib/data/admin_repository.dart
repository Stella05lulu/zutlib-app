import 'dart:convert';
import '../core/failure.dart';
import '../core/supabase.dart';
import '../models/profile.dart';

class RollEntry {
  const RollEntry({
    required this.studentNumber,
    required this.surname,
    required this.programme,
    required this.department,
    required this.intakeYear,
    required this.claimed,
    this.firstName,
  });

  final String studentNumber, surname, programme, department;
  final String? firstName;
  final int intakeYear;
  final bool claimed;

  factory RollEntry.fromMap(Map<String, dynamic> m) => RollEntry(
        studentNumber: m['student_number'] as String,
        surname: m['surname'] as String,
        firstName: m['first_name'] as String?,
        programme: m['programme'] as String,
        department: m['department'] as String,
        intakeYear: m['intake_year'] as int,
        claimed: (m['claimed'] ?? false) as bool,
      );
}

class AdminRepository {
  const AdminRepository();

  Future<List<RollEntry>> roll({String? search}) async {
    try {
      var q = db.from('roll').select();
      if (search != null && search.trim().isNotEmpty) {
        final s = search.trim();
        q = q.or('student_number.ilike.%$s%,surname.ilike.%$s%');
      }
      final rows = await q.order('student_number').limit(200);
      return (rows as List).map((e) => RollEntry.fromMap(e)).toList();
    } catch (e) {
      throw Failure.from(e);
    }
  }

  /// Import is additive and idempotent: re-importing a roll updates the
  /// details of existing records without disturbing the claimed flag.
  Future<int> importRoll(String csv) async {
    final lines = const LineSplitter().convert(csv).where((l) => l.trim().isNotEmpty).toList();
    if (lines.length < 2) throw const Failure('That file has no rows under its header.');

    final header = lines.first.split(',').map((h) => h.trim().toLowerCase()).toList();
    int col(String name) {
      final i = header.indexOf(name);
      if (i < 0) throw Failure('The file is missing a "$name" column.');
      return i;
    }

    final iNum = col('student_number');
    final iSur = col('surname');
    final iProg = col('programme');
    final iDept = col('department');
    final iYear = col('intake_year');
    final iFirst = header.indexOf('first_name');

    final payload = <Map<String, dynamic>>[];
    for (var i = 1; i < lines.length; i++) {
      final cells = lines[i].split(',');
      if (cells.length < header.length) continue;
      payload.add({
        'student_number': cells[iNum].trim(),
        'surname': cells[iSur].trim(),
        if (iFirst >= 0) 'first_name': cells[iFirst].trim(),
        'programme': cells[iProg].trim(),
        'department': cells[iDept].trim(),
        'intake_year': int.tryParse(cells[iYear].trim()) ?? DateTime.now().year,
      });
    }
    if (payload.isEmpty) throw const Failure('No usable rows were found in that file.');

    try {
      await db.from('roll').upsert(payload, onConflict: 'student_number', ignoreDuplicates: false);
      return payload.length;
    } catch (e) {
      throw Failure.from(e);
    }
  }

  Future<List<Profile>> users() async {
    try {
      final rows = await db.from('profiles').select().order('created_at', ascending: false);
      return (rows as List).map((e) => Profile.fromMap(e)).toList();
    } catch (e) {
      throw Failure.from(e);
    }
  }

  Future<void> setRole(String userId, UserRole role) async {
    try {
      await db.from('profiles').update({'role': role.wire}).eq('id', userId);
    } catch (e) {
      throw Failure.from(e);
    }
  }
}
