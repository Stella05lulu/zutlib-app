import 'dart:typed_data';
import '../core/failure.dart';
import '../core/supabase.dart';
import '../models/resource.dart';

class ResourceFilters {
  const ResourceFilters({
    this.query = '',
    this.department,
    this.courseCode,
    this.year,
    this.type,
  });

  final String query;
  final String? department;
  final String? courseCode;
  final int? year;
  final ResourceType? type;

  bool get isEmpty =>
      query.trim().isEmpty &&
      department == null &&
      courseCode == null &&
      year == null &&
      type == null;

  int get activeCount => [
        department, courseCode, year, type,
      ].where((e) => e != null).length;

  ResourceFilters copyWith({
    String? query,
    Object? department = _keep,
    Object? courseCode = _keep,
    Object? year = _keep,
    Object? type = _keep,
  }) =>
      ResourceFilters(
        query: query ?? this.query,
        department: department == _keep ? this.department : department as String?,
        courseCode: courseCode == _keep ? this.courseCode : courseCode as String?,
        year: year == _keep ? this.year : year as int?,
        type: type == _keep ? this.type : type as ResourceType?,
      );

  static const _keep = Object();

  @override
  bool operator ==(Object other) =>
      other is ResourceFilters &&
      other.query == query &&
      other.department == department &&
      other.courseCode == courseCode &&
      other.year == year &&
      other.type == type;

  @override
  int get hashCode => Object.hash(query, department, courseCode, year, type);
}

class Facets {
  const Facets({this.departments = const [], this.courseCodes = const [], this.years = const []});
  final List<String> departments;
  final List<String> courseCodes;
  final List<int> years;
}

class ResourceRepository {
  const ResourceRepository();

  /// Metadata filters and full text search resolve in a single call, and row
  /// level security still applies inside the function.
  Future<List<Resource>> search(ResourceFilters f, {int limit = 50, int offset = 0}) async {
    try {
      final rows = await db.rpc('search_resources', params: {
        'q': f.query.trim().isEmpty ? null : f.query.trim(),
        'p_department': f.department,
        'p_course': f.courseCode,
        'p_year': f.year,
        'p_type': f.type?.wire,
        'p_limit': limit,
        'p_offset': offset,
      });
      return (rows as List)
          .map((e) => Resource.fromMap(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw Failure.from(e);
    }
  }

  /// Course codes and years narrow to [department] when one is chosen.
  Future<Facets> facets({String? department}) async {
    try {
      final rows = await db.rpc('resource_facets',
          params: {'p_department': department});
      final list = rows as List;
      if (list.isEmpty) return const Facets();
      final m = list.first as Map<String, dynamic>;
      return Facets(
        departments: List<String>.from(m['departments'] as List? ?? const []),
        courseCodes: List<String>.from(m['course_codes'] as List? ?? const []),
        years: List<int>.from(m['years'] as List? ?? const []),
      );
    } catch (e) {
      throw Failure.from(e);
    }
  }

  Future<Resource> byId(String id) async {
    try {
      final row = await db.from('resources').select().eq('id', id).single();
      return Resource.fromMap(row);
    } catch (e) {
      throw Failure.from(e);
    }
  }

  /// Files live in a private bucket. A link is minted on demand and expires,
  /// so a URL copied out of one session does not stay valid indefinitely.
  Future<String> signedUrl(String filePath, {int seconds = 300}) async {
    try {
      return await db.storage.from('resources').createSignedUrl(filePath, seconds);
    } catch (e) {
      throw Failure.from(e);
    }
  }

  Future<void> upload({
    required String title,
    required ResourceType type,
    required String department,
    required String courseCode,
    required int academicYear,
    int? semester,
    String? description,
    Uint8List? fileBytes,
    String? fileName,
    String? externalUrl,
    bool isPhysical = false,
    int totalCopies = 0,
  }) async {
    try {
      String? path;
      if (fileBytes != null && fileName != null) {
        final safe = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
        path = '$department/$courseCode/${DateTime.now().millisecondsSinceEpoch}_$safe';
        await db.storage.from('resources').uploadBinary(path, fileBytes);
      }
      await db.from('resources').insert({
        'title': title.trim(),
        'type': type.wire,
        'department': department.trim(),
        'course_code': courseCode.trim().toUpperCase(),
        'academic_year': academicYear,
        'semester': semester,
        'description': description?.trim(),
        'file_path': path,
        'external_url': externalUrl?.trim(),
        'is_physical': isPhysical,
        'total_copies': isPhysical ? totalCopies : 0,
        'available_copies': isPhysical ? totalCopies : 0,
        'uploaded_by': currentUserId,
      });
    } catch (e) {
      throw Failure.from(e);
    }
  }

  Future<void> delete(String id) async {
    try {
      await db.from('resources').delete().eq('id', id);
    } catch (e) {
      throw Failure.from(e);
    }
  }
}
