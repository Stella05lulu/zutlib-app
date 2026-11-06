import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';

/// Building blocks shared by the study screens. All colours come from
/// [StudyColors]; none are written here.

final studyDate = DateFormat('d MMM yyyy');
final studyDateTime = DateFormat('d MMM yyyy, HH:mm');

// ------------------------------------------------------------------ bars

/// A screen's top bar: back arrow, a left-aligned title, actions, and a
/// hairline underneath.
class StudyTopBar extends StatelessWidget implements PreferredSizeWidget {
  const StudyTopBar({super.key, required this.title, this.actions = const []});
  final String title;
  final List<Widget> actions;

  @override
  Size get preferredSize => const Size.fromHeight(57);

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    final canPop = Navigator.of(context).canPop();
    return Material(
      color: c.canvas,
      child: SafeArea(
        bottom: false,
        child: Container(
          height: 56,
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
          padding: EdgeInsets.only(left: canPop ? Gap.hair : Gap.page, right: Gap.hair),
          child: Row(
            children: [
              if (canPop)
                IconButton(
                  tooltip: 'Back',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              Expanded(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    // Screen titles in the serif section style.
                    style: Theme.of(context).textTheme.titleLarge),
              ),
              ...actions,
            ],
          ),
        ),
      ),
    );
  }
}

/// A heading for a group on a screen, with an optional action on the right.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.action, this.top = Gap.section});
  final String text;
  final Widget? action;
  final double top;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: top, bottom: Gap.tight),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Section headings use the serif heading style (see the type
            // scale in app_theme.dart).
            Expanded(child: Text(text, style: Theme.of(context).textTheme.titleLarge)),
            if (action != null) action!,
          ],
        ),
      );
}

// ------------------------------------------------------------------ rows

/// A bordered panel holding rows separated by hairlines.
class RowGroup extends StatelessWidget {
  const RowGroup({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.panel),
        border: Border.all(color: c.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, color: c.line),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// One row: a title, an optional line of detail, machine values on the
/// right, and an optional trailing control.
class StudyRow extends StatelessWidget {
  const StudyRow({
    super.key,
    required this.title,
    this.detail,
    this.meta,
    this.tags = const [],
    this.trailing,
    this.onTap,
    this.detailLines = 2,
  });

  final String title;
  final String? detail;
  final String? meta;
  final List<Widget> tags;
  final Widget? trailing;
  final VoidCallback? onTap;
  final int detailLines;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.page - 4, Gap.row, Gap.snug, Gap.row),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: t.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (detail != null && detail!.isNotEmpty) ...[
                    const SizedBox(height: Gap.hair),
                    Text(detail!, style: t.bodyMedium, maxLines: detailLines, overflow: TextOverflow.ellipsis),
                  ],
                  if (meta != null || tags.isNotEmpty) ...[
                    const SizedBox(height: Gap.tight),
                    Wrap(
                      spacing: Gap.tight,
                      runSpacing: Gap.hair,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ...tags,
                        if (meta != null) Text(meta!, style: Mono.of(context, size: 12)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: Gap.tight), trailing!],
          ],
        ),
      ),
    );
  }
}

/// A small label in the mono face. [sky] draws it in the light blue;
/// [Tag.ai] is the label on anything Gemini made.
class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.sky = false});
  const Tag.ai({super.key})
      : text = 'AI',
        sky = true;

  final String text;
  final bool sky;

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: sky ? c.skyWash : c.sunken,
        borderRadius: BorderRadius.circular(Radii.tag),
      ),
      child: Text(text,
          style: Mono.of(context, size: 11, weight: FontWeight.w600, color: sky ? c.sky : c.inkSoft)),
    );
  }
}

// ------------------------------------------------------------------ notices

/// A message that stays on the screen next to what it is about, instead
/// of a pop-up that vanishes. [error] uses the danger colour.
class InlineNotice extends StatelessWidget {
  const InlineNotice(this.message, {super.key, this.error = false, this.action, this.onClose});
  final String message;
  final bool error;
  final Widget? action;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    final edge = error ? c.danger : c.sky;
    return Container(
      decoration: BoxDecoration(
        color: error ? c.dangerWash : c.skyWash,
        borderRadius: BorderRadius.circular(Radii.control),
        border: Border(left: BorderSide(color: edge, width: 3)),
      ),
      padding: const EdgeInsets.fromLTRB(Gap.snug, Gap.tight + 2, Gap.hair, Gap.tight + 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(message,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: c.ink)),
          ),
          if (action != null) action!,
          if (onClose != null)
            IconButton(
              tooltip: 'Dismiss',
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.close, size: 18, color: c.inkSoft),
              onPressed: onClose,
            ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ four states

/// Shows one of four states for anything loaded from the database:
/// a skeleton shaped like the content while loading, a plain message when
/// it failed (with Try again), [empty] when there is nothing yet, and the
/// content otherwise.
class StudyAsync<T> extends StatelessWidget {
  const StudyAsync({
    super.key,
    required this.value,
    required this.skeleton,
    required this.data,
    this.isEmpty,
    this.empty,
    this.onRetry,
  });

  final AsyncValue<T> value;
  final Widget skeleton;
  final Widget Function(T value) data;
  final bool Function(T value)? isEmpty;
  final Widget? empty;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    // Keep showing the last good content while a refresh is under way.
    if (value.hasValue && !value.hasError) {
      final v = value.requireValue;
      if (empty != null && isEmpty != null && isEmpty!(v)) return empty!;
      return data(v);
    }
    if (value.hasError) {
      return StudyErrorState(message: '${value.error}', onRetry: onRetry);
    }
    return skeleton;
  }
}

/// The empty state: one plain sentence, and the action that fixes it.
class StudyEmptyState extends StatelessWidget {
  const StudyEmptyState(this.sentence, {super.key, this.action, this.compact = false});
  final String sentence;
  final Widget? action;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: Gap.page, vertical: compact ? Gap.page : Gap.wide),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.panel),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(sentence, style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: c.inkSoft)),
          if (action != null) ...[const SizedBox(height: Gap.snug + 4), action!],
        ],
      ),
    );
  }
}

class StudyErrorState extends StatelessWidget {
  const StudyErrorState({super.key, required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => InlineNotice(
        message,
        error: true,
        action: onRetry == null
            ? null
            : TextButton(onPressed: onRetry, child: const Text('Try again')),
      );
}

// ------------------------------------------------------------------ skeletons

/// A flat block standing in for text that has not arrived yet.
class Bone extends StatelessWidget {
  const Bone({super.key, this.width, this.height = 12, this.radius = Radii.tag});
  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
        width: width ?? double.infinity,
        height: height,
        decoration: BoxDecoration(
          color: StudyColors.of(context).sunken,
          borderRadius: BorderRadius.circular(radius),
        ),
      );
}

/// Placeholder rows shaped like [StudyRow]s inside a [RowGroup].
class RowsSkeleton extends StatelessWidget {
  const RowsSkeleton({super.key, this.rows = 4, this.detail = true});
  final int rows;
  final bool detail;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: RowGroup(children: [
          for (var i = 0; i < rows; i++)
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.page - 4, Gap.row + 2, Gap.wide, Gap.row + 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Bone(width: 150.0 + (i % 3) * 40, height: 15),
                  if (detail) ...[
                    const SizedBox(height: Gap.tight),
                    const Bone(height: 11),
                    const SizedBox(height: 6),
                    Bone(width: 120.0 + (i % 2) * 60, height: 11),
                  ],
                  const SizedBox(height: Gap.snug),
                  const Bone(width: 70, height: 10),
                ],
              ),
            ),
        ]),
      );
}

/// Placeholder for a page of reading text: a title and paragraphs.
class TextSkeleton extends StatelessWidget {
  const TextSkeleton({super.key, this.paragraphs = 3});
  final int paragraphs;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Bone(width: 240, height: 22),
            const SizedBox(height: Gap.snug),
            const Bone(width: 110, height: 11),
            for (var p = 0; p < paragraphs; p++) ...[
              const SizedBox(height: Gap.page),
              const Bone(height: 12),
              const SizedBox(height: 7),
              const Bone(height: 12),
              const SizedBox(height: 7),
              Bone(width: 180.0 + p * 30, height: 12),
            ],
          ],
        ),
      );
}

/// Placeholder shaped like a flashcard in study mode.
class FlashcardSkeleton extends StatelessWidget {
  const FlashcardSkeleton({super.key});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Bone(width: 60, height: 12),
            const SizedBox(height: Gap.snug),
            Container(
              height: 260,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Radii.panel),
                border: Border.all(color: StudyColors.of(context).line),
              ),
              padding: const EdgeInsets.all(Gap.section),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [Bone(width: 220, height: 16), SizedBox(height: 10), Bone(width: 160, height: 16)],
              ),
            ),
            const SizedBox(height: Gap.page),
            const Bone(height: 46, radius: Radii.control),
          ],
        ),
      );
}

/// Placeholder shaped like one quiz question with its options.
class QuestionSkeleton extends StatelessWidget {
  const QuestionSkeleton({super.key});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Bone(width: 80, height: 11),
            const SizedBox(height: Gap.snug),
            const Bone(height: 18),
            const SizedBox(height: 8),
            const Bone(width: 200, height: 18),
            const SizedBox(height: Gap.section),
            for (var i = 0; i < 4; i++) ...[
              const Bone(height: 50, radius: Radii.control),
              const SizedBox(height: Gap.tight + 2),
            ],
          ],
        ),
      );
}

// ------------------------------------------------------------------ dialogs

/// Asks before deleting. Returns true only if the student confirms.
Future<bool> confirmDelete(BuildContext context, {required String what, String? consequence}) async {
  final c = StudyColors.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Delete $what?'),
      content: Text(consequence ?? 'This cannot be undone.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep it')),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: c.danger),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Asks for a short title (for a new or renamed deck or quiz).
Future<String?> askForTitle(
  BuildContext context, {
  required String heading,
  required String confirmLabel,
  String initial = '',
  required int maxLength,
}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => _TitleDialog(
      heading: heading,
      confirmLabel: confirmLabel,
      initial: initial,
      maxLength: maxLength,
    ),
  );
}

class _TitleDialog extends StatefulWidget {
  const _TitleDialog({
    required this.heading,
    required this.confirmLabel,
    required this.initial,
    required this.maxLength,
  });
  final String heading, confirmLabel, initial;
  final int maxLength;

  @override
  State<_TitleDialog> createState() => _TitleDialogState();
}

class _TitleDialogState extends State<_TitleDialog> {
  late final TextEditingController _ctl = TextEditingController(
      text: widget.initial.length > widget.maxLength
          ? widget.initial.substring(0, widget.maxLength)
          : widget.initial);
  String? _error;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _ctl.text.trim();
    if (v.isEmpty) {
      setState(() => _error = 'Give it a title.');
      return;
    }
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.heading),
        content: TextField(
          controller: _ctl,
          autofocus: true,
          maxLength: widget.maxLength,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: 'Title', errorText: _error),
          onSubmitted: (_) => _submit(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
        ],
      );
}

/// Width-limited, padded scrolling page body used by every study screen.
class StudyPage extends StatelessWidget {
  const StudyPage({
    super.key,
    required this.children,
    this.bottom = Gap.wide,
    this.onRefresh,
    this.maxWidth = 760,
  });

  final List<Widget> children;
  final double bottom;
  final Future<void> Function()? onRefresh;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(Gap.page, Gap.page, Gap.page, bottom),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ),
      ],
    );
    if (onRefresh == null) return list;
    return RefreshIndicator(onRefresh: onRefresh!, child: list);
  }
}
