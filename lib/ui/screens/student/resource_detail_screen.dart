import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/profile.dart';
import '../../../models/resource.dart';
import '../../../state/providers.dart';
import '../../../state/study_providers.dart';
import '../../widgets/study_widgets.dart';
import '../shared/pdf_viewer_screen.dart';
import '../../../state/plan_providers.dart' show accountRepo;

/// One catalogue item. Papers open as a PDF through a link that expires
/// after five minutes. Students can ask to borrow a physical copy, or turn
/// a PDF into a study kit; staff see the item without those actions.
class ResourceDetailScreen extends ConsumerStatefulWidget {
  const ResourceDetailScreen({super.key, required this.resourceId});
  final String resourceId;

  @override
  ConsumerState<ResourceDetailScreen> createState() => _ResourceDetailScreenState();
}

class _ResourceDetailScreenState extends ConsumerState<ResourceDetailScreen> {
  String? _message;
  bool _isError = false;
  bool _studying = false;

  void _show(String m, bool isError) {
    if (mounted) {
      setState(() {
        _message = m;
        _isError = isError;
      });
    }
  }

  Future<void> _open(Resource r) async {
    if (r.externalUrl != null) {
      final ok = await launchUrl(Uri.parse(r.externalUrl!), mode: LaunchMode.externalApplication);
      if (!ok) _show('Could not open that link on this device.', true);
      return;
    }
    unawaited(accountRepo.logEvent('open_resource', courseCode: r.courseCode, resourceId: r.id));
    final error = await openPdf(context,
        title: r.title, loadUrl: () => resourceRepo.signedUrl(r.filePath!, seconds: 300));
    if (error != null) _show(error, true);
  }

  /// Makes a study note built on this PDF and opens it, ready for AI help.
  Future<void> _study(Resource r) async {
    setState(() => _studying = true);
    try {
      final note = await studyRepo.createLibraryNote(
        resourceId: r.id,
        title: r.title,
        courseCode: r.courseCode.isEmpty ? null : r.courseCode,
      );
      if (!mounted) return;
      refreshStudy(ref, noteId: note.id);
      unawaited(context.push('/study/note/${note.id}?build=1'));
    } on Failure catch (f) {
      _show(f.message, true);
    } finally {
      if (mounted) setState(() => _studying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(resourceProvider(widget.resourceId));
    final isStudent = ref.watch(profileProvider).valueOrNull?.role == UserRole.student;

    return StudyScope(
      child: Builder(builder: (context) {
        final t = Theme.of(context).textTheme;
        return Scaffold(
          appBar: StudyTopBar(title: async.valueOrNull?.type.label ?? 'Resource'),
          body: StudyPage(children: [
            StudyAsync<Resource>(
              value: async,
              onRetry: () => ref.invalidate(resourceProvider(widget.resourceId)),
              skeleton: const TextSkeleton(paragraphs: 2),
              data: (r) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (r.isSample) ...[
                    const InlineNotice('Sample data for demonstration only. This is not an official ZUT item.'),
                    const SizedBox(height: Gap.page),
                  ],
                  Text(r.title, style: t.headlineSmall),
                  const SizedBox(height: Gap.tight),
                  Wrap(spacing: Gap.tight, runSpacing: Gap.hair, children: [
                    Tag(r.type.label),
                    Tag(r.department),
                    if (r.courseCode.isNotEmpty) Tag(r.courseCode),
                    if (r.isRetired) const Tag('Retired'),
                  ]),
                  if (_message != null) ...[
                    const SizedBox(height: Gap.page),
                    InlineNotice(_message!, error: _isError, onClose: () => setState(() => _message = null)),
                  ],
                  const SizedBox(height: Gap.page),
                  Wrap(spacing: Gap.tight, runSpacing: Gap.tight, children: [
                    if (r.hasDigitalCopy)
                      FilledButton.icon(
                        onPressed: () => _open(r),
                        icon: Icon(r.externalUrl != null ? Icons.open_in_new : Icons.picture_as_pdf_outlined,
                            size: 18),
                        label: Text(r.externalUrl != null ? 'Open the link' : 'Open the PDF'),
                      ),
                    if (isStudent && r.hasPdf)
                      OutlinedButton.icon(
                        onPressed: _studying ? null : () => _study(r),
                        icon: const Icon(Icons.school_outlined, size: 18),
                        label: Text(_studying ? 'Preparing' : 'Study this with AI'),
                      ),
                    if (isStudent && r.isPhysical && r.canBeBorrowed)
                      OutlinedButton.icon(
                        onPressed: () => context.push('/resource/${r.id}/borrow'),
                        icon: const Icon(Icons.library_books_outlined, size: 18),
                        label: const Text('Ask to borrow a copy'),
                      ),
                  ]),
                  if (isStudent && r.isPhysical && !r.canBeBorrowed) ...[
                    const SizedBox(height: Gap.snug),
                    Text(
                      r.isRetired
                          ? 'This book has been retired and cannot be borrowed.'
                          : 'Every copy is on loan right now. Check back once one is returned.',
                      style: t.bodyMedium,
                    ),
                  ],
                  if (isStudent && r.hasPdf) ...[
                    const SizedBox(height: Gap.snug),
                    Text('Study this with AI builds a study kit from this PDF: a study guide, '
                        'flashcards, practice questions and timed tests.',
                        style: t.bodySmall),
                  ],
                  if (r.author != null ||
                      r.edition != null ||
                      r.isbn != null ||
                      r.courseTitle != null ||
                      r.academicYear != null ||
                      r.semester != null ||
                      r.isPhysical) ...[
                  const SectionLabel('Details'),
                  RowGroup(children: [
                    if (r.author != null) _Detail('Author', r.author!),
                    if (r.edition != null) _Detail('Edition', r.edition!),
                    if (r.isbn != null) _Detail('ISBN', r.isbn!, mono: true),
                    if (r.courseTitle != null) _Detail('Course', r.courseTitle!),
                    if (r.academicYear != null) _Detail('Academic year', '${r.academicYear}', mono: true),
                    if (r.semester != null) _Detail('Semester', '${r.semester}', mono: true),
                    if (r.isPhysical) _Detail('Copies', r.availabilityLabel),
                  ]),
                  ],
                  if (r.description != null && r.description!.isNotEmpty) ...[
                    const SectionLabel('About this item'),
                    Text(r.description!, style: t.bodyMedium),
                  ],
                ],
              ),
            ),
          ]),
        );
      }),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail(this.label, this.value, {this.mono = false});
  final String label, value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Gap.page - 4, vertical: Gap.snug),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 130, child: Text(label, style: t.bodyMedium)),
          Expanded(
            child: Text(value,
                style: mono
                    ? Mono.of(context, size: 14, color: StudyColors.of(context).ink)
                    : t.bodyLarge?.copyWith(fontSize: 15)),
          ),
        ],
      ),
    );
  }
}
