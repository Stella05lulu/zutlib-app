import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/failure.dart';
import '../../../core/theme.dart' show kNavClearance;
import '../../../core/theme/app_theme.dart';
import '../../../models/resource.dart';
import '../../../state/providers.dart';
import '../../widgets/study_widgets.dart';

/// The librarian's catalogue: past papers and books, with the tools to add,
/// edit, retire and import them. Only active library staff can reach this
/// screen, and only they can write the catalogue (row level security).
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});
  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final _search = TextEditingController();
  String? _message;
  bool _isError = false;

  @override
  void initState() {
    super.initState();
    _search.text = ref.read(libraryQueryProvider);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _show(String m, bool isError) => setState(() {
        _message = m;
        _isError = isError;
      });

  Future<void> _run(String done, Future<void> Function() action) async {
    try {
      await action();
      if (!mounted) return;
      refreshCatalogue(ref);
      _show(done, false);
    } on Failure catch (f) {
      if (mounted) _show(f.message, true);
    }
  }

  Future<void> _changeCopies(Resource book) async {
    final ctl = TextEditingController(text: '${book.totalCopies}');
    final total = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Copies the library owns'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${book.availableCopies} of ${book.totalCopies} are on the shelf now. '
                'The shelf count moves by the same amount as the total.'),
            const SizedBox(height: Gap.snug),
            TextField(
              controller: ctl,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Total copies'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(ctl.text.trim())),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    ctl.dispose();
    if (total == null) return;
    await _run('${book.title} now has $total copies.', () => libraryRepo.setCopies(book.id, total));
  }

  Future<void> _retire(Resource book) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Retire this book?'),
        content: const Text('It leaves the catalogue and cannot be requested any more. '
            'Its borrowing history is kept, and you can bring it back later.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep it')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Retire')),
        ],
      ),
    );
    if (ok != true) return;
    await _run('${book.title} was retired.', () => libraryRepo.retire(book.id));
  }

  Future<void> _deletePaper(Resource paper) async {
    final ok = await confirmDelete(context,
        what: 'this paper', consequence: 'The PDF is removed from storage too. This cannot be undone.');
    if (!ok) return;
    await _run('${paper.title} was deleted.', () => libraryRepo.deletePaper(paper));
  }

  @override
  Widget build(BuildContext context) {
    final tab = ref.watch(libraryTabProvider);
    final showRetired = ref.watch(libraryShowRetiredProvider);
    final items = ref.watch(libraryItemsProvider);
    final books = tab == 1;

    return StudyScope(
      child: Builder(builder: (context) {
        final c = StudyColors.of(context);
        final t = Theme.of(context).textTheme;
        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: StudyPage(
              bottom: kNavClearance,
              onRefresh: () async {
                ref.invalidate(libraryItemsProvider);
                try {
                  await ref.read(libraryItemsProvider.future);
                } catch (_) {
                  // Shown on screen.
                }
              },
              children: [
                const SizedBox(height: Gap.tight),
                Text('Library', style: t.headlineSmall),
                const SizedBox(height: Gap.hair + 2),
                Text('Past papers and books. Items marked Sample are demonstration data.', style: t.bodyMedium),
                const SizedBox(height: Gap.page),
                Container(
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
                  child: Row(children: [
                    for (var i = 0; i < 2; i++)
                      InkWell(
                        onTap: () => ref.read(libraryTabProvider.notifier).state = i,
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(2, Gap.snug, 2, Gap.snug - 2),
                          margin: const EdgeInsets.only(right: Gap.page + 2),
                          decoration: BoxDecoration(
                            border: Border(bottom: BorderSide(color: tab == i ? c.accent : c.canvas, width: 2)),
                          ),
                          child: Text(i == 0 ? 'Past papers' : 'Books',
                              style: t.titleSmall?.copyWith(color: tab == i ? c.ink : c.inkFaint)),
                        ),
                      ),
                  ]),
                ),
                const SizedBox(height: Gap.page),
                Wrap(spacing: Gap.tight, runSpacing: Gap.tight, children: [
                  if (books) ...[
                    FilledButton.icon(
                      onPressed: () => context.push('/staff/books/new'),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add a book'),
                    ),
                    OutlinedButton(
                      onPressed: () => context.push('/staff/books/import'),
                      child: const Text('Import books from CSV'),
                    ),
                  ] else
                    FilledButton.icon(
                      onPressed: () => context.push('/staff/papers/upload'),
                      icon: const Icon(Icons.upload_file, size: 18),
                      label: const Text('Upload papers'),
                    ),
                ]),
                const SizedBox(height: Gap.page),
                TextField(
                  controller: _search,
                  decoration: InputDecoration(
                    hintText: books ? 'Search by title, author or course' : 'Search by title or course',
                    prefixIcon: const Icon(Icons.search, size: 20),
                  ),
                  onSubmitted: (v) => ref.read(libraryQueryProvider.notifier).state = v,
                ),
                if (books)
                  Row(children: [
                    Checkbox(
                      value: showRetired,
                      onChanged: (v) => ref.read(libraryShowRetiredProvider.notifier).state = v ?? false,
                    ),
                    Text('Show retired books', style: t.bodyMedium),
                  ]),
                if (_message != null) ...[
                  const SizedBox(height: Gap.tight),
                  InlineNotice(_message!, error: _isError, onClose: () => setState(() => _message = null)),
                ],
                const SizedBox(height: Gap.snug),
                StudyAsync<SearchPage>(
                  value: items,
                  onRetry: () => ref.invalidate(libraryItemsProvider),
                  skeleton: const RowsSkeleton(rows: 6),
                  isEmpty: (v) => v.items.isEmpty,
                  empty: StudyEmptyState(books
                      ? 'No books match. Add one, or import a CSV of books.'
                      : 'No papers match. Upload a PDF, or several at once with a CSV.'),
                  data: (page) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    RowGroup(children: [
                      for (final r in page.items)
                        books
                            ? StudyRow(
                                title: r.title,
                                detail: [r.author ?? '', if (r.edition != null) '${r.edition} edition'].join(', '),
                                detailLines: 1,
                                meta: '${r.availableCopies}/${r.totalCopies} on shelf',
                                tags: [
                                  if (r.isSample) const Tag('Sample', sky: true),
                                  if (r.isRetired) const Tag('Retired'),
                                  Tag(r.department),
                                  if (r.courseCode.isNotEmpty) Tag(r.courseCode),
                                ],
                                onTap: () => context.push('/staff/books/${r.id}/edit'),
                                trailing: PopupMenuButton<String>(
                                  tooltip: 'More',
                                  onSelected: (v) {
                                    if (v == 'copies') _changeCopies(r);
                                    if (v == 'retire') _retire(r);
                                    if (v == 'restore') {
                                      _run('${r.title} is back in the catalogue.', () => libraryRepo.restore(r.id));
                                    }
                                  },
                                  itemBuilder: (_) => [
                                    const PopupMenuItem(value: 'copies', child: Text('Change copy count')),
                                    if (!r.isRetired) const PopupMenuItem(value: 'retire', child: Text('Retire')),
                                    if (r.isRetired) const PopupMenuItem(value: 'restore', child: Text('Bring back')),
                                  ],
                                ),
                              )
                            : StudyRow(
                                title: r.title,
                                detail: r.courseTitle,
                                detailLines: 1,
                                meta: [r.type.label, if (r.academicYear != null) '${r.academicYear}'].join('  /  '),
                                tags: [
                                  if (r.isSample) const Tag('Sample', sky: true),
                                  Tag(r.department),
                                ],
                                onTap: () => context.push('/resource/${r.id}'),
                                trailing: IconButton(
                                  tooltip: 'Delete paper',
                                  icon: const Icon(Icons.delete_outline, size: 19),
                                  onPressed: () => _deletePaper(r),
                                ),
                              ),
                    ]),
                    if (page.hasMore) ...[
                      const SizedBox(height: Gap.snug),
                      Text('Showing the first ${page.items.length}. Search to narrow the list, or show more.',
                          style: t.bodySmall),
                      const SizedBox(height: Gap.tight),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton(
                          onPressed: items.isLoading
                              ? null
                              : () => ref.read(libraryLimitProvider.notifier).state += libraryPageSize,
                          child: Text(items.isLoading ? 'Loading' : 'Show more'),
                        ),
                      ),
                    ],
                  ]),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}
