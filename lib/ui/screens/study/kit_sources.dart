import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/governance_repository.dart';
import '../../../data/resource_repository.dart' show ResourceFilters;
import '../../../models/resource.dart';
import '../../../models/study.dart';
import '../../../state/governance_providers.dart';
import '../../../state/providers.dart' show resourceRepo;
import '../../widgets/study_widgets.dart';
import '../shared/pdf_viewer_screen.dart';

/// Every source a kit is built from: the kit's original one (an upload, a
/// library PDF or a video) and up to four more of any kind, with typed
/// text too. AI help reads all of them together (0020).
class KitSources extends ConsumerStatefulWidget {
  const KitSources({super.key, required this.note, required this.onChanged, required this.loadMainPdf});
  final Note note;
  final VoidCallback onChanged;
  final Future<String> Function() loadMainPdf;

  @override
  ConsumerState<KitSources> createState() => _KitSourcesState();
}

class _KitSourcesState extends ConsumerState<KitSources> {
  String? _message;
  bool _isError = false;
  bool _busy = false;

  List<KitSource> _all(List<KitSource> extra) {
    final n = widget.note;
    return [
      if (n.hasUpload) KitSource(kind: 'upload', label: n.fileName ?? 'Uploaded PDF', filePath: n.filePath, isMain: true),
      if (!n.hasUpload && n.resourceId != null)
        KitSource(kind: 'library', label: n.resourceTitle ?? 'Library PDF', resourceId: n.resourceId, isMain: true),
      if (!n.hasUpload && n.resourceId == null && n.hasVideo)
        KitSource(kind: 'youtube', label: 'YouTube video', youtubeUrl: n.youtubeUrl, isMain: true),
      ...extra,
    ];
  }

  Future<void> _run(String done, Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
      ref.invalidate(kitSourcesProvider(widget.note.id));
      widget.onChanged();
      if (mounted) {
        setState(() {
          _message = done;
          _isError = false;
        });
      }
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

  Future<void> _open(KitSource s) async {
    switch (s.kind) {
      case 'upload':
        final error = await openPdf(context,
            title: s.label, loadUrl: s.isMain ? widget.loadMainPdf : () => governanceRepo.sourcePdfUrl(s));
        if (error != null && mounted) {
          setState(() {
            _message = error;
            _isError = true;
          });
        }
      case 'library':
        if (s.isMain) {
          final error = await openPdf(context, title: s.label, loadUrl: widget.loadMainPdf);
          if (error != null && mounted) {
            setState(() {
              _message = error;
              _isError = true;
            });
          }
        } else {
          await context.push('/resource/${s.resourceId}');
        }
      case 'youtube':
        final ok = await launchUrl(Uri.parse(s.youtubeUrl!), mode: LaunchMode.externalApplication);
        if (!ok && mounted) {
          setState(() {
            _message = 'Could not open the video on this device.';
            _isError = true;
          });
        }
      default:
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(s.label),
            content: SingleChildScrollView(child: Text(s.body ?? '')),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
          ),
        );
    }
  }

  Future<void> _remove(KitSource s) async {
    final ok = await confirmDelete(context,
        what: 'this source',
        consequence: 'It is taken out of the kit. What AI already made from it stays until you build again.');
    if (!ok) return;
    await _run('Source removed.', () => governanceRepo.removeSource(widget.note.id, s));
  }

  Future<void> _add() async {
    final kind = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final (k, label, icon) in const [
            ('upload', 'Upload a PDF', Icons.upload_file_outlined),
            ('library', 'A PDF from the library', Icons.local_library_outlined),
            ('youtube', 'A YouTube video', Icons.smart_display_outlined),
            ('text', 'Typed text', Icons.notes_outlined),
          ])
            ListTile(
              leading: Icon(icon),
              title: Text(label),
              onTap: () => Navigator.pop(ctx, k),
            ),
          const SizedBox(height: Gap.tight),
        ]),
      ),
    );
    if (!mounted || kind == null) return;
    final id = widget.note.id;
    switch (kind) {
      case 'upload':
        final picked = await FilePicker.platform
            .pickFiles(type: FileType.custom, allowedExtensions: ['pdf'], withData: true, allowMultiple: true);
        final files = [for (final f in picked?.files ?? const <PlatformFile>[]) if (f.bytes != null) f];
        if (files.isEmpty) return;
        final tooBig = [for (final f in files) if (f.bytes!.length > StudyLimits.pdfBytes) f.name];
        final ok = [for (final f in files) if (f.bytes!.length <= StudyLimits.pdfBytes) f];
        if (ok.isEmpty) {
          setState(() {
            _message = '${tooBig.join(', ')} is larger than 10 MB. Choose a smaller file.';
            _isError = true;
          });
          return;
        }
        // One at a time, so the server's checks (ten sources, 30 MB) apply
        // to each and the message says which file stopped it.
        await _run(
          ok.length == 1 ? 'PDF added.' : '${ok.length} PDFs added.',
          () async {
            for (final f in ok) {
              await governanceRepo.addUploadSource(id, bytes: f.bytes!, fileName: f.name);
            }
          },
        );
      case 'library':
        if (!mounted) return;
        final r = await showDialog<Resource>(context: context, builder: (_) => const _LibraryPicker());
        if (r != null) await _run('Library PDF added.', () => governanceRepo.addLibrarySource(id, r));
      case 'youtube':
        if (!mounted) return;
        final link = await askForTitle(context, heading: 'YouTube link', confirmLabel: 'Add', maxLength: 200);
        if (link == null) return;
        final url = normaliseYoutubeUrl(link);
        if (url == null) {
          setState(() {
          _message = 'That is not a YouTube video link.';
          _isError = true;
        });
          return;
        }
        await _run('Video added.', () => governanceRepo.addVideoSource(id, url));
      case 'text':
        if (!mounted) return;
        final text = await showDialog<(String, String)>(context: context, builder: (_) => const _TextSourceDialog());
        if (text != null) await _run('Text added.', () => governanceRepo.addTextSource(id, label: text.$1, body: text.$2));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = StudyColors.of(context);
    final async = ref.watch(kitSourcesProvider(widget.note.id));
    final extra = async.valueOrNull ?? const <KitSource>[];
    final all = _all(extra);
    final full = all.length >= GovernanceRepository.kitMaxSources;
    final mb = extra.fold<int>(0, (s, x) => s + x.bytes) / (1024 * 1024);

    IconData icon(KitSource s) => switch (s.kind) {
          'upload' => Icons.picture_as_pdf_outlined,
          'library' => Icons.local_library_outlined,
          'youtube' => Icons.smart_display_outlined,
          _ => Icons.notes_outlined,
        };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${all.length} of ${GovernanceRepository.kitMaxSources} sources'
          '${mb > 0 ? '  /  ${mb.toStringAsFixed(1)} MB of 30 MB added here' : ''}',
          style: Mono.of(context, size: 12),
        ),
        const SizedBox(height: Gap.tight),
        if (_message != null) ...[
          InlineNotice(_message!, error: _isError, onClose: () => setState(() => _message = null)),
          const SizedBox(height: Gap.tight),
        ],
        if (async.isLoading && !async.hasValue)
          const RowsSkeleton(rows: 2)
        else if (async.hasError)
          StudyErrorState(message: 'The sources could not be loaded.', onRetry: () => ref.invalidate(kitSourcesProvider(widget.note.id)))
        else if (all.isEmpty)
          const StudyEmptyState('No sources yet. Add PDFs, videos or text for AI to read together.', compact: true)
        else
          RowGroup(children: [
            for (final s in all)
              InkWell(
                onTap: () => _open(s),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Gap.page - 4, Gap.snug, Gap.hair, Gap.snug),
                  child: Row(children: [
                    Icon(icon(s), size: 22, color: c.accent),
                    const SizedBox(width: Gap.snug),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(s.label, style: t.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                        Text(
                          [
                            s.kindLabel,
                            if (s.kind == 'library') 'From the ZutLib library',
                            if (s.kind == 'upload') 'Only you can see it',
                            if (s.bytes > 0) '${(s.bytes / (1024 * 1024)).toStringAsFixed(1)} MB',
                          ].join('  /  '),
                          style: t.bodySmall,
                        ),
                      ]),
                    ),
                    IconButton(
                      tooltip: 'Remove ${s.label}',
                      onPressed: _busy ? null : () => _remove(s),
                      icon: const Icon(Icons.close, size: 20),
                    ),
                  ]),
                ),
              ),
          ]),
        const SizedBox(height: Gap.tight),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _busy || full ? null : _add,
            icon: const Icon(Icons.add, size: 18),
            label: Text(_busy ? 'Working' : full ? 'This kit has ${GovernanceRepository.kitMaxSources} sources' : 'Add a source'),
          ),
        ),
      ],
    );
  }
}

/// Search the library for a PDF to add.
class _LibraryPicker extends StatefulWidget {
  const _LibraryPicker();

  @override
  State<_LibraryPicker> createState() => _LibraryPickerState();
}

class _LibraryPickerState extends State<_LibraryPicker> {
  List<Resource>? _results;
  String? _error;
  bool _busy = false;

  Future<void> _search(String q) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final found = await resourceRepo.search(ResourceFilters(query: q.trim()), limit: 30);
      if (mounted) setState(() => _results = [for (final r in found) if (r.hasPdf) r]);
    } on Failure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AlertDialog(
      title: const Text('A PDF from the library'),
      content: SizedBox(
        width: 420,
        height: 380,
        child: Column(children: [
          TextField(
            autofocus: true,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(hintText: 'Course code or title', prefixIcon: Icon(Icons.search, size: 20)),
            onSubmitted: _search,
          ),
          const SizedBox(height: Gap.tight),
          Expanded(
            child: _busy
                ? const RowsSkeleton(rows: 4)
                : _error != null
                    ? Text(_error!, style: t.bodyMedium)
                    : _results == null
                        ? Text('Search for a past paper, notes or a book with a PDF.', style: t.bodySmall)
                        : _results!.isEmpty
                            ? Text('No PDFs match that search.', style: t.bodySmall)
                            : ListView(children: [
                                for (final r in _results!)
                                  ListTile(
                                                          title: Text(r.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                                    subtitle: Text([r.type.label, if (r.courseCode.isNotEmpty) r.courseCode].join('  /  ')),
                                    onTap: () => Navigator.pop(context, r),
                                  ),
                              ]),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
    );
  }
}

class _TextSourceDialog extends StatefulWidget {
  const _TextSourceDialog();

  @override
  State<_TextSourceDialog> createState() => _TextSourceDialogState();
}

class _TextSourceDialogState extends State<_TextSourceDialog> {
  final _label = TextEditingController();
  final _body = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _label.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Typed text'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: _label, maxLength: 120, decoration: const InputDecoration(labelText: 'Name, for example Formulas')),
          TextField(
            controller: _body,
            maxLength: 12000,
            minLines: 4,
            maxLines: 10,
            decoration: InputDecoration(labelText: 'Text', errorText: _error),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          onPressed: () {
            if (_label.text.trim().isEmpty || _body.text.trim().isEmpty) {
              setState(() => _error = 'Give it a name and some text.');
              return;
            }
            Navigator.pop(context, (_label.text.trim(), _body.text.trim()));
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}
