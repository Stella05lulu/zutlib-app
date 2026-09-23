// ZutLib — one-off catalogue seed.
//
// Uploads every file listed in scripts/seed/resources_manifest.csv to the
// private "resources" bucket and inserts its catalogue row, so search has
// real past papers to find.
//
// Runs with the SERVICE ROLE key, which bypasses row level security. That
// key must never go in .env (the .env file is bundled inside the app).
// Pass it through the terminal for this one run only.
//
// PowerShell, from the zutlib folder:
//   $env:SUPABASE_SERVICE_ROLE_KEY = "paste-service-role-key"
//   dart run scripts/seed_resources.dart --dry-run     # checks files only
//   dart run scripts/seed_resources.dart               # uploads
//   Remove-Item Env:SUPABASE_SERVICE_ROLE_KEY
//
// Safe to run twice: a row whose file_path already exists is skipped.
// Optional first argument: the resources folder
// (default: ../resouces for zutlib).

import 'dart:convert';
import 'dart:io';

const manifestPath = 'scripts/seed/resources_manifest.csv';
const bucket = 'resources';

Future<void> main(List<String> argv) async {
  final dryRun = argv.contains('--dry-run');
  final positional = argv.where((a) => !a.startsWith('--')).toList();
  final folder =
      positional.isNotEmpty ? positional.first : '../resouces for zutlib';

  final rows = _parseCsv(File(manifestPath).readAsStringSync());
  final header = rows.first;
  final records = [
    for (final r in rows.skip(1))
      if (r.length == header.length) {for (var i = 0; i < r.length; i++) header[i]: r[i]}
  ];
  stdout.writeln('${records.length} resources in manifest.');

  // 1. Every file must exist before anything is uploaded.
  final missing = [
    for (final r in records)
      if (!File('$folder/${r['file']}').existsSync()) r['file']!
  ];
  if (missing.isNotEmpty) {
    stderr.writeln('Missing files:\n  ${missing.join('\n  ')}');
    exit(1);
  }
  stdout.writeln('All files found.');
  if (dryRun) return;

  final url = (Platform.environment['SUPABASE_URL'] ?? _envFileValue('SUPABASE_URL'))
      ?.replaceAll(RegExp(r'/+$'), '');
  final key = Platform.environment['SUPABASE_SERVICE_ROLE_KEY'];
  if (url == null || url.isEmpty) {
    stderr.writeln('SUPABASE_URL not set and not found in .env');
    exit(1);
  }
  if (key == null || key.isEmpty) {
    stderr.writeln('Set SUPABASE_SERVICE_ROLE_KEY in this terminal first.');
    exit(1);
  }

  final client = HttpClient();
  var added = 0, skipped = 0, failed = 0;

  Future<(int, String)> send(String method, Uri uri,
      {Map<String, String> headers = const {}, List<int>? body}) async {
    final req = await client.openUrl(method, uri);
    req.headers.set('apikey', key);
    req.headers.set('Authorization', 'Bearer $key');
    headers.forEach((k, v) => req.headers.set(k, v));
    if (body != null) {
      req.contentLength = body.length;
      req.add(body);
    }
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();
    return (res.statusCode, text);
  }

  for (final r in records) {
    final code = r['course_code']!.replaceAll(' ', '');
    final ext = r['file']!.split('.').last.toLowerCase();
    final objectPath = '${_slug(r['department']!)}/$code/${_slug(r['title']!)}.$ext';
    final label = '${r['course_code']} ${r['academic_year']}  ${r['title']}';

    try {
      // Already catalogued?
      final check = Uri.parse('$url/rest/v1/resources').replace(queryParameters: {
        'select': 'id',
        'file_path': 'eq.$objectPath',
      });
      final (cs, cb) = await send('GET', check);
      if (cs != 200) throw 'lookup $cs $cb';
      if ((jsonDecode(cb) as List).isNotEmpty) {
        skipped++;
        stdout.writeln('skip   $label');
        continue;
      }

      // Upload the file (overwrite a half-finished earlier attempt).
      final bytes = File('$folder/${r['file']}').readAsBytesSync();
      final encoded = objectPath.split('/').map(Uri.encodeComponent).join('/');
      final (us, ub) = await send(
        'POST',
        Uri.parse('$url/storage/v1/object/$bucket/$encoded'),
        headers: {
          'Content-Type': ext == 'pdf' ? 'application/pdf' : 'application/octet-stream',
          'x-upsert': 'true',
        },
        body: bytes,
      );
      if (us != 200 && us != 201) throw 'upload $us $ub';

      // Catalogue row. The database trigger tidies the course code.
      final semester = r['semester']!.trim();
      final description = r['description']!.trim();
      final (is_, ib) = await send(
        'POST',
        Uri.parse('$url/rest/v1/resources'),
        headers: {
          'Content-Type': 'application/json',
          'Prefer': 'return=minimal',
        },
        body: utf8.encode(jsonEncode({
          'title': r['title'],
          'type': r['type'],
          'department': r['department'],
          'course_code': r['course_code'],
          'academic_year': int.parse(r['academic_year']!),
          'semester': semester.isEmpty ? null : int.parse(semester),
          'description': description.isEmpty ? null : description,
          'file_path': objectPath,
          'is_physical': false,
          'total_copies': 0,
          'available_copies': 0,
        })),
      );
      if (is_ != 201 && is_ != 200) throw 'insert $is_ $ib';

      added++;
      stdout.writeln('added  $label');
    } catch (e) {
      failed++;
      stderr.writeln('FAILED $label\n       $e');
    }
  }

  client.close();
  stdout.writeln('\nDone. added $added, skipped $skipped, failed $failed.');
  if (failed > 0) exit(1);
}

/// "Electric Circuits, May 2025 Test II" -> "electric-circuits-may-2025-test-ii"
String _slug(String s) => s
    .toLowerCase()
    .replaceAll('+', 'p')
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-+|-+$'), '');

String? _envFileValue(String name) {
  final f = File('.env');
  if (!f.existsSync()) return null;
  for (final line in f.readAsLinesSync()) {
    final i = line.indexOf('=');
    if (i > 0 && line.substring(0, i).trim() == name) {
      return line.substring(i + 1).trim();
    }
  }
  return null;
}

/// Minimal RFC 4180 reader: quoted fields, doubled quotes, commas and
/// newlines inside quotes.
List<List<String>> _parseCsv(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var quoted = false;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        field.write(c);
      }
    } else if (c == '"') {
      quoted = true;
    } else if (c == ',') {
      row.add(field.toString());
      field.clear();
    } else if (c == '\n' || c == '\r') {
      if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(field.toString());
      field.clear();
      if (row.any((f) => f.isNotEmpty)) rows.add(row);
      row = <String>[];
    } else {
      field.write(c);
    }
  }
  if (field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString());
    if (row.any((f) => f.isNotEmpty)) rows.add(row);
  }
  return rows;
}
