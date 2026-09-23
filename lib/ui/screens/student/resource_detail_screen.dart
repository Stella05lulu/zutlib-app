import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/failure.dart';
import '../../../core/theme.dart';
import '../../../models/resource.dart';
import '../../../state/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/state_views.dart';

class ResourceDetailScreen extends ConsumerWidget {
  const ResourceDetailScreen({super.key, required this.resourceId});
  final String resourceId;

  Future<void> _open(BuildContext context, Resource r) async {
    try {
      final url = r.externalUrl ??
          await resourceRepo.signedUrl(r.filePath!, seconds: 300);
      final uri = Uri.parse(url);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        if (context.mounted) {
          showMessage(context, 'Could not open that file.', isError: true);
        }
      }
    } on Failure catch (f) {
      if (context.mounted) showMessage(context, f.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(resourceProvider(resourceId));

    return Scaffold(
      appBar: AppBar(title: const Text('Resource')),
      body: AsyncView<Resource>(
        value: async,
        onRetry: () => ref.invalidate(resourceProvider(resourceId)),
        data: (r) => SingleChildScrollView(
          padding: const EdgeInsets.all(Insets.md),
          child: Readable(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TypeBadge(r.type),
                    const SizedBox(width: Insets.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.title,
                              style: Theme.of(context).textTheme.headlineSmall),
                          const SizedBox(height: Insets.xs),
                          Text(r.type.label,
                              style: Theme.of(context).textTheme.bodyMedium),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Insets.lg),
                Card(
                  child: Column(
                    children: [
                      _Row('Course code', r.courseCode),
                      const Divider(height: 1),
                      _Row('Department', r.department),
                      const Divider(height: 1),
                      _Row('Academic year', '${r.academicYear}'),
                      if (r.semester != null) ...[
                        const Divider(height: 1),
                        _Row('Semester', '${r.semester}'),
                      ],
                      if (r.isPhysical) ...[
                        const Divider(height: 1),
                        _Row('Physical copies', r.availabilityLabel),
                      ],
                    ],
                  ),
                ),
                if (r.description != null && r.description!.isNotEmpty) ...[
                  const SectionHeading('About this resource'),
                  Text(r.description!,
                      style: Theme.of(context).textTheme.bodyMedium),
                ],
                const SizedBox(height: Insets.lg),
                if (r.hasDigitalCopy)
                  FilledButton.icon(
                    onPressed: () => _open(context, r),
                    icon: Icon(r.externalUrl != null
                        ? Icons.open_in_new
                        : Icons.download_outlined),
                    label: Text(r.externalUrl != null
                        ? 'Open the book link'
                        : 'Open the document'),
                  ),
                if (r.isPhysical) ...[
                  const SizedBox(height: Insets.sm),
                  if (r.canBeBorrowed)
                    OutlinedButton.icon(
                      onPressed: () => context.push('/resource/${r.id}/borrow'),
                      icon: const Icon(Icons.library_books_outlined),
                      label: const Text('Apply to borrow a copy'),
                    )
                  else
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(Insets.md),
                      decoration: BoxDecoration(
                        color: Palette.warnWash,
                        borderRadius: BorderRadius.circular(Corners.field),
                      ),
                      child: Text(
                        'Every copy is currently on loan. Check back once one '
                        'is returned.',
                        style: TextStyle(
                            color: Palette.warn, fontSize: 13.5, height: 1.4),
                      ),
                    ),
                ],
                const SizedBox(height: Insets.xl),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);
  final String label, value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: Insets.md, vertical: 13),
        child: Row(
          children: [
            SizedBox(
              width: 140,
              child: Text(label,
                  style: Theme.of(context).textTheme.bodyMedium),
            ),
            Expanded(
              child: Text(value,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
}
