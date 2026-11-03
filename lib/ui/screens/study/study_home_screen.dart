import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/failure.dart';
import '../../../core/theme.dart' show kNavClearance;
import '../../../core/theme/app_theme.dart';
import '../../../models/study.dart';
import '../../../state/study_providers.dart';
import '../../widgets/study_widgets.dart';
import 'kit_widgets.dart';
import 'new_note_sheet.dart';

/// The Study tab: the student's study kits, drawn as course tiles, with a
/// search box and one clear way to start a new kit. Everything here is
/// private to the signed-in student; the database returns nobody else's
/// rows.
class StudyHomeScreen extends ConsumerStatefulWidget {
  const StudyHomeScreen({super.key});

  @override
  ConsumerState<StudyHomeScreen> createState() => _StudyHomeScreenState();
}

class _StudyHomeScreenState extends ConsumerState<StudyHomeScreen> {
  final _search = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(kitListProvider);
    refreshStudy(ref);
    try {
      await ref.read(kitListProvider.future);
    } catch (_) {
      // The list shows its own error state.
    }
  }

  Future<void> _delete(Note note) async {
    final ok = await confirmDelete(context,
        what: 'this study kit',
        consequence: 'Its study guide is deleted. Its flashcards, questions and scores stay under '
            '"Other decks and question banks".');
    if (!ok) return;
    try {
      await studyRepo.deleteNote(note);
      if (mounted) refreshKit(ref, note.id);
    } on Failure catch (f) {
      if (mounted) setState(() => _error = f.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final kits = ref.watch(kitListProvider);
    final query = _search.text.trim().toLowerCase();

    return StudyScope(
      child: Builder(builder: (context) {
        final c = StudyColors.of(context);
        final t = Theme.of(context).textTheme;
        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: StudyPage(
              bottom: kNavClearance,
              maxWidth: 1080,
              onRefresh: _refresh,
              children: [
                const SizedBox(height: Gap.tight),
                Text('Study', style: t.headlineSmall?.copyWith(fontSize: 30, fontWeight: FontWeight.w700)),
                const SizedBox(height: Gap.hair),
                Text('Turn any PDF, video or notes into a study guide, flashcards, practice and tests.',
                    style: t.bodyLarge?.copyWith(color: c.inkSoft)),
                const SizedBox(height: Gap.page),
                _CreateBar(onTap: () => showNewKitSheet(context)),
                const SizedBox(height: Gap.snug),
                TextField(
                  controller: _search,
                  decoration: InputDecoration(
                    hintText: 'Search your kits',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear',
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => setState(_search.clear),
                          ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                if (_error != null) ...[
                  const SizedBox(height: Gap.snug),
                  InlineNotice(_error!, error: true, onClose: () => setState(() => _error = null)),
                ],
                const SizedBox(height: Gap.section),
                StudyAsync<List<KitSummary>>(
                  value: kits,
                  onRetry: () => ref.invalidate(kitListProvider),
                  skeleton: const _GridSkeleton(),
                  isEmpty: (v) => v.isEmpty,
                  empty: KitEmpty(
                    icon: Icons.auto_stories_outlined,
                    title: 'Make your first study kit',
                    sentence: 'Upload lecture notes or a past paper, paste a YouTube lecture, or type your notes. '
                        'AI builds the guide, flashcards and questions in about a minute.',
                    actions: [
                      FilledButton.icon(
                        onPressed: () => showNewKitSheet(context),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Create a study kit'),
                      ),
                    ],
                  ),
                  data: (all) {
                    final shown = query.isEmpty
                        ? all
                        : all
                            .where((k) =>
                                k.note.title.toLowerCase().contains(query) ||
                                (k.note.courseCode ?? '').toLowerCase().contains(query))
                            .toList();
                    if (shown.isEmpty) {
                      return StudyEmptyState('No kit matches "${_search.text.trim()}".', compact: true);
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('My study kits', style: t.titleLarge),
                        const SizedBox(height: Gap.snug),
                        LayoutBuilder(builder: (context, box) {
                          final columns = box.maxWidth >= 900 ? 3 : box.maxWidth >= 560 ? 2 : 1;
                          const gap = Gap.page - 4;
                          final width = (box.maxWidth - gap * (columns - 1)) / columns;
                          return Wrap(
                            spacing: gap,
                            runSpacing: gap,
                            children: [
                              for (final k in shown)
                                SizedBox(
                                  width: width,
                                  child: KitTile(
                                    summary: k,
                                    onTap: () => context.push('/study/note/${k.note.id}'),
                                    menu: PopupMenuButton<String>(
                                      tooltip: 'Kit options',
                                      icon: const Icon(Icons.more_vert),
                                      onSelected: (v) {
                                        if (v == 'delete') {
                                          unawaited(_delete(k.note));
                                        } else {
                                          unawaited(context.push('/study/note/${k.note.id}'));
                                        }
                                      },
                                      itemBuilder: (_) => const [
                                        PopupMenuItem(value: 'open', child: Text('Open')),
                                        PopupMenuItem(value: 'delete', child: Text('Delete')),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          );
                        }),
                      ],
                    );
                  },
                ),
                const _LooseItems(),
              ],
            ),
          ),
        );
      }),
    );
  }
}

/// The wide "Create a study kit" button at the top of the page.
class _CreateBar extends StatelessWidget {
  const _CreateBar({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    final t = Theme.of(context).textTheme;
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.panel + 2),
        side: BorderSide(color: c.accent, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.page, vertical: Gap.page - 2),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: c.accentWash, borderRadius: BorderRadius.circular(Radii.control)),
                child: Icon(Icons.auto_awesome_outlined, color: c.accent),
              ),
              const SizedBox(width: Gap.snug),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Create a study kit', style: t.titleMedium),
                    Text('From a PDF, a YouTube video, pasted notes or the library', style: t.bodySmall),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward, color: c.accent),
            ],
          ),
        ),
      ),
    );
  }
}

class _GridSkeleton extends StatelessWidget {
  const _GridSkeleton();

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: LayoutBuilder(builder: (context, box) {
          final columns = box.maxWidth >= 900 ? 3 : box.maxWidth >= 560 ? 2 : 1;
          const gap = Gap.page - 4;
          final width = (box.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (var i = 0; i < columns * 2; i++)
                SizedBox(
                  width: width,
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Bone(height: 112, radius: Radii.panel),
                      SizedBox(height: Gap.snug),
                      Bone(width: 140, height: 11),
                      SizedBox(height: Gap.tight),
                      Bone(width: 200, height: 11),
                    ],
                  ),
                ),
            ],
          );
        }),
      );
}

/// Decks and question banks that belong to no kit: older ones made before
/// kits existed, or ones whose kit was deleted. They still open as before.
class _LooseItems extends ConsumerWidget {
  const _LooseItems();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final decks = (ref.watch(decksProvider).valueOrNull ?? const <Deck>[]).where((d) => d.noteId == null).toList();
    final quizzes = (ref.watch(quizzesProvider).valueOrNull ?? const <Quiz>[]).where((q) => q.noteId == null).toList();
    if (decks.isEmpty && quizzes.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Other decks and question banks'),
        RowGroup(children: [
          for (final d in decks)
            StudyRow(
              title: d.title,
              meta: '${d.cardCount} ${d.cardCount == 1 ? 'card' : 'cards'}',
              tags: [const Tag('Deck'), if (d.source == StudySource.ai) const Tag.ai()],
              onTap: () => context.push('/study/deck/${d.id}'),
            ),
          for (final q in quizzes)
            StudyRow(
              title: q.title,
              meta: '${q.questionCount} ${q.questionCount == 1 ? 'question' : 'questions'}',
              tags: [const Tag('Questions'), if (q.source == StudySource.ai) const Tag.ai()],
              onTap: () => context.push('/study/quiz/${q.id}'),
            ),
        ]),
      ],
    );
  }
}
