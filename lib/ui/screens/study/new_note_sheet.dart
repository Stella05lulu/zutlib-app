import 'dart:async';
import 'dart:typed_data';

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
import 'kit_widgets.dart';

/// "Provide your materials": the start of a new study kit. A kit is built
/// on one PDF the student uploads, one YouTube video, pasted or typed
/// text, or a PDF already in the library. "Proceed without materials"
/// makes an empty kit the student fills by hand.
///
/// After the kit is made the sheet closes and the kit opens with ?build=1,
/// which starts building the guide, cards and questions with AI.
Future<void> showNewNoteSheet(BuildContext context) => showNewKitSheet(context);

Future<void> showNewKitSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.panel + 6)),
    ),
    builder: (_) => const StudyScope(child: _NewKitSheet()),
  );
}

enum _Source { upload, youtube, paste, library }

class _NewKitSheet extends ConsumerStatefulWidget {
  const _NewKitSheet();
  @override
  ConsumerState<_NewKitSheet> createState() => _NewKitSheetState();
}

class _NewKitSheetState extends ConsumerState<_NewKitSheet> {
  _Source _source = _Source.upload;
  final _title = TextEditingController();
  final _link = TextEditingController();
  final _text = TextEditingController();
  Uint8List? _pdfBytes;
  String? _pdfName;
  Resource? _resource;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _link.dispose();
    _text.dispose();
    super.dispose();
  }

  KitColor get _nextColor => KitColorX.forIndex(ref.read(notesProvider).valueOrNull?.length ?? 0);

  bool get _ready => switch (_source) {
        _Source.upload => _pdfBytes != null,
        _Source.youtube => normaliseYoutubeUrl(_link.text) != null,
        _Source.paste => _text.text.trim().isNotEmpty,
        _Source.library => _resource != null,
      };

  String _titleOr(String fallback) {
    final t = _title.text.trim();
    final v = t.isEmpty ? fallback : t;
    return v.length > StudyLimits.noteTitle ? v.substring(0, StudyLimits.noteTitle) : v;
  }

  Future<void> _pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    final file = result?.files.firstOrNull;
    if (file == null || file.bytes == null) return;
    if (file.bytes!.length > StudyLimits.pdfBytes) {
      setState(() => _error = 'That PDF is larger than 10 MB. Choose a smaller file, for example one chapter.');
      return;
    }
    setState(() {
      _pdfBytes = file.bytes;
      _pdfName = file.name;
      _error = null;
    });
  }

  Future<void> _create({required bool withMaterials}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final color = _nextColor;
      final Note note;
      if (!withMaterials) {
        note = await studyRepo.createNote(title: _titleOr('My study kit'), body: '', color: color);
      } else {
        switch (_source) {
          case _Source.upload:
            final name = _pdfName ?? 'My PDF';
            final stem = name.toLowerCase().endsWith('.pdf') ? name.substring(0, name.length - 4) : name;
            note = await studyRepo.createPdfNote(
              title: _titleOr(stem.trim().isEmpty ? 'My PDF' : stem),
              bytes: _pdfBytes!,
              fileName: name,
              color: color,
            );
          case _Source.youtube:
            note = await studyRepo.createVideoKit(
              title: _titleOr('YouTube lecture'),
              youtubeUrl: normaliseYoutubeUrl(_link.text)!,
              color: color,
            );
          case _Source.paste:
            final text = _text.text.trim();
            final firstLine = text.split('\n').first.trim();
            note = await studyRepo.createNote(
              title: _titleOr(firstLine.length > 60 ? '${firstLine.substring(0, 60)}...' : firstLine),
              body: text.length > StudyLimits.noteBody ? text.substring(0, StudyLimits.noteBody) : text,
              color: color,
            );
          case _Source.library:
            final r = _resource!;
            note = await studyRepo.createLibraryNote(
              resourceId: r.id,
              title: _titleOr(r.title),
              courseCode: r.courseCode.isEmpty ? null : r.courseCode,
              color: color,
            );
        }
      }
      if (!mounted) return;
      refreshKit(ref, note.id);
      final router = GoRouter.of(context);
      Navigator.pop(context);
      unawaited(router.push('/study/note/${note.id}${withMaterials ? '?build=1' : ''}'));
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
    final c = StudyColors.of(context);
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.92),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Gap.page, Gap.snug, Gap.page, Gap.section),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(color: c.lineStrong, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: Gap.snug),
                  Row(
                    children: [
                      Expanded(child: Text('Provide your materials', style: t.titleLarge)),
                      IconButton(
                        tooltip: 'Close',
                        icon: const Icon(Icons.close),
                        onPressed: _busy ? null : () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  Text('AI turns them into a study guide, flashcards and practice questions.',
                      style: t.bodyMedium),
                  const SizedBox(height: Gap.page),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: KitSegments(
                        labels: const ['Upload', 'YouTube', 'Paste', 'Library'],
                        index: _source.index,
                        onChanged: _busy
                            ? (_) {}
                            : (i) => setState(() {
                                  _source = _Source.values[i];
                                  _error = null;
                                }),
                      ),
                    ),
                  ),
                  const SizedBox(height: Gap.page),
                  switch (_source) {
                    _Source.upload => _UploadBox(
                        fileName: _pdfName,
                        onTap: _busy ? null : _pickPdf,
                      ),
                    _Source.youtube => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: _link,
                            enabled: !_busy,
                            keyboardType: TextInputType.url,
                            decoration: InputDecoration(
                              labelText: 'YouTube link',
                              hintText: 'https://www.youtube.com/watch?v=...',
                              prefixIcon: const Icon(Icons.smart_display_outlined),
                              errorText: _link.text.trim().isNotEmpty && normaliseYoutubeUrl(_link.text) == null
                                  ? 'That is not a YouTube video link'
                                  : null,
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: Gap.tight),
                          Text('Public videos only. AI watches the video, so a lecture or tutorial works best.',
                              style: t.bodySmall),
                        ],
                      ),
                    _Source.paste => TextField(
                        controller: _text,
                        enabled: !_busy,
                        minLines: 6,
                        maxLines: 12,
                        maxLength: StudyLimits.noteBody,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Paste or type your notes',
                          alignLabelWithHint: true,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    _Source.library => _resource == null
                        ? _LibraryPicker(onPick: (r) => setState(() => _resource = r))
                        : RowGroup(children: [
                            StudyRow(
                              title: _resource!.title,
                              meta: [_resource!.type.label, if (_resource!.academicYear != null) '${_resource!.academicYear}']
                                  .join('  /  '),
                              trailing: TextButton(
                                onPressed: _busy ? null : () => setState(() => _resource = null),
                                child: const Text('Change'),
                              ),
                            ),
                          ]),
                  },
                  const SizedBox(height: Gap.page),
                  TextField(
                    controller: _title,
                    enabled: !_busy,
                    maxLength: StudyLimits.noteTitle,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Kit name (optional)',
                      hintText: 'For example: Cloud Computing and Big Data',
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: Gap.tight),
                    InlineNotice(_error!, error: true),
                  ],
                  const SizedBox(height: Gap.snug),
                  if (_busy) ...[
                    const LinearProgressIndicator(minHeight: 3),
                    const SizedBox(height: Gap.snug),
                  ],
                  FilledButton.icon(
                    onPressed: _busy || !_ready ? null : () => _create(withMaterials: true),
                    icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                    label: const Text('Create study kit'),
                  ),
                  const SizedBox(height: Gap.tight),
                  Center(
                    child: TextButton(
                      onPressed: _busy ? null : () => _create(withMaterials: false),
                      child: const Text('Proceed without materials'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The place to tap to choose a PDF.
class _UploadBox extends StatelessWidget {
  const _UploadBox({required this.fileName, required this.onTap});
  final String? fileName;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    final t = Theme.of(context).textTheme;
    final chosen = fileName != null;
    return Material(
      color: chosen ? c.accentWash : c.sunken,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.panel),
        side: BorderSide(color: chosen ? c.accent : c.lineStrong, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.page, vertical: Gap.section),
          child: Column(
            children: [
              Icon(chosen ? Icons.picture_as_pdf_outlined : Icons.cloud_upload_outlined,
                  size: 40, color: chosen ? c.accent : c.inkSoft),
              const SizedBox(height: Gap.tight),
              Text(chosen ? fileName! : 'Click to add a PDF',
                  style: t.titleMedium, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: Gap.hair),
              Text(chosen ? 'Tap to choose a different file' : 'Lecture notes, handouts or a past paper, up to 10 MB',
                  style: t.bodySmall, textAlign: TextAlign.center),
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
