import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/failure.dart';
import '../../../core/theme.dart';
import '../../../models/resource.dart';
import '../../../state/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/state_views.dart';

/// The staff view of the catalogue. It has its own search box, so what a
/// librarian types here never changes a student's Explore filters.
class ResourceManagerScreen extends ConsumerStatefulWidget {
  const ResourceManagerScreen({super.key});

  @override
  ConsumerState<ResourceManagerScreen> createState() =>
      _ResourceManagerScreenState();
}

class _ResourceManagerScreenState extends ConsumerState<ResourceManagerScreen> {
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _search.text = ref.read(staffQueryProvider);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), () {
      ref.read(staffQueryProvider.notifier).state = value.trim();
    });
  }

  void _clear() {
    _debounce?.cancel();
    _search.clear();
    ref.read(staffQueryProvider.notifier).state = '';
    setState(() {});
  }

  Future<void> _delete(Resource r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove this resource?'),
        content: Text('"${r.title}" and its file will be removed from the '
            'library. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Keep it')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await resourceRepo.delete(r);
      ref.invalidate(staffResourcesProvider);
      ref.invalidate(searchProvider);
      ref.invalidate(facetsProvider);
      ref.invalidate(overviewProvider);
      if (mounted) showMessage(context, 'Removed.');
    } on Failure catch (f) {
      if (mounted) showMessage(context, f.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(staffResourcesProvider);
    final query = ref.watch(staffQueryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Resources')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/staff/upload'),
        backgroundColor: Palette.blue,
        foregroundColor: Palette.onAccent,
        icon: const Icon(Icons.add),
        label: const Text('Add resource'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Insets.md, Insets.sm, Insets.md, Insets.sm),
            child: Readable(
              maxWidth: 1100,
              child: TextField(
                controller: _search,
                onChanged: _onChanged,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search by course code, title or year',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: _clear,
                        ),
                ),
              ),
            ),
          ),
          Expanded(
            child: AsyncView<List<Resource>>(
              value: async,
              onRetry: () => ref.invalidate(staffResourcesProvider),
              data: (items) {
                if (items.isEmpty) {
                  return query.isNotEmpty
                      ? EmptyView(
                          icon: Icons.search_off_rounded,
                          headline: 'No resources match that',
                          body: 'Try a course code such as EEE 2011, or clear '
                              'the search.',
                          action: OutlinedButton(
                            onPressed: _clear,
                            child: const Text('Clear search'),
                          ),
                        )
                      : EmptyView(
                          icon: Icons.folder_outlined,
                          headline: 'The library is empty',
                          body: 'Add past papers, test papers, lecture notes '
                              'or links to recommended books so students can '
                              'find them.',
                          action: FilledButton(
                            onPressed: () => context.push('/staff/upload'),
                            child: const Text('Add the first resource'),
                          ),
                        );
                }
                final columns =
                    catalogGridColumns(MediaQuery.sizeOf(context).width);
                return CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                            Insets.md, Insets.xs, Insets.md, Insets.sm),
                        child: Text(
                          '${items.length} '
                          '${items.length == 1 ? "resource" : "resources"}'
                          '${items.length >= 100 ? ", showing the first 100. "
                              "Search to narrow it down." : ""}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                          Insets.md, 0, Insets.md, kNavClearance + 60),
                      sliver: SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          mainAxisSpacing: Insets.md,
                          crossAxisSpacing: Insets.md,
                          mainAxisExtent: 232,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (_, i) {
                            final r = items[i];
                            return ResourceGridCard(
                              resource: r,
                              onTap: () => context.push('/resource/${r.id}'),
                              overlayAction: CardOverlayButton(
                                icon: Icons.delete_outline,
                                tooltip: 'Remove',
                                color: Palette.bad,
                                onPressed: () => _delete(r),
                              ),
                            );
                          },
                          childCount: items.length,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
