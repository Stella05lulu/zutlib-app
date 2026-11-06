import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/failure.dart';
import '../../../core/theme.dart' show kNavClearance;
import '../../../core/theme/app_theme.dart';
import '../../../data/governance_repository.dart' show governanceRepo;
import '../../../models/resource.dart';
import '../../../state/governance_providers.dart';
import '../../widgets/common.dart' show showMessage;
import '../../widgets/section_switch.dart';
import '../../widgets/study_widgets.dart';

/// Everything this person bookmarked, newest first, with a search box.
class SavedScreen extends ConsumerStatefulWidget {
  const SavedScreen({super.key});

  @override
  ConsumerState<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends ConsumerState<SavedScreen> {
  String _query = '';

  bool _matches(Resource r) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return [r.title, r.courseCode, r.department, r.author ?? '', r.type.label]
        .any((x) => x.toLowerCase().contains(q));
  }

  Future<void> _remove(Resource r) async {
    try {
      await governanceRepo.unsave(r.id);
      ref.invalidate(savedProvider);
    } on Failure catch (f) {
      if (mounted) showMessage(context, f.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(savedProvider);
    return StudyScope(
      child: Builder(builder: (context) {
        final t = Theme.of(context).textTheme;
        return Scaffold(
          body: SafeArea(
           bottom: false,
           child: StudyPage(
            bottom: kNavClearance,
            onRefresh: () async {
              ref.invalidate(savedProvider);
              try {
                await ref.read(savedProvider.future);
              } catch (_) {
                // Shown on the page.
              }
            },
            children: [
              const SizedBox(height: Gap.tight),
              const SectionHeader(title: 'Explore', sections: exploreSections),
              const SizedBox(height: Gap.page),
              TextField(
                decoration: const InputDecoration(
                  hintText: 'Search your saved items',
                  prefixIcon: Icon(Icons.search, size: 20),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
              const SizedBox(height: Gap.snug),
              StudyAsync<List<Resource>>(
                value: async,
                onRetry: () => ref.invalidate(savedProvider),
                skeleton: const RowsSkeleton(rows: 5),
                isEmpty: (v) => v.isEmpty,
                empty: const StudyEmptyState('Nothing saved yet. Tap the bookmark on any item to keep it here.'),
                data: (all) {
                  final shown = all.where(_matches).toList();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('${shown.length} of ${all.length} saved', style: t.bodySmall),
                      const SizedBox(height: Gap.tight),
                      if (shown.isEmpty)
                        const StudyEmptyState('Nothing saved matches that search.', compact: true)
                      else
                        RowGroup(children: [
                          for (final r in shown)
                            StudyRow(
                              title: r.title,
                              detail: [
                                r.type.label,
                                if (r.courseCode.isNotEmpty) r.courseCode,
                                r.department,
                                if (r.academicYear != null) '${r.academicYear}',
                              ].join('  /  '),
                              detailLines: 1,
                              tags: [if (r.isSample) const Tag('Sample')],
                              trailing: IconButton(
                                tooltip: 'Remove from Saved',
                                icon: const Icon(Icons.bookmark_remove_outlined, size: 20),
                                onPressed: () => _remove(r),
                              ),
                              onTap: () => context.push('/resource/${r.id}'),
                            ),
                        ]),
                    ],
                  );
                },
              ),
            ],
           ),
          ),
        );
      }),
    );
  }
}
