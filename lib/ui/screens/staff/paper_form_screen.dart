import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/library_import.dart';
import '../../../models/resource.dart';
import '../../../state/providers.dart';
import '../../widgets/study_widgets.dart';

/// Edit what describes a past paper, test or set of lecture notes. The PDF
/// itself stays; a wrong file is fixed by deleting and uploading again.
class PaperFormScreen extends ConsumerWidget {
  const PaperFormScreen({super.key, required this.paperId});
  final String paperId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(resourceProvider(paperId));
    return StudyScope(
      child: Builder(builder: (context) {
        if (async.hasValue) return _PaperForm(paper: async.requireValue);
        return Scaffold(
          appBar: const StudyTopBar(title: 'Edit details'),
          body: StudyPage(children: [
            if (async.hasError)
              StudyErrorState(message: '${async.error}', onRetry: () => ref.invalidate(resourceProvider(paperId)))
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

class _PaperForm extends ConsumerStatefulWidget {
  const _PaperForm({required this.paper});
  final Resource paper;
  @override
  ConsumerState<_PaperForm> createState() => _PaperFormState();
}

class _PaperFormState extends ConsumerState<_PaperForm> {
  final _form = GlobalKey<FormState>();
  late final _code = TextEditingController(text: widget.paper.courseCode);
  late final _courseTitle = TextEditingController(text: widget.paper.courseTitle ?? '');
  late final _year = TextEditingController(text: '${widget.paper.academicYear ?? DateTime.now().year}');
  late final _topic = TextEditingController(text: _draft(withTopic: false).topicIn(widget.paper.title) ?? '');
  late String? _department = kLibraryDepartments.contains(widget.paper.department) ? widget.paper.department : null;
  late PaperKind _kind = switch (widget.paper.type) {
    ResourceType.testPaper => PaperKind.test,
    ResourceType.lectureNotes => PaperKind.notes,
    _ => PaperKind.exam,
  };
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_code, _courseTitle, _year, _topic]) {
      c.dispose();
    }
    super.dispose();
  }

  /// The paper as the form describes it right now. Before the form has
  /// a department it borrows the stored one, so the title preview works.
  PaperDraft _draft({bool withTopic = true}) => PaperDraft(
        department: _department ?? widget.paper.department,
        courseCode: _code.text.trim(),
        courseTitle: _courseTitle.text.trim(),
        academicYear: int.tryParse(_year.text.trim()) ?? 0,
        kind: _kind,
        topic: withTopic && _kind == PaperKind.notes ? _topic.text.trim() : null,
      );

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await libraryRepo.updatePaper(widget.paper.id, _draft());
      if (!mounted) return;
      ref.invalidate(resourceProvider(widget.paper.id));
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
    final t = Theme.of(context).textTheme;
    final draft = _draft();
    return Scaffold(
      appBar: StudyTopBar(
        title: 'Edit details',
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: Gap.tight),
            child: FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Saving' : 'Save')),
          ),
        ],
      ),
      body: Form(
        key: _form,
        onChanged: () => setState(() {}),
        child: StudyPage(children: [
          if (widget.paper.isSample) ...[
            const InlineNotice('This is sample data, used for demonstrations.'),
            const SizedBox(height: Gap.page),
          ],
          if (_error != null) ...[
            InlineNotice(_error!, error: true),
            const SizedBox(height: Gap.page),
          ],
          DropdownButtonFormField<String>(
            initialValue: _department,
            decoration: const InputDecoration(labelText: 'Department'),
            items: [for (final d in kLibraryDepartments) DropdownMenuItem(value: d, child: Text(d))],
            onChanged: (v) => setState(() => _department = v),
            validator: (v) => v == null ? 'Choose a department' : null,
          ),
          const SizedBox(height: Gap.snug),
          Wrap(spacing: Gap.snug, runSpacing: Gap.snug, children: [
            SizedBox(
              width: 180,
              child: TextFormField(
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Course code', hintText: 'ICT 2010'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter the course code' : null,
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
          const SizedBox(height: Gap.snug),
          TextFormField(
            controller: _courseTitle,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Course title', hintText: 'Programming in C'),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter the course title' : null,
          ),
          const SizedBox(height: Gap.snug),
          Text('Type', style: t.titleSmall),
          const SizedBox(height: Gap.tight),
          SegmentedButton<PaperKind>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: PaperKind.exam, label: Text('Examination')),
              ButtonSegment(value: PaperKind.test, label: Text('Test')),
              ButtonSegment(value: PaperKind.notes, label: Text('Lecture notes')),
            ],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() => _kind = s.first),
          ),
          if (_kind == PaperKind.notes) ...[
            const SizedBox(height: Gap.snug),
            TextFormField(
              controller: _topic,
              maxLength: 120,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Topic',
                hintText: 'Week 3: Pointers',
                helperText: 'Optional. Added to the title so students can tell sets apart.',
              ),
            ),
          ],
          const SectionLabel('Title students will see'),
          Text(draft.title, style: t.bodyLarge),
          if (draft.title != widget.paper.title) ...[
            const SizedBox(height: Gap.tight),
            Text('Was: ${widget.paper.title}', style: t.bodySmall),
          ],
        ]),
      ),
    );
  }
}
