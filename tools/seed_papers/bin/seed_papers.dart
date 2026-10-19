// seed_papers.dart
//
// One-off loader: takes PDFs from seed/papers/ plus metadata from
// seed/papers/papers.csv, uploads each PDF to the "resources" storage
// bucket, and inserts one matching row into public.resources.
//
// This talks to Supabase directly over plain HTTP (PostgREST for the
// table, the Storage REST API for the file), using the project's
// sb_secret_ key. That key bypasses row level security entirely, so
// this script must never ship with the app and must never be run by
// anyone but an administrator from their own machine.
//
// Usage (run from this folder, tools/seed_papers/):
//   dart pub get
//   dart run bin/seed_papers.dart --dry-run
//   dart run bin/seed_papers.dart --limit 3
//   dart run bin/seed_papers.dart

import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:http/http.dart' as http;

// ---------------------------------------------------------------------------
// Facts about public.resources, read from supabase/migrations/0001_schema.sql
// and lib/models/resource.dart — not guessed.
// ---------------------------------------------------------------------------

/// resource_type enum values (0001_schema.sql).
const kResourceTypes = {'past_paper', 'test_paper', 'lecture_notes', 'book_link'};

/// Departments the app's upload form offers (lib/models/resource.dart).
const kDepartments = {'Business', 'Engineering', 'ICT'};

/// Private storage bucket for resource files (0006_storage.sql).
const kBucket = 'resources';

/// Columns papers.csv must have. "filename" identifies which PDF the row
/// describes; it is not itself resource metadata.
const kRequiredColumns = [
  'filename', 'title', 'type', 'department', 'course_code', 'academic_year',
];
const kOptionalColumns = ['semester', 'description'];

void main(List<String> args) async {
  final dryRun = args.contains('--dry-run');
  final limit = _readLimit(args);

  final toolDir = File(Platform.script.toFilePath()).parent.parent;
  final repoRoot = toolDir.parent.parent;
  final papersDir = Directory('${repoRoot.path}/seed/papers');
  final csvFile = File('${papersDir.path}/papers.csv');
  final envFile = File('${toolDir.path}/.env');

  if (!envFile.existsSync()) {
    stderr.writeln('Missing ${envFile.path}. Copy .env.example and fill it in.');
    exitCode = 1;
    return;
  }
  if (!csvFile.existsSync()) {
    stderr.writeln('Missing ${csvFile.path}.');
    exitCode = 1;
    return;
  }

  final env = _loadEnv(envFile);
  final supabaseUrl = env['SUPABASE_URL'];
  final secretKey = env['SUPABASE_SECRET_KEY'];
  if (supabaseUrl == null || supabaseUrl.isEmpty ||
      secretKey == null || secretKey.isEmpty) {
    stderr.writeln('SUPABASE_URL and SUPABASE_SECRET_KEY must both be set in ${envFile.path}.');
    exitCode = 1;
    return;
  }

  final client = _SupabaseRest(baseUrl: supabaseUrl, secretKey: secretKey);

  // Fail fast and clearly if the key does not work, rather than failing
  // partway through a batch of uploads.
  final authCheck = await client.checkAuth();
  if (authCheck != null) {
    stderr.writeln('Supabase rejected the key: $authCheck');
    stderr.writeln('Not retrying with a different key or workaround. Fix the key and re-run.');
    exitCode = 1;
    return;
  }

  final rows = _parseCsv(csvFile.readAsStringSync());
  final pdfNames = papersDir
      .listSync()
      .whereType<File>()
      .map((f) => f.uri.pathSegments.last)
      .where((n) => n.toLowerCase().endsWith('.pdf'))
      .toSet();

  final added = <String>[];
  final skipped = <String, String>{};
  final failed = <String, String>{};

  // Rows in the CSV with no matching PDF on disk.
  for (final row in rows) {
    final filename = (row['filename'] ?? '').trim();
    if (filename.isNotEmpty && !pdfNames.contains(filename)) {
      skipped[filename] = 'listed in papers.csv but file not found in seed/papers/';
    }
  }

  // PDFs on disk with no matching CSV row.
  final describedFiles = rows.map((r) => (r['filename'] ?? '').trim()).toSet();
  for (final name in pdfNames) {
    if (!describedFiles.contains(name)) {
      skipped[name] = 'no row for this file in papers.csv';
    }
  }

  // Cache of storage listings, one entry per department/course_code folder,
  // so a 40-row CSV does not issue 40 separate list calls.
  final folderCache = <String, Set<String>>{};
  Future<Set<String>> namesInFolder(String folder) async =>
      folderCache[folder] ??= await client.listFolder(kBucket, folder);

  var attempted = 0;
  for (final row in rows) {
    final filename = (row['filename'] ?? '').trim();
    if (filename.isEmpty || !pdfNames.contains(filename)) continue; // already reported above

    final v = _validateRow(row);
    if (v.error != null) {
      skipped[filename] = v.error!;
      continue;
    }
    final meta = v.value!;

    final safeName = filename.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final folder = '${meta.department}/${meta.courseCode}';
    final namesAlreadyThere = await namesInFolder(folder);
    final alreadyThere = namesAlreadyThere.any((name) => name.endsWith('_$safeName'));
    if (alreadyThere) {
      skipped[filename] = 'already uploaded (matching file already in storage)';
      continue;
    }

    if (limit != null && attempted >= limit) {
      skipped[filename] = 'limit reached (not attempted this run)';
      continue;
    }
    attempted++;

    if (dryRun) {
      added.add('$filename -> would upload to $folder/<timestamp>_$safeName '
          'and insert "${meta.title}"');
      continue;
    }

    final file = File('${papersDir.path}/$filename');
    final bytes = await file.readAsBytes();
    final path = '$folder/${DateTime.now().millisecondsSinceEpoch}_$safeName';

    try {
      await client.uploadFile(kBucket, path, bytes);
    } catch (e) {
      failed[filename] = 'upload failed: $e';
      continue;
    }

    try {
      await client.insertResource({
        'title': meta.title,
        'type': meta.type,
        'department': meta.department,
        'course_code': meta.courseCode,
        'academic_year': meta.academicYear,
        'semester': meta.semester,
        'description': meta.description,
        'file_path': path,
        'is_physical': false,
        'total_copies': 0,
        'available_copies': 0,
      });
      added.add('$filename -> "${meta.title}" ($path)');
    } catch (e) {
      // Mirror ResourceRepository.upload(): a row that was refused must
      // not leave an orphaned file behind.
      try {
        await client.deleteFile(kBucket, path);
      } catch (_) {}
      failed[filename] = 'database insert failed: $e';
    }
  }

  _printSummary(dryRun: dryRun, added: added, skipped: skipped, failed: failed);
}

// ---------------------------------------------------------------------------
// CSV row validation
// ---------------------------------------------------------------------------

class _ResourceMeta {
  _ResourceMeta({
    required this.title,
    required this.type,
    required this.department,
    required this.courseCode,
    required this.academicYear,
    this.semester,
    this.description,
  });
  final String title;
  final String type;
  final String department;
  final String courseCode;
  final int academicYear;
  final int? semester;
  final String? description;
}

class _ValidationResult {
  _ValidationResult.ok(this.value) : error = null;
  _ValidationResult.err(this.error) : value = null;
  final _ResourceMeta? value;
  final String? error;
}

_ValidationResult _validateRow(Map<String, String> row) {
  final title = (row['title'] ?? '').trim();
  if (title.isEmpty) return _ValidationResult.err('missing title');

  final type = (row['type'] ?? '').trim();
  if (!kResourceTypes.contains(type)) {
    return _ValidationResult.err(
        'type "$type" is not one of ${kResourceTypes.join(', ')}');
  }

  final department = (row['department'] ?? '').trim();
  if (!kDepartments.contains(department)) {
    return _ValidationResult.err(
        'department "$department" is not one of ${kDepartments.join(', ')}');
  }

  final courseCode = (row['course_code'] ?? '').trim();
  if (courseCode.isEmpty) return _ValidationResult.err('missing course_code');

  final yearText = (row['academic_year'] ?? '').trim();
  final academicYear = int.tryParse(yearText);
  if (academicYear == null || academicYear < 1990 || academicYear > 2100) {
    return _ValidationResult.err('academic_year "$yearText" is not a year between 1990 and 2100');
  }

  int? semester;
  final semesterText = (row['semester'] ?? '').trim();
  if (semesterText.isNotEmpty) {
    semester = int.tryParse(semesterText);
    if (semester == null || semester < 1 || semester > 3) {
      return _ValidationResult.err('semester "$semesterText" is not 1, 2 or 3');
    }
  }

  final descriptionText = (row['description'] ?? '').trim();

  return _ValidationResult.ok(_ResourceMeta(
    title: title,
    type: type,
    department: department,
    courseCode: courseCode.toUpperCase(), // same transform as ResourceRepository.upload()
    academicYear: academicYear,
    semester: semester,
    description: descriptionText.isEmpty ? null : descriptionText,
  ));
}

// ---------------------------------------------------------------------------
// Supabase REST + Storage, over plain http
// ---------------------------------------------------------------------------

class _SupabaseRest {
  _SupabaseRest({required this.baseUrl, required this.secretKey});
  final String baseUrl;
  final String secretKey;

  Map<String, String> get _headers => {
        'apikey': secretKey,
        'Authorization': 'Bearer $secretKey',
      };

  /// Cheap request that only works with a valid, privileged key.
  /// Returns null on success, or a description of the failure.
  Future<String?> checkAuth() async {
    final res = await http.get(
      Uri.parse('$baseUrl/rest/v1/resources?select=id&limit=1'),
      headers: _headers,
    );
    if (res.statusCode == 200) return null;
    return '${res.statusCode} ${res.body}';
  }

  /// Names of the objects directly inside bucket/folder.
  Future<Set<String>> listFolder(String bucket, String folder) async {
    final res = await http.post(
      Uri.parse('$baseUrl/storage/v1/object/list/$bucket'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({'prefix': '$folder/', 'limit': 1000}),
    );
    if (res.statusCode != 200) {
      throw 'listing $bucket/$folder failed: ${res.statusCode} ${res.body}';
    }
    final list = jsonDecode(res.body) as List;
    return list.map((e) => (e as Map)['name'] as String).toSet();
  }

  Future<void> uploadFile(String bucket, String path, List<int> bytes) async {
    final res = await http.post(
      Uri.parse('$baseUrl/storage/v1/object/$bucket/$path'),
      headers: {..._headers, 'Content-Type': 'application/pdf'},
      body: bytes,
    );
    if (res.statusCode != 200) {
      throw '${res.statusCode} ${res.body}';
    }
  }

  Future<void> deleteFile(String bucket, String path) async {
    await http.delete(
      Uri.parse('$baseUrl/storage/v1/object/$bucket/$path'),
      headers: _headers,
    );
  }

  Future<void> insertResource(Map<String, dynamic> row) async {
    final res = await http.post(
      Uri.parse('$baseUrl/rest/v1/resources'),
      headers: {
        ..._headers,
        'Content-Type': 'application/json',
        'Prefer': 'return=minimal',
      },
      body: jsonEncode(row),
    );
    if (res.statusCode != 201) {
      throw '${res.statusCode} ${res.body}';
    }
  }
}

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------

Map<String, String> _loadEnv(File file) {
  final env = <String, String>{};
  for (final line in file.readAsLinesSync()) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    final i = trimmed.indexOf('=');
    if (i < 0) continue;
    env[trimmed.substring(0, i).trim()] = trimmed.substring(i + 1).trim();
  }
  return env;
}

List<Map<String, String>> _parseCsv(String content) {
  final rows = const CsvToListConverter(eol: '\n', shouldParseNumbers: false)
      .convert(content.replaceAll('\r\n', '\n'));
  if (rows.isEmpty) return [];
  final header = rows.first.map((h) => h.toString().trim()).toList();
  for (final required in kRequiredColumns) {
    if (!header.contains(required)) {
      stderr.writeln('papers.csv is missing the required column "$required".');
      exit(1);
    }
  }
  final out = <Map<String, String>>[];
  for (final r in rows.skip(1)) {
    if (r.every((cell) => cell.toString().trim().isEmpty)) continue; // blank line
    final map = <String, String>{};
    for (var i = 0; i < header.length && i < r.length; i++) {
      map[header[i]] = r[i].toString();
    }
    out.add(map);
  }
  return out;
}

int? _readLimit(List<String> args) {
  final i = args.indexOf('--limit');
  if (i < 0 || i + 1 >= args.length) return null;
  return int.tryParse(args[i + 1]);
}

void _printSummary({
  required bool dryRun,
  required List<String> added,
  required Map<String, String> skipped,
  required Map<String, String> failed,
}) {
  print('');
  print('==== ${dryRun ? 'Dry run ' : ''}summary ====');
  print('Added (${added.length}):');
  for (final line in added) print('  - $line');
  print('Skipped (${skipped.length}):');
  skipped.forEach((file, reason) => print('  - $file: $reason'));
  print('Failed (${failed.length}):');
  failed.forEach((file, reason) => print('  - $file: $reason'));
}
