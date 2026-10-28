import 'dart:typed_data';

import '../core/failure.dart';
import '../core/supabase.dart';
import '../models/resource.dart';
import 'library_import.dart';

/// The result of one row of a bulk import, for the report shown afterwards.
class ImportOutcome {
  const ImportOutcome(this.line, this.label, this.error);
  final int line;
  final String label;

  /// Null when the row was saved.
  final String? error;
  bool get ok => error == null;
}

/// Librarian tools: books, copy counts, retiring, and past paper uploads.
/// Row level security lets only active library staff write the catalogue;
/// copy counts are changed through set_book_copies() so they can never go
/// below zero or above the total.
class LibraryRepository {
  const LibraryRepository();

  static const _bucket = 'resources';

  /// The staff view of the catalogue. Unlike student search it can include
  /// retired books.
  Future<List<Resource>> list({
    required bool books,
    String query = '',
    bool includeRetired = false,
  }) async {
    try {
      var q = db.from('resources').select();
      q = books ? q.eq('type', 'book') : q.inFilter('type', ['past_paper', 'test_paper', 'lecture_notes']);
      if (!includeRetired) q = q.isFilter('retired_at', null);
      final s = query.trim().replaceAll(RegExp(r'[,()%]'), ' ').trim();
      if (s.isNotEmpty) {
        q = q.or('title.ilike.%$s%,course_code.ilike.%$s%,author.ilike.%$s%,course_title.ilike.%$s%');
      }
      final rows = await q.order('created_at', ascending: false).limit(200);
      return [for (final r in rows) Resource.fromMap(r)];
    } catch (e) {
      throw Failure.from(e);
    }
  }

  Future<void> createBook(BookDraft book) async {
    final problems = book.problems();
    if (problems.isNotEmpty) throw Failure('Check the form: ${problems.join('; ')}.');
    try {
      await db.from('resources').insert({...book.toRow(), 'uploaded_by': currentUserId});
    } catch (e) {
      throw Failure.from(e);
    }
  }

  /// Changes a book's details. Copy counts change separately, through
  /// [setCopies].
  Future<void> updateBook(String id, BookDraft book) async {
    final problems = book.problems();
    if (problems.isNotEmpty) throw Failure('Check the form: ${problems.join('; ')}.');
    final row = book.toRow()
      ..remove('total_copies')
      ..remove('available_copies')
      ..remove('type')
      ..remove('is_physical');
    try {
      await db.from('resources').update(row).eq('id', id);
    } catch (e) {
      throw Failure.from(e);
    }
  }

  /// Sets how many copies the library owns. The number on the shelf moves
  /// by the same amount; the database refuses a total smaller than the
  /// number out on loan.
  Future<void> setCopies(String id, int total) async {
    try {
      await db.rpc('set_book_copies', params: {'p_resource': id, 'p_total': total});
    } catch (e) {
      throw Failure.from(e);
    }
  }

  /// Takes a book out of the catalogue without deleting its borrowing history.
  Future<void> retire(String id) async {
    try {
      await db.from('resources').update({'retired_at': DateTime.now().toUtc().toIso8601String()}).eq('id', id);
    } catch (e) {
      throw Failure.from(e);
    }
  }

  Future<void> restore(String id) async {
    try {
      await db.from('resources').update({'retired_at': null}).eq('id', id);
    } catch (e) {
      throw Failure.from(e);
    }
  }

  /// Saves each valid book row on its own and reports what happened to
  /// every row.
  Future<List<ImportOutcome>> importBooks(List<ImportRow<BookDraft>> rows) async {
    final out = <ImportOutcome>[];
    for (final r in rows) {
      if (!r.isOk) {
        out.add(ImportOutcome(r.line, 'Line ${r.line}', r.problem));
        continue;
      }
      final b = r.value!;
      try {
        await db.from('resources').insert({...b.toRow(), 'uploaded_by': currentUserId});
        out.add(ImportOutcome(r.line, b.title, null));
      } catch (e) {
        out.add(ImportOutcome(r.line, b.title, Failure.from(e).message));
      }
    }
    return out;
  }

  /// Uploads one past paper PDF and catalogues it. If the catalogue row is
  /// refused, the uploaded file is removed again.
  Future<void> uploadPaper(PaperDraft paper, Uint8List bytes, String fileName) async {
    final problems = paper.problems();
    if (problems.isNotEmpty) throw Failure('Check the form: ${problems.join('; ')}.');
    if (bytes.length < 5 || String.fromCharCodes(bytes.sublist(0, 5)) != '%PDF-') {
      throw const Failure('That file is not a PDF.');
    }
    final safe = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final code = paper.courseCode.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final path = '${paper.department}/$code/${DateTime.now().millisecondsSinceEpoch}_$safe';
    try {
      await db.storage.from(_bucket).uploadBinary(path, bytes);
    } catch (e) {
      throw Failure.from(e);
    }
    try {
      await db.from('resources').insert({...paper.toRow(path), 'uploaded_by': currentUserId});
    } catch (e) {
      try {
        await db.storage.from(_bucket).remove([path]);
      } catch (_) {
        // The catalogue row was refused; a leftover file is harmless.
      }
      throw Failure.from(e);
    }
  }

  /// Uploads a batch of PDFs described by a CSV and reports every row.
  Future<List<ImportOutcome>> uploadPapers(
      List<ImportRow<PaperDraft>> rows, Map<String, Uint8List> files) async {
    final out = <ImportOutcome>[];
    for (final r in rows) {
      if (!r.isOk) {
        out.add(ImportOutcome(r.line, 'Line ${r.line}', r.problem));
        continue;
      }
      final p = r.value!;
      final bytes = files[p.fileName];
      if (bytes == null) {
        out.add(ImportOutcome(r.line, p.fileName ?? 'Line ${r.line}', 'the PDF was not picked'));
        continue;
      }
      try {
        await uploadPaper(p, bytes, p.fileName!);
        out.add(ImportOutcome(r.line, p.title, null));
      } on Failure catch (f) {
        out.add(ImportOutcome(r.line, p.fileName!, f.message));
      }
    }
    return out;
  }

  /// Removes a paper that nobody has borrowed (the database refuses if
  /// borrowing history points at it), then its file.
  Future<void> deletePaper(Resource r) async {
    try {
      await db.from('resources').delete().eq('id', r.id);
      if (r.filePath != null) await db.storage.from(_bucket).remove([r.filePath!]);
    } catch (e) {
      throw Failure.from(e);
    }
  }
}
