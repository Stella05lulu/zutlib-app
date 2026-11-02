import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/library_import.dart';
import '../../../data/library_repository.dart';
import '../../../state/providers.dart';
import '../../widgets/study_widgets.dart';

/// Add many books at once from a CSV file. Every row is checked first and
/// the librarian sees which rows will be added and why others will not,
/// then a report of what was saved.
class BookImportScreen extends ConsumerStatefulWidget {
  const BookImportScreen({super.key});
  @override
  ConsumerState<BookImportScreen> createState() => _BookImportScreenState();
}

class _BookImportScreenState extends ConsumerState<BookImportScreen> {
  String? _fileName;
  String? _fileProblem;
  List<ImportRow<BookDraft>> _rows = const [];
  List<ImportOutcome>? _report;
  bool _busy = false;

  Future<void> _pick() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );
    final file = result?.files.firstOrNull;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return;
    final parsed = parseBooksCsv(utf8.decode(bytes, allowMalformed: true));
    setState(() {
      _fileName = file.name;
      _fileProblem = parsed.fileProblem;
      _rows = parsed.rows;
      _report = null;
    });
  }

  Future<void> _import() async {
    setState(() => _busy = true);
    final report = await libraryRepo.importBooks(_rows);
    if (!mounted) return;
    refreshCatalogue(ref);
    setState(() {
      _report = report;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final good = _rows.where((r) => r.isOk).length;
    final bad = _rows.length - good;
    final report = _report;
    return StudyScope(
      child: Builder(builder: (context) {
        final t = Theme.of(context).textTheme;
        return Scaffold(
          appBar: const StudyTopBar(title: 'Import books'),
          body: StudyPage(children: [
            Text('The first line of the file must be:', style: t.bodyMedium),
            const SizedBox(height: Gap.tight),
            SelectableText(kBookCsvHeader, style: Mono.of(context, size: 13)),
            const SizedBox(height: Gap.tight),
            Text('Title, author, department (ICT, Engineering or Business) and total copies are required. '
                'ISBN, course code and edition are optional. Imported books are not marked as sample data.',
                style: t.bodySmall),
            const SizedBox(height: Gap.page),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _pick,
                icon: const Icon(Icons.attach_file, size: 18),
                label: Text(_fileName == null ? 'Choose a CSV file' : 'Choose a different file'),
              ),
            ),
            if (_fileName != null) ...[
              const SizedBox(height: Gap.page),
              if (_fileProblem != null)
                InlineNotice(_fileProblem!, error: true)
              else if (report == null) ...[
                Text('$_fileName: $good ${good == 1 ? 'book' : 'books'} ready, $bad with problems.',
                    style: t.titleSmall),
                const SizedBox(height: Gap.snug),
                if (_rows.isEmpty)
                  const StudyEmptyState('The file has a header but no rows.', compact: true)
                else
                  RowGroup(children: [
                    for (final r in _rows.take(200))
                      StudyRow(
                        title: r.isOk ? r.value!.title : 'Line ${r.line} will be skipped',
                        detail: r.isOk ? '${r.value!.author}, ${r.value!.totalCopies} copies' : r.problem,
                        meta: 'line ${r.line}',
                        tags: [if (!r.isOk) const Tag('Problem')],
                      ),
                  ]),
                const SizedBox(height: Gap.page),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton(
                    onPressed: _busy || good == 0 ? null : _import,
                    child: Text(_busy ? 'Importing' : 'Import $good ${good == 1 ? 'book' : 'books'}'),
                  ),
                ),
                if (_busy) ...[
                  const SizedBox(height: Gap.snug),
                  const LinearProgressIndicator(minHeight: 3),
                ],
              ] else ...[
                InlineNotice('${report.where((o) => o.ok).length} added, '
                    '${report.where((o) => !o.ok).length} not added.'),
                const SizedBox(height: Gap.snug),
                RowGroup(children: [
                  for (final o in report)
                    StudyRow(
                      title: o.label,
                      detail: o.ok ? 'Added' : o.error,
                      meta: 'line ${o.line}',
                      tags: [Tag(o.ok ? 'Added' : 'Not added', sky: o.ok)],
                    ),
                ]),
              ],
            ],
          ]),
        );
      }),
    );
  }
}
