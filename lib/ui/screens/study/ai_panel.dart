import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/study.dart';
import '../../../state/study_providers.dart';
import '../../widgets/study_widgets.dart';

/// AI help for one note: summarise it, make flashcards, or make a quiz.
///
/// The app only sends the note's id. The study-generate Edge Function
/// reads the note itself, checks the daily limit, and holds the Gemini
/// key; nothing secret is in the app. While a request runs the panel says
/// what is happening; if it fails, the reason stays on the panel in plain
/// words. Writing notes, cards and quizzes by hand works whether or not
/// AI is available.
class AiPanel extends ConsumerStatefulWidget {
  const AiPanel({super.key, required this.note});
  final Note note;

  @override
  ConsumerState<AiPanel> createState() => _AiPanelState();
}

class _AiPanelState extends ConsumerState<AiPanel> {
  StudyKind? _running;
  String? _error;
  String? _done;

  String _working(StudyKind k) {
    final what = widget.note.hasPdf ? 'this PDF' : 'this note';
    return switch (k) {
      StudyKind.summary => 'Writing a summary of $what.',
      StudyKind.flashcards => 'Making flashcards from $what.',
      StudyKind.quiz => 'Writing quiz questions from $what.',
      StudyKind.kit => 'Building a study kit from $what.',
    };
  }

  Future<void> _generate(StudyKind kind) async {
    setState(() {
      _running = kind;
      _error = null;
      _done = null;
    });
    try {
      final result = await studyRepo.generate(kind, widget.note.id);
      if (!mounted) return;
      refreshStudy(ref, noteId: widget.note.id);
      ref.invalidate(aiStatusProvider);
      final fromCache = result.cached
          ? ' The note has not changed since last time, so this was made earlier and no request was used.'
          : '';
      final what = switch (kind) {
        StudyKind.summary => 'Summary added below.',
        StudyKind.flashcards => 'Flashcard deck ready.',
        StudyKind.quiz => 'Quiz ready.',
        StudyKind.kit => 'Study kit ready.',
      };
      setState(() {
        _running = null;
        _done = what + fromCache;
      });
      if (kind == StudyKind.flashcards) unawaited(context.push('/study/deck/${result.id}'));
      if (kind == StudyKind.quiz) unawaited(context.push('/study/quiz/${result.id}'));
    } on Failure catch (f) {
      if (!mounted) return;
      ref.invalidate(aiStatusProvider);
      setState(() {
        _running = null;
        _error = f.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    final t = Theme.of(context).textTheme;
    final status = ref.watch(aiStatusProvider);
    final remaining = status.valueOrNull?.remaining;
    final busy = _running != null;
    // If the allowance could not be checked, let the student try anyway:
    // the server enforces the limit whatever the app shows.
    final canRun = !busy && (remaining != null ? remaining > 0 : status.hasError);

    Widget action(StudyKind kind, String label, IconData icon) {
      final primary = kind == StudyKind.summary;
      final child = Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon, size: 18), const SizedBox(width: Gap.tight), Text(label)],
      );
      final onPressed = canRun ? () => _generate(kind) : null;
      return primary
          ? FilledButton(onPressed: onPressed, child: child)
          : OutlinedButton(onPressed: onPressed, child: child);
    }

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
          // A thin bar across the top while a request is running.
          SizedBox(
            height: 3,
            child: busy ? const LinearProgressIndicator(minHeight: 3) : null,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.page - 4, Gap.snug, Gap.page - 4, Gap.page - 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: Text('AI help', style: t.titleMedium)),
                    _Allowance(status: status),
                  ],
                ),
                const SizedBox(height: Gap.hair),
                Text('AI can get things wrong. Check what it writes against your note.',
                    style: t.bodySmall),
                const SizedBox(height: Gap.snug + 2),
                Wrap(
                  spacing: Gap.tight,
                  runSpacing: Gap.tight,
                  children: [
                    action(StudyKind.summary, 'Summarise', Icons.short_text),
                    action(StudyKind.flashcards, 'Make flashcards', Icons.style_outlined),
                    action(StudyKind.quiz, 'Make a quiz', Icons.quiz_outlined),
                  ],
                ),
                if (busy) ...[
                  const SizedBox(height: Gap.snug),
                  Text('${_working(_running!)} This usually takes under a minute.',
                      style: t.bodyMedium?.copyWith(color: c.ink)),
                ],
                if (!busy && remaining == 0) ...[
                  const SizedBox(height: Gap.snug),
                  Text('No AI requests left today. They renew at midnight. '
                      'You can still write summaries, cards and quizzes yourself.',
                      style: t.bodyMedium),
                ],
                if (_error != null) ...[
                  const SizedBox(height: Gap.snug),
                  InlineNotice(_error!, error: true, onClose: () => setState(() => _error = null)),
                ],
                if (_done != null) ...[
                  const SizedBox(height: Gap.snug),
                  InlineNotice(_done!, onClose: () => setState(() => _done = null)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "7 of 10 left today", with the numbers in the mono face.
class _Allowance extends ConsumerWidget {
  const _Allowance({required this.status});
  final AsyncValue<AiStatus> status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = StudyColors.of(context);
    if (status.hasValue) {
      final s = status.requireValue;
      return Semantics(
        label: '${s.remaining} of ${s.dailyLimit} AI requests left today',
        child: ExcludeSemantics(
          child: Text.rich(TextSpan(children: [
            TextSpan(
                text: '${s.remaining}',
                style: Mono.of(context, size: 13, weight: FontWeight.w600,
                    color: s.remaining == 0 ? c.danger : c.ink)),
            TextSpan(text: ' of ', style: Theme.of(context).textTheme.bodySmall),
            TextSpan(text: '${s.dailyLimit}', style: Mono.of(context, size: 13)),
            TextSpan(text: ' left today', style: Theme.of(context).textTheme.bodySmall),
          ])),
        ),
      );
    }
    if (status.hasError) {
      return TextButton(
        onPressed: () => ref.invalidate(aiStatusProvider),
        child: const Text('Check requests left'),
      );
    }
    return const Bone(width: 96, height: 12);
  }
}
