import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/study.dart';
import '../../../state/study_providers.dart';
import '../../widgets/study_widgets.dart';

/// Write a new note, or change an existing one when [noteId] is given.
class NoteEditorScreen extends ConsumerWidget {
  const NoteEditorScreen({super.key, this.noteId});
  final String? noteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = noteId;
    if (id == null) {
      return const StudyScope(child: _NoteForm(note: null));
    }
    final async = ref.watch(noteProvider(id));
    return StudyScope(
      child: Builder(builder: (context) {
        // Editing: wait for the note, with a form-shaped placeholder.
        if (async.hasValue && async.value != null) return _NoteForm(note: async.value);
        return Scaffold(
          appBar: const StudyTopBar(title: 'Edit note'),
          body: StudyPage(children: [
            if (async.hasError)
              StudyErrorState(
                message: '${async.error}',
                onRetry: () => ref.invalidate(noteProvider(id)),
              )
            else if (async.hasValue)
              const StudyEmptyState('This note no longer exists. It may have been deleted.')
            else
              const _FormSkeleton(),
          ]),
        );
      }),
    );
  }
}

class _FormSkeleton extends StatelessWidget {
  const _FormSkeleton();

  @override
  Widget build(BuildContext context) => const ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Bone(height: 52, radius: Radii.control),
            SizedBox(height: Gap.page),
            Bone(width: 180, height: 52, radius: Radii.control),
            SizedBox(height: Gap.page),
            Bone(height: 280, radius: Radii.control),
          ],
        ),
      );
}

class _NoteForm extends ConsumerStatefulWidget {
  const _NoteForm({required this.note});
  final Note? note;

  @override
  ConsumerState<_NoteForm> createState() => _NoteFormState();
}

class _NoteFormState extends ConsumerState<_NoteForm> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.note?.title ?? '');
  late final _course = TextEditingController(text: widget.note?.courseCode ?? '');
  late final _body = TextEditingController(text: widget.note?.body ?? '');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _course.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final title = _title.text.trim();
    final body = _body.text.trim();
    final course = _course.text.trim().isEmpty ? null : _course.text.trim().toUpperCase();
    try {
      final existing = widget.note;
      if (existing == null) {
        final created = await studyRepo.createNote(title: title, body: body, courseCode: course);
        if (!mounted) return;
        refreshStudy(ref, noteId: created.id);
        context.pushReplacement('/study/note/${created.id}');
      } else {
        await studyRepo.updateNote(existing.id, title: title, body: body, courseCode: course);
        if (!mounted) return;
        refreshStudy(ref, noteId: existing.id);
        context.pop();
      }
    } on Failure catch (f) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = f.message;
        });
      }
    }
  }

  String? _required(String? v, String what) =>
      (v == null || v.trim().isEmpty) ? 'Add $what.' : null;

  @override
  Widget build(BuildContext context) {
    final editing = widget.note != null;
    return Scaffold(
      appBar: StudyTopBar(
        title: editing ? 'Edit note' : 'New note',
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: Gap.tight),
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving' : 'Save'),
            ),
          ),
        ],
      ),
      body: Form(
        key: _form,
        child: StudyPage(children: [
          if (_error != null) ...[
            InlineNotice(_error!, error: true, onClose: () => setState(() => _error = null)),
            const SizedBox(height: Gap.page),
          ],
          TextFormField(
            controller: _title,
            maxLength: StudyLimits.noteTitle,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Title'),
            validator: (v) => _required(v, 'a title'),
          ),
          const SizedBox(height: Gap.tight),
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 220,
              child: TextFormField(
                controller: _course,
                maxLength: StudyLimits.courseCode,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Course code',
                  hintText: 'For example EEE 2021',
                  helperText: 'Optional',
                ),
              ),
            ),
          ),
          const SizedBox(height: Gap.tight),
          TextFormField(
            controller: _body,
            minLines: 12,
            maxLines: null,
            maxLength: StudyLimits.noteBody,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Note',
              alignLabelWithHint: true,
              hintText: 'Type or paste your notes here.',
            ),
            // A note built on a PDF does not need typed text.
            validator: (v) => (widget.note?.hasPdf ?? false) ? null : _required(v, 'some text'),
          ),
        ]),
      ),
    );
  }
}
