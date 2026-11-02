import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/library_import.dart';
import '../../../state/providers.dart';
import '../../widgets/study_widgets.dart';

/// Add a recommended book: a reading-list entry for a course that links to
/// the book online. Students find it under Recommended books on Explore.
class LinkFormScreen extends ConsumerStatefulWidget {
  const LinkFormScreen({super.key});
  @override
  ConsumerState<LinkFormScreen> createState() => _LinkFormScreenState();
}

class _LinkFormScreenState extends ConsumerState<LinkFormScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _author = TextEditingController();
  final _course = TextEditingController();
  final _year = TextEditingController(text: '${DateTime.now().year}');
  final _url = TextEditingController();
  String? _department;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_title, _author, _course, _year, _url]) {
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
      await libraryRepo.createLink(LinkDraft(
        title: _title.text.trim(),
        author: _author.text.trim(),
        department: _department!,
        courseCode: _course.text.trim(),
        academicYear: int.parse(_year.text.trim()),
        url: _url.text.trim(),
      ));
      if (!mounted) return;
      refreshCatalogue(ref);
      ref.invalidate(facetsProvider);
      context.pop();
    } on Failure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String? need(String? v, String what) => (v == null || v.trim().isEmpty) ? 'Enter the $what' : null;
    return StudyScope(
      child: Scaffold(
        appBar: StudyTopBar(
          title: 'Add a recommended book',
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
              decoration: const InputDecoration(labelText: 'Author', helperText: 'Optional'),
            ),
            const SizedBox(height: Gap.tight),
            TextFormField(
              controller: _url,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Link',
                hintText: 'https://',
                helperText: 'Where students can read or buy the book',
              ),
              validator: (v) => linkProblem(v ?? '') == null ? null : 'Enter a web address starting with https://',
            ),
            const SizedBox(height: Gap.page),
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
                width: 180,
                child: TextFormField(
                  controller: _course,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'Course code', hintText: 'ICT 2010'),
                  validator: (v) => need(v, 'course code'),
                ),
              ),
              SizedBox(
                width: 140,
                child: TextFormField(
                  controller: _year,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Academic year'),
                  validator: (v) {
                    final y = int.tryParse((v ?? '').trim());
                    return y == null || y < 1990 || y > 2100 ? 'A year such as 2024' : null;
                  },
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
