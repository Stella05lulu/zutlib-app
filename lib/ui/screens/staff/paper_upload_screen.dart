import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/library_import.dart';
import '../../../data/library_repository.dart';
import '../../../state/providers.dart';
import '../../widgets/study_widgets.dart';

/// Upload past papers and lecture notes: one PDF with its details, or many
/// PDFs at once with a CSV that describes each of them.
class PaperUploadScreen extends ConsumerStatefulWidget {
  const PaperUploadScreen({super.key});
  @override
  ConsumerState<PaperUploadScreen> createState() => _PaperUploadScreenState();
}

class _PaperUploadScreenState extends ConsumerState<PaperUploadScreen> {
  bool _bulk = false;

  @override
  Widget build(BuildContext context) {
    return StudyScope(
      child: Builder(builder: (context) {
        final c = StudyColors.of(context);
        return Scaffold(
          appBar: const StudyTopBar(title: 'Upload papers and notes'),
          body: StudyPage(children: [
            Container(
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
              child: Row(children: [
                for (var i = 0; i < 2; i++)
                  InkWell(
                    onTap: () => setState(() => _bulk = i == 1),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(2, Gap.snug, 2, Gap.snug - 2),
                      margin: const EdgeInsets.only(right: Gap.page + 2),
                      decoration: BoxDecoration(
                        border: Border(
                            bottom: BorderSide(color: _bulk == (i == 1) ? c.accent : c.canvas, width: 2)),
                      ),
                      child: Text(i == 0 ? 'One PDF' : 'Many PDFs with a CSV',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                color: _bulk == (i == 1) ? c.ink : c.inkFaint,
                              )),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: Gap.page),
            if (_bulk) const _BulkUpload() else const _SingleUpload(),
          ]),
        );
      }),
    );
  }
}

// ------------------------------------------------------------------ one paper
class _SingleUpload extends ConsumerStatefulWidget {
  const _SingleUpload();
  @override
  ConsumerState<_SingleUpload> createState() => _SingleUploadState();
}

class _SingleUploadState extends ConsumerState<_SingleUpload> {
  final _form = GlobalKey<FormState>();
  final _code = TextEditingController();
  final _courseTitle = TextEditingController();
  final _year = TextEditingController(text: '${DateTime.now().year}');
  final _topic = TextEditingController();
  String? _department;
  PaperKind _kind = PaperKind.exam;
  PlatformFile? _file;
  bool _busy = false;
  String? _message;
  bool _isError = false;

  @override
  void dispose() {
    _code.dispose();
    _courseTitle.dispose();
    _year.dispose();
    _topic.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    final f = result?.files.firstOrNull;
    if (f != null) setState(() => _file = f);
  }

  Future<void> _upload() async {
    if (!_form.currentState!.validate()) return;
    final file = _file;
    final bytes = file?.bytes;
    if (file == null || bytes == null) {
      setState(() {
        _message = 'Choose the PDF first.';
        _isError = true;
      });
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    final paper = PaperDraft(
      department: _department!,
      courseCode: _code.text.trim(),
      courseTitle: _courseTitle.text.trim(),
      academicYear: int.parse(_year.text.trim()),
      kind: _kind,
      topic: _kind == PaperKind.notes ? _topic.text.trim() : null,
    );
    try {
      await libraryRepo.uploadPaper(paper, bytes, file.name);
      if (!mounted) return;
      refreshCatalogue(ref);
      ref.invalidate(facetsProvider);
      setState(() {
        _message = '${paper.title} was uploaded.';
        _isError = false;
        _file = null;
        _topic.clear();
      });
    } on Failure catch (f) {
      if (mounted) {
        setState(() {
          _message = f.message;
          _isError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
          const SizedBox(height: Gap.page),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _pick,
              icon: const Icon(Icons.attach_file, size: 18),
              label: Text(_file == null ? 'Choose the PDF' : _file!.name),
            ),
          ),
          if (_message != null) ...[
            const SizedBox(height: Gap.snug),
            InlineNotice(_message!, error: _isError),
          ],
          const SizedBox(height: Gap.page),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: _busy ? null : _upload,
              child: Text(_busy ? 'Uploading' : 'Upload'),
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ many papers
class _BulkUpload extends ConsumerStatefulWidget {
  const _BulkUpload();
  @override
  ConsumerState<_BulkUpload> createState() => _BulkUploadState();
}

class _BulkUploadState extends ConsumerState<_BulkUpload> {
  final Map<String, Uint8List> _files = {};
  String? _csvName;
  String? _csvProblem;
  List<ImportRow<PaperDraft>> _rows = const [];
  List<ImportOutcome>? _report;
  bool _busy = false;

  Future<void> _pickPdfs() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      allowMultiple: true,
      withData: true,
    );
    if (result == null) return;
    setState(() {
      for (final f in result.files) {
        if (f.bytes != null) _files[f.name] = f.bytes!;
      }
      _report = null;
    });
    _recheck();
  }

  String? _csvText;

  Future<void> _pickCsv() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );
    final f = result?.files.firstOrNull;
    if (f == null || f.bytes == null) return;
    _csvText = utf8.decode(f.bytes!, allowMalformed: true);
    setState(() {
      _csvName = f.name;
      _report = null;
    });
    _recheck();
  }

  void _recheck() {
    final text = _csvText;
    if (text == null) return;
    final parsed = parsePapersCsv(text, _files.keys.toSet());
    setState(() {
      _csvProblem = parsed.fileProblem;
      _rows = parsed.rows;
    });
  }

  Future<void> _upload() async {
    setState(() => _busy = true);
    final report = await libraryRepo.uploadPapers(_rows, _files);
    if (!mounted) return;
    refreshCatalogue(ref);
    ref.invalidate(facetsProvider);
    setState(() {
      _report = report;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final good = _rows.where((r) => r.isOk).length;
    final report = _report;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('1. Choose the PDFs. 2. Choose a CSV with one line per PDF. Its first line must be:', style: t.bodyMedium),
        const SizedBox(height: Gap.tight),
        SelectableText(kPaperCsvHeader, style: Mono.of(context, size: 13)),
        const SizedBox(height: Gap.tight),
        Text('"file" is the PDF\'s file name exactly, department is ICT, Engineering or Business, '
            'and paper_type is exam, test or notes.',
            style: t.bodySmall),
        const SizedBox(height: Gap.page),
        Wrap(spacing: Gap.tight, runSpacing: Gap.tight, children: [
          OutlinedButton.icon(
            onPressed: _busy ? null : _pickPdfs,
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
            label: Text(_files.isEmpty ? 'Choose PDFs' : '${_files.length} PDFs chosen'),
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pickCsv,
            icon: const Icon(Icons.table_view_outlined, size: 18),
            label: Text(_csvName ?? 'Choose the CSV'),
          ),
        ]),
        const SizedBox(height: Gap.page),
        if (_csvProblem != null)
          InlineNotice(_csvProblem!, error: true)
        else if (report != null) ...[
          InlineNotice('${report.where((o) => o.ok).length} uploaded, ${report.where((o) => !o.ok).length} not uploaded.'),
          const SizedBox(height: Gap.snug),
          RowGroup(children: [
            for (final o in report)
              StudyRow(
                title: o.label,
                detail: o.ok ? 'Uploaded' : o.error,
                meta: 'line ${o.line}',
                tags: [Tag(o.ok ? 'Uploaded' : 'Not uploaded', sky: o.ok)],
              ),
          ]),
        ] else if (_csvName == null || _files.isEmpty)
          const StudyEmptyState('Choose the PDFs and the CSV to see what will be uploaded.', compact: true)
        else ...[
          Text('$good of ${_rows.length} lines are ready.', style: t.titleSmall),
          const SizedBox(height: Gap.snug),
          RowGroup(children: [
            for (final r in _rows)
              StudyRow(
                title: r.isOk ? r.value!.title : 'Line ${r.line} will be skipped',
                detail: r.isOk ? r.value!.fileName : r.problem,
                meta: 'line ${r.line}',
                tags: [if (!r.isOk) const Tag('Problem')],
              ),
          ]),
          const SizedBox(height: Gap.page),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: _busy || good == 0 ? null : _upload,
              child: Text(_busy ? 'Uploading' : 'Upload $good ${good == 1 ? 'PDF' : 'PDFs'}'),
            ),
          ),
          if (_busy) ...[
            const SizedBox(height: Gap.snug),
            const LinearProgressIndicator(minHeight: 3),
          ],
        ],
      ],
    );
  }
}
