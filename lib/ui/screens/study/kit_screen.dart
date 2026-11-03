import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/study.dart';
import '../../../state/study_providers.dart';
import '../../widgets/study_widgets.dart';
import 'kit_flashcards_tab.dart';
import 'kit_guide_tab.dart';
import 'kit_materials_tab.dart';
import 'kit_smart_study_tab.dart';
import 'kit_test_tab.dart';
import 'kit_widgets.dart';

/// One study kit, with its five parts along the bottom: Materials, Study
/// guide, Smart study, Flashcards and Test. Opened with ?build=1 right
/// after the kit is made, which starts building it with AI.
class KitScreen extends ConsumerStatefulWidget {
  const KitScreen({super.key, required this.noteId, this.initialTab = 0, this.autoBuild = false});
  final String noteId;
  final int initialTab;
  final bool autoBuild;

  @override
  ConsumerState<KitScreen> createState() => _KitScreenState();
}

class _KitScreenState extends ConsumerState<KitScreen> {
  late int _tab = widget.initialTab.clamp(0, _tabs.length - 1);
  String? _error;

  static const _tabs = [
    (icon: Icons.folder_open_outlined, active: Icons.folder_open, label: 'Materials'),
    (icon: Icons.menu_book_outlined, active: Icons.menu_book, label: 'Study guide'),
    (icon: Icons.bolt_outlined, active: Icons.bolt, label: 'Smart study'),
    (icon: Icons.style_outlined, active: Icons.style, label: 'Flashcards'),
    (icon: Icons.assignment_outlined, active: Icons.assignment, label: 'Test'),
  ];

  @override
  void initState() {
    super.initState();
    if (widget.autoBuild) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final ok = await buildKitWithAi(context, ref, widget.noteId);
        if (ok && mounted) setState(() => _tab = 1);
      });
    }
  }

  void _refresh() => refreshKit(ref, widget.noteId);

  Future<void> _rename(Note note) async {
    final title = await askForTitle(context,
        heading: 'Rename kit', confirmLabel: 'Save', initial: note.title, maxLength: StudyLimits.noteTitle);
    if (title == null) return;
    await _attempt(() => studyRepo.renameKit(note.id, title));
  }

  Future<void> _recolour(Note note) async {
    final picked = await showDialog<KitColor>(
      context: context,
      builder: (ctx) => StudyScope(
        child: AlertDialog(
          title: const Text('Kit colour'),
          content: Wrap(
            spacing: Gap.snug,
            runSpacing: Gap.snug,
            children: [
              for (final k in KitColor.values)
                Semantics(
                  button: true,
                  label: k.label,
                  selected: k == note.color,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => Navigator.pop(ctx, k),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: KitPalette.fill(k.wire),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: k == note.color ? StudyColors.of(ctx).ink : StudyColors.of(ctx).line, width: 2.5),
                      ),
                      child: k == note.color ? Icon(Icons.check, color: KitPalette.onFill(k.wire)) : null,
                    ),
                  ),
                ),
            ],
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel'))],
        ),
      ),
    );
    if (picked == null || picked == note.color) return;
    await _attempt(() => studyRepo.setKitColor(note.id, picked));
  }

  Future<void> _delete(Note note) async {
    final ok = await confirmDelete(context,
        what: 'this study kit',
        consequence: 'Its study guide is deleted. Its flashcards, questions and test scores stay in your Study page '
            'under "Other decks and question banks".');
    if (!ok) return;
    try {
      await studyRepo.deleteNote(note);
      if (!mounted) return;
      _refresh();
      context.pop();
    } on Failure catch (f) {
      if (mounted) setState(() => _error = f.message);
    }
  }

  Future<void> _attempt(Future<void> Function() action) async {
    try {
      await action();
      if (!mounted) return;
      setState(() => _error = null);
      _refresh();
    } on Failure catch (f) {
      if (mounted) setState(() => _error = f.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(kitProvider(widget.noteId));
    final kit = async.valueOrNull;
    return StudyScope(
      child: Builder(builder: (context) {
        final c = StudyColors.of(context);
        return Scaffold(
          appBar: StudyTopBar(
            title: kit?.note.title ?? 'Study kit',
            actions: [
              if (kit != null)
                PopupMenuButton<String>(
                  tooltip: 'Kit options',
                  icon: const Icon(Icons.more_vert),
                  onSelected: (v) {
                    switch (v) {
                      case 'rename':
                        unawaited(_rename(kit.note));
                      case 'colour':
                        unawaited(_recolour(kit.note));
                      case 'build':
                        unawaited(buildKitWithAi(context, ref, kit.note.id));
                      default:
                        unawaited(_delete(kit.note));
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'rename', child: Text('Rename')),
                    const PopupMenuItem(value: 'colour', child: Text('Change colour')),
                    if (kit.note.hasMaterials)
                      PopupMenuItem(
                          value: 'build', child: Text(kit.guide == null ? 'Build with AI' : 'Build again with AI')),
                    const PopupMenuItem(value: 'delete', child: Text('Delete kit')),
                  ],
                ),
            ],
          ),
          body: Column(
            children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(Gap.page, Gap.snug, Gap.page, 0),
                  child: InlineNotice(_error!, error: true, onClose: () => setState(() => _error = null)),
                ),
              Expanded(
                child: StudyAsync<KitData?>(
                  value: async,
                  onRetry: () => ref.invalidate(kitProvider(widget.noteId)),
                  skeleton: const StudyPage(children: [TextSkeleton(paragraphs: 3)]),
                  isEmpty: (k) => k == null,
                  empty: const StudyPage(children: [
                    StudyEmptyState('This study kit could not be found. It may have been deleted.'),
                  ]),
                  data: (k) {
                    final data = k!;
                    return IndexedStack(
                      index: _tab,
                      children: [
                        KitMaterialsTab(kit: data, onChanged: _refresh, onOpenTab: (i) => setState(() => _tab = i)),
                        KitGuideTab(kit: data, onChanged: _refresh),
                        KitSmartStudyTab(kit: data, onChanged: _refresh),
                        KitFlashcardsTab(kit: data, onChanged: _refresh),
                        KitTestTab(kit: data, onChanged: _refresh),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
          bottomNavigationBar: Container(
            decoration: BoxDecoration(
              color: c.surface,
              border: Border(top: BorderSide(color: c.line)),
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                height: 64,
                child: Row(
                  children: [
                    for (var i = 0; i < _tabs.length; i++)
                      Expanded(
                        child: Semantics(
                          selected: i == _tab,
                          button: true,
                          label: _tabs[i].label,
                          child: InkWell(
                            onTap: () => setState(() => _tab = i),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(i == _tab ? _tabs[i].active : _tabs[i].icon,
                                    size: 22, color: i == _tab ? c.accent : c.inkFaint),
                                const SizedBox(height: 3),
                                Text(
                                  _tabs[i].label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: i == _tab ? FontWeight.w600 : FontWeight.w500,
                                    color: i == _tab ? c.accent : c.inkFaint,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// Shows a message from a kit action as a brief bar at the bottom.
void kitToast(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
}
