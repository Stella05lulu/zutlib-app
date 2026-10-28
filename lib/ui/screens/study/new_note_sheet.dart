import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/resource_repository.dart';
import '../../../models/resource.dart';
import '../../../models/study.dart';
import '../../../state/providers.dart';
import '../../../state/study_providers.dart';
import '../../widgets/study_widgets.dart';

/// The three ways to start studying: upload your own PDF, pick a PDF the
/// library already has (a past paper or lecture notes), or type a note.
Future<void> showNewNoteSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.panel)),
    ),
    builder: (_) => const _NewNoteSheet(),
  );
}

class _NewNoteSheet extends ConsumerStatefulWidget {
  const _NewNoteSheet();
  @override
  ConsumerState<_NewNoteSheet> createState() => _NewNoteSheetState();
}

class _NewNoteSheetState extends ConsumerState<_NewNoteSheet> {
  bool _busy = false;
  String? _error;
  bool _picking = false;

  Future<void> _upload() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    final file = result?.files.firstOrNull;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final name = file.name.toLowerCase().endsWith('.pdf') ? file.name.substring(0, file.name.length - 4) : file.name;
      final note = await studyRepo.createPdfNote(
        title: name.trim().isEmpty ? 'My PDF' : (name.length > StudyLimits.noteTitle ? name.substring(0, StudyLimits.noteTitle) : name),
        bytes: bytes,
        fileName: file.name,
      );
      if (!mounted) return;
      refreshStudy(ref, noteId: note.id);
      final router = GoRouter.of(context);
      Navigator.pop(context);
      unawaited(router.push('/study/note/${note.id}'));
    } on Failure catch (f) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = f.message;
        });
      }
    }
  }

  Future<void> _fromLibrary(Resource r) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final note = await studyRepo.createLibraryNote(
        resourceId: r.id,
        title: r.title,
        courseCode: r.courseCode.isEmpty ? null : r.courseCode,
      );
      if (!mounted) return;
      refreshStudy(ref, noteId: note.id);
      final router = GoRouter.of(context);
      Navigator.pop(context);
      unawaited(router.push('/study/note/${note.id}'));
    } on Failure catch (f) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = f.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(Gap.page, Gap.page, Gap.page, Gap.section + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_picking ? 'Choose a PDF from the library' : 'What do you want to study?', style: t.titleMedium),
          const SizedBox(height: Gap.snug),
          if (_busy) ...[
            const LinearProgressIndicator(minHeight: 3),
            const SizedBox(height: Gap.snug),
            Text('Preparing your study note.', style: t.bodyMedium),
          ] else if (_picking)
            _LibraryPicker(onPick: _fromLibrary)
          else ...[
            _Choice(
              icon: Icons.upload_file,
              title: 'Upload a PDF',
              detail: 'Your own lecture notes or handouts, up to 10 MB. Only you can see it.',
              onTap: _upload,
            ),
            const SizedBox(height: Gap.tight),
            _Choice(
              icon: Icons.local_library_outlined,
              title: 'Pick a PDF from the library',
              detail: 'A past paper or lecture notes already in ZutLib.',
              onTap: () => setState(() => _picking = true),
            ),
            const SizedBox(height: Gap.tight),
            _Choice(
              icon: Icons.edit_note,
              title: 'Type or paste a note',
              detail: 'Write the material yourself.',
              onTap: () {
                final router = GoRouter.of(context);
                Navigator.pop(context);
                unawaited(router.push('/study/note/new'));
              },
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: Gap.snug),
            InlineNotice(_error!, error: true),
          ],
        ],
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({required this.icon, required this.title, required this.detail, required this.onTap});
  final IconData icon;
  final String title, detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    final t = Theme.of(context).textTheme;
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.control),
        side: BorderSide(color: c.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.snug + 2, vertical: Gap.row),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 22, color: c.inkSoft),
              const SizedBox(width: Gap.snug),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: t.titleMedium),
                    const SizedBox(height: Gap.hair),
                    Text(detail, style: t.bodyMedium),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A search over library items that have a PDF.
class _LibraryPicker extends StatefulWidget {
  const _LibraryPicker({required this.onPick});
  final ValueChanged<Resource> onPick;
  @override
  State<_LibraryPicker> createState() => _LibraryPickerState();
}

class _LibraryPickerState extends State<_LibraryPicker> {
  final _q = TextEditingController();
  List<Resource>? _results;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await resourceRepo.search(ResourceFilters(query: _q.text), limit: 40);
      if (!mounted) return;
      setState(() {
        _results = rows.where((r) => r.hasPdf).toList();
        _loading = false;
      });
    } on Failure catch (f) {
      if (mounted) {
        setState(() {
          _error = f.message;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _q,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Course code or title, for example ICT 2010',
            prefixIcon: Icon(Icons.search, size: 20),
          ),
          onSubmitted: (_) => _search(),
        ),
        const SizedBox(height: Gap.snug),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.5),
          child: SingleChildScrollView(
            child: _error != null
                ? StudyErrorState(message: _error!, onRetry: _search)
                : _loading || results == null
                    ? const RowsSkeleton(rows: 4, detail: false)
                    : results.isEmpty
                        ? const StudyEmptyState('No library PDFs match that search.', compact: true)
                        : RowGroup(children: [
                            for (final r in results)
                              StudyRow(
                                title: r.title,
                                meta: [r.type.label, if (r.academicYear != null) '${r.academicYear}'].join('  /  '),
                                tags: [if (r.isSample) const Tag('Sample', sky: true)],
                                onTap: () => widget.onPick(r),
                              ),
                          ]),
          ),
        ),
      ],
    );
  }
}
