import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/failure.dart';
import '../../../core/theme.dart';
import '../../../models/resource.dart';
import '../../../state/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/state_views.dart';

class ResourceManagerScreen extends ConsumerWidget {
  const ResourceManagerScreen({super.key});

  Future<void> _delete(BuildContext context, WidgetRef ref, Resource r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove this resource?'),
        content: Text('"${r.title}" will no longer appear in the library. '
            'This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep it')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await resourceRepo.delete(r.id);
      ref.invalidate(searchProvider);
      ref.invalidate(overviewProvider);
      if (context.mounted) showMessage(context, 'Removed.');
    } on Failure catch (f) {
      if (context.mounted) showMessage(context, f.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(searchProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Resources')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/staff/upload'),
        backgroundColor: Palette.blue,
        foregroundColor: Palette.onAccent,
        icon: const Icon(Icons.add),
        label: const Text('Add resource'),
      ),
      body: AsyncView<List<Resource>>(
        value: async,
        onRetry: () => ref.invalidate(searchProvider),
        data: (items) {
          if (items.isEmpty) {
            return EmptyView(
              icon: Icons.folder_outlined,
              headline: 'The library is empty',
              body: 'Add past papers, test papers, lecture notes or links to '
                  'recommended books so students can find them.',
              action: FilledButton(
                onPressed: () => context.push('/staff/upload'),
                child: const Text('Add the first resource'),
              ),
            );
          }
          final columns = catalogGridColumns(MediaQuery.sizeOf(context).width);
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(
                Insets.md, Insets.md, Insets.md, kNavClearance + 60),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: Insets.md,
              crossAxisSpacing: Insets.md,
              mainAxisExtent: 232,
            ),
            itemCount: items.length,
            itemBuilder: (_, i) {
              final r = items[i];
              return ResourceGridCard(
                resource: r,
                onTap: () => context.push('/resource/${r.id}'),
                overlayAction: CardOverlayButton(
                  icon: Icons.delete_outline,
                  tooltip: 'Remove',
                  color: Palette.bad,
                  onPressed: () => _delete(context, ref, r),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
