import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/library_import.dart';
import '../../../models/resource.dart';
import '../../../state/providers.dart';
import '../../widgets/study_widgets.dart';

/// Add a book, or edit one when [bookId] is given. Copy counts on an
/// existing book change from the Library list ("Change copy count"), so
/// the shelf count always moves with the total.
class BookFormScreen extends ConsumerWidget {
  const BookFormScreen({super.key, this.bookId});
  final String? bookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = bookId;
    if (id == null) return const StudyScope(child: _BookForm(book: null));
    final async = ref.watch(resourceProvider(id));
    return StudyScope(
      child: Builder(builder: (context) {
        if (async.hasValue) return _BookForm(book: async.requireValue);
        return Scaffold(
          appBar: const StudyTopBar(title: 'Edit book'),
          body: StudyPage(children: [
            if (async.hasError)
              StudyErrorState(message: '${async.error}', onRetry: () => ref.invalidate(resourceProvider(id)))
            else
              const Column(children: [
                Bone(height: 52, radius: Radii.control),
                SizedBox(height: Gap.page),
                Bone(height: 52, radius: Radii.control),
                SizedBox(height: Gap.page),
                Bone(width: 220, height: 52, radius: Radii.control),
              ]),
          ]),
        );
      }),
    );
  }
}

class _BookForm extends ConsumerStatefulWidget {
  const _BookForm({required this.book});
  final Resource? book;
  @override
  ConsumerState<_BookForm> createState() => _BookFormState();
}

class _BookFormState extends ConsumerState<_BookForm> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.book?.title ?? '');
  late final _author = TextEditingController(text: widget.book?.author ?? '');
  late final _isbn = TextEditingController(text: widget.book?.isbn ?? '');
  late final _course = TextEditingController(text: widget.book?.courseCode ?? '');
  late final _edition = TextEditingController(text: widget.book?.edition ?? '');
  late final _copies = TextEditingController(text: '${widget.book?.totalCopies ?? 1}');
  late String? _department = widget.book?.department;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_title, _author, _isbn, _course, _edition, _copies]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final draft = BookDraft(
        title: _title.text.trim(),
        author: _author.text.trim(),
        department: _department!,
        totalCopies: int.parse(_copies.text.trim()),
        isbn: cleanIsbn(_isbn.text),
        courseCode: _course.text.trim(),
        edition: _edition.text.trim(),
      );
      final existing = widget.book;
      if (existing == null) {
        await libraryRepo.createBook(draft);
      } else {
        await libraryRepo.updateBook(existing.id, draft);
        ref.invalidate(resourceProvider(existing.id));
      }
      if (!mounted) return;
      refreshCatalogue(ref);
      context.pop();
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Failure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.book != null;
    String? need(String? v, String what) => (v == null || v.trim().isEmpty) ? 'Enter the $what' : null;
    return Scaffold(
      appBar: StudyTopBar(
        title: editing ? 'Edit book' : 'Add a book',
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: Gap.tight),
            child: FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Saving' : 'Save')),
          ),
        ],
      ),
      body: Form(
        key: _form,
        child: StudyPage(children: [
          if (widget.book?.isSample ?? false) ...[
            const InlineNotice('This is a sample book, used for demonstrations.'),
            const SizedBox(height: Gap.page),
          ],
          if (_error != null) ...[
            InlineNotice(_error!, error: true),
            const SizedBox(height: Gap.page),
          ],
          TextFormField(
            controller: _title,
            maxLength: 300,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Title'),
            validator: (v) => need(v, 'title'),
          ),
          TextFormField(
            controller: _author,
            maxLength: 200,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Author'),
            validator: (v) => need(v, 'author'),
          ),
          const SizedBox(height: Gap.tight),
          DropdownButtonFormField<String>(
            initialValue: _department,
            decoration: const InputDecoration(labelText: 'Department'),
            items: [for (final d in kLibraryDepartments) DropdownMenuItem(value: d, child: Text(d))],
            onChanged: (v) => setState(() => _department = v),
            validator: (v) => v == null ? 'Choose a department' : null,
          ),
          const SizedBox(height: Gap.page),
          Wrap(spacing: Gap.snug, runSpacing: Gap.snug, children: [
            SizedBox(
              width: 240,
              child: TextFormField(
                controller: _isbn,
                decoration: const InputDecoration(labelText: 'ISBN', helperText: 'Optional, 10 or 13 digits'),
                validator: (v) {
                  try {
                    cleanIsbn(v ?? '');
                    return null;
                  } on FormatException catch (e) {
                    return e.message;
                  }
                },
              ),
            ),
            SizedBox(
              width: 180,
              child: TextFormField(
                controller: _course,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Course code', helperText: 'Optional'),
              ),
            ),
            SizedBox(
              width: 140,
              child: TextFormField(
                controller: _edition,
                maxLength: 40,
                decoration: const InputDecoration(labelText: 'Edition', helperText: 'Optional'),
              ),
            ),
          ]),
          const SizedBox(height: Gap.snug),
          if (!editing)
            SizedBox(
              width: 180,
              child: TextFormField(
                controller: _copies,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Total copies'),
                validator: (v) {
                  final n = int.tryParse((v ?? '').trim());
                  return n == null || n < 1 || n > 1000 ? 'From 1 to 1000' : null;
                },
              ),
            )
          else
            Text('${widget.book!.availableCopies} of ${widget.book!.totalCopies} copies are on the shelf. '
                'Change the total from the Library list.',
                style: Theme.of(context).textTheme.bodyMedium),
        ]),
      ),
    );
  }
}
