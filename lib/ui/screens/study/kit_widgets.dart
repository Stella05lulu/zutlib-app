import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/study.dart';
import '../../../state/study_providers.dart';
import '../../widgets/study_widgets.dart';

/// Pieces shared by the study kit screens.

/// The icon for what a kit is built on.
IconData kitSourceIcon(Note n) => n.hasVideo
    ? Icons.smart_display_outlined
    : n.hasLibraryPdf
        ? Icons.local_library_outlined
        : n.hasUpload
            ? Icons.picture_as_pdf_outlined
            : n.body.trim().isNotEmpty
                ? Icons.notes_outlined
                : Icons.auto_stories_outlined;

/// A kit in the kit list, drawn like a course tile in an online-learning
/// catalogue: a solid colour block with the title, then what is inside.
class KitTile extends StatelessWidget {
  const KitTile({super.key, required this.summary, required this.onTap, this.menu});
  final KitSummary summary;
  final VoidCallback onTap;
  final Widget? menu;

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    final t = Theme.of(context).textTheme;
    final n = summary.note;
    final fill = KitPalette.fill(n.color.wire);
    final on = KitPalette.onFill(n.color.wire);
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.panel + 2),
        side: BorderSide(color: c.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 112,
              child: ColoredBox(
                color: fill,
                child: Stack(
                  children: [
                    Positioned(
                      right: -14,
                      bottom: -22,
                      child: Icon(kitSourceIcon(n), size: 118, color: on.withValues(alpha: 0.16)),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Gap.row + 2, Gap.row, Gap.wide, Gap.row),
                      child: Text(
                        n.title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: t.titleMedium?.copyWith(color: on, fontSize: 17, fontWeight: FontWeight.w700, height: 1.25),
                      ),
                    ),
                    if (menu != null)
                      Positioned(
                        top: 2,
                        right: 2,
                        child: IconTheme(data: IconThemeData(color: on), child: menu!),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.row + 2, Gap.snug, Gap.snug, Gap.row),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    [n.sourceLabel, if (n.courseCode != null) n.courseCode!].join('  /  '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodySmall,
                  ),
                  const SizedBox(height: Gap.tight),
                  Wrap(
                    spacing: Gap.tight,
                    runSpacing: Gap.hair,
                    children: [
                      _Count(Icons.style_outlined, '${summary.cardCount} ${summary.cardCount == 1 ? 'card' : 'cards'}'),
                      _Count(Icons.quiz_outlined,
                          '${summary.questionCount} ${summary.questionCount == 1 ? 'question' : 'questions'}'),
                      if (summary.hasGuide) const _Count(Icons.menu_book_outlined, 'Guide'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: c.inkFaint),
        const SizedBox(width: 4),
        Text(label, style: Mono.of(context, size: 12)),
      ],
    );
  }
}

/// A row of pill-shaped choices, such as List / Deck / Games.
class KitSegments extends StatelessWidget {
  const KitSegments({super.key, required this.labels, required this.index, required this.onChanged});
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.sunken,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < labels.length; i++)
            Semantics(
              selected: i == index,
              button: true,
              child: GestureDetector(
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(horizontal: Gap.page - 4, vertical: Gap.tight),
                  decoration: BoxDecoration(
                    color: i == index ? c.surface : c.sunken,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: i == index ? c.lineStrong : c.sunken),
                  ),
                  child: Text(
                    labels[i],
                    style: t.labelLarge?.copyWith(
                      fontSize: 13.5,
                      color: i == index ? c.ink : c.inkSoft,
                      fontWeight: i == index ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// "Level 2: 40%" on a progress bar, with up to three stars beside it.
class LevelBar extends StatelessWidget {
  const LevelBar({super.key, required this.label, required this.progress, required this.stars});
  final String label;
  final double progress;
  final int stars;

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    return Row(
      children: [
        Expanded(
          child: Semantics(
            label: label,
            child: Container(
              height: 30,
              decoration: BoxDecoration(color: c.sunken, borderRadius: BorderRadius.circular(999)),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: progress.clamp(0.0, 1.0),
                    child: Container(color: c.accentWash),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Gap.snug),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(label, style: Mono.of(context, size: 12.5, weight: FontWeight.w600, color: c.ink)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: Gap.tight),
        for (var i = 0; i < 3; i++)
          Icon(i < stars ? Icons.star_rounded : Icons.star_outline_rounded,
              size: 24, color: i < stars ? c.warn : c.lineStrong),
      ],
    );
  }
}

/// A round percentage, as shown while a kit is being made.
class ProgressRing extends StatelessWidget {
  const ProgressRing({super.key, required this.value, this.size = 140});
  final double value;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: value.clamp(0.0, 1.0),
              strokeWidth: 6,
              color: c.accent,
              backgroundColor: c.sunken,
            ),
          ),
          Text('${(value * 100).floor()}%',
              style: Mono.of(context, size: size / 5.5, weight: FontWeight.w600, color: c.accent)),
        ],
      ),
    );
  }
}

/// Asks the server to build the whole kit (study guide, flashcards and
/// question bank) in one AI request, showing a percentage while it works.
/// Returns true when the kit was made or found ready-made in the cache.
Future<bool> buildKitWithAi(BuildContext context, WidgetRef ref, String noteId) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => StudyScope(child: _KitBuilderDialog(noteId: noteId)),
  );
  refreshKit(ref, noteId);
  return ok ?? false;
}

class _KitBuilderDialog extends StatefulWidget {
  const _KitBuilderDialog({required this.noteId});
  final String noteId;

  @override
  State<_KitBuilderDialog> createState() => _KitBuilderDialogState();
}

class _KitBuilderDialogState extends State<_KitBuilderDialog> {
  double _value = 0.02;
  String? _error;
  bool _done = false;
  Timer? _tick;

  static const _stages = [
    'Reading your materials',
    'Writing the study guide',
    'Making flashcards',
    'Writing practice questions',
    'Checking everything',
  ];

  @override
  void initState() {
    super.initState();
    // A kit usually takes 20 to 60 seconds. The ring eases towards 95%
    // and jumps to 100% when the answer arrives; it is a guide, not a
    // measurement.
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted || _done || _error != null) return;
      setState(() => _value = min(0.95, _value + (0.95 - _value) * 0.012));
    });
    unawaited(_run());
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _run() async {
    try {
      await studyRepo.generate(StudyKind.kit, widget.noteId);
      if (!mounted) return;
      setState(() {
        _done = true;
        _value = 1;
      });
      await Future<void>.delayed(const Duration(milliseconds: 450));
      if (mounted) Navigator.pop(context, true);
    } on Failure catch (f) {
      if (mounted) setState(() => _error = f.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final stage = _stages[min((_value / 0.95 * _stages.length).floor(), _stages.length - 1)];
    return AlertDialog(
      contentPadding: const EdgeInsets.fromLTRB(Gap.section, Gap.section, Gap.section, Gap.page),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error == null) ...[
              ProgressRing(value: _value),
              const SizedBox(height: Gap.page),
              Text(_done ? 'Your study kit is ready' : stage, style: t.titleMedium, textAlign: TextAlign.center),
              const SizedBox(height: Gap.hair),
              Text('This uses one of today\'s AI requests and can take up to a minute.',
                  style: t.bodySmall, textAlign: TextAlign.center),
            ] else ...[
              InlineNotice(_error!, error: true),
              const SizedBox(height: Gap.page),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(onPressed: () => Navigator.pop(context, false), child: const Text('Close')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A big friendly empty state for a kit tab, with the one action that
/// fills it.
class KitEmpty extends StatelessWidget {
  const KitEmpty({super.key, required this.icon, required this.title, required this.sentence, this.actions = const []});
  final IconData icon;
  final String title;
  final String sentence;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    final t = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: Gap.page, vertical: Gap.wide),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.panel),
        border: Border.all(color: c.line),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: c.accentWash, shape: BoxShape.circle),
            child: Icon(icon, color: c.accent, size: 28),
          ),
          const SizedBox(height: Gap.snug),
          Text(title, style: t.titleMedium, textAlign: TextAlign.center),
          const SizedBox(height: Gap.hair),
          Text(sentence, style: t.bodyMedium, textAlign: TextAlign.center),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: Gap.page),
            Wrap(spacing: Gap.tight, runSpacing: Gap.tight, alignment: WrapAlignment.center, children: actions),
          ],
        ],
      ),
    );
  }
}
