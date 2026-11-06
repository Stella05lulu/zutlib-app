import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/study.dart';
import '../../../state/study_providers.dart';
import '../../../study/practice.dart';
import '../../widgets/study_widgets.dart';
import 'editor_sheets.dart';
import 'kit_widgets.dart';

/// Smart Study: one question at a time, easy questions first, then medium,
/// then hard. Right the first time masters a question (3 stars) and it is
/// not asked again; a wrong answer brings it back later in the same level
/// until it has been answered right twice more (practice.dart).
class KitSmartStudyTab extends ConsumerStatefulWidget {
  const KitSmartStudyTab({super.key, required this.kit, required this.onChanged});
  final KitData kit;
  final VoidCallback onChanged;

  @override
  ConsumerState<KitSmartStudyTab> createState() => _KitSmartStudyTabState();
}

class _KitSmartStudyTabState extends ConsumerState<KitSmartStudyTab> {
  final _rng = Random();
  late Map<String, int> _stars = {...widget.kit.stars};
  final _recent = <String>[];
  String? _currentId;
  int? _chosen;
  bool _revealed = false;
  bool _rated = false;
  String? _error;

  List<QuizQuestion> get _questions => widget.kit.questions;
  Map<String, int> get _difficulty => {for (final q in _questions) q.id: q.difficulty};

  @override
  void initState() {
    super.initState();
    _pickNext();
  }

  @override
  void didUpdateWidget(KitSmartStudyTab old) {
    super.didUpdateWidget(old);
    final before = old.kit.questions.map((q) => q.id).join(',');
    final now = widget.kit.questions.map((q) => q.id).join(',');
    if (before != now) {
      _stars = {...widget.kit.stars};
      _recent.clear();
      _pickNext();
    }
  }

  QuizQuestion? get _current {
    for (final q in _questions) {
      if (q.id == _currentId) return q;
    }
    return null;
  }

  /// Chooses the next question without redrawing (safe in initState).
  void _pickNext() {
    final id = pickNextQuestion([for (final q in _questions) q.id], _stars, _recent, _rng, difficulty: _difficulty);
    _currentId = id;
    _chosen = null;
    _revealed = false;
    _rated = false;
    if (id != null) {
      _recent.add(id);
      if (_recent.length > 3) _recent.removeAt(0);
    }
  }

  void _next() => setState(_pickNext);

  /// Saves the new star count in the background; the screen moves on.
  void _setStars(String id, int stars) {
    final levelBefore = smartLevel(_questions.map((q) => q.id), _stars, difficulty: _difficulty).level;
    setState(() => _stars[id] = stars);
    final levelAfter = smartLevel(_questions.map((q) => q.id), _stars, difficulty: _difficulty).level;
    unawaited(studyRepo.rateQuestion(id, stars).then((_) {
      if (levelAfter != levelBefore && mounted) widget.onChanged();
    }).catchError((Object e) {
      if (mounted) setState(() => _error = e is Failure ? e.message : 'Your progress could not be saved.');
    }));
  }

  void _answer(QuizQuestion q, int index) {
    if (_revealed) return;
    final correct = index == q.correctIndex;
    setState(() {
      _chosen = index;
      _revealed = true;
      _rated = true;
    });
    _setStars(q.id, Stars.afterAnswer(_stars[q.id] ?? 0, correct: correct));
  }

  void _thumb(QuizQuestion q, {required bool up}) {
    if (_rated) {
      _next();
      return;
    }
    _setStars(q.id, Stars.afterAnswer(_stars[q.id] ?? 0, correct: up));
    if (up) {
      _next();
    } else {
      setState(() {
        _revealed = true;
        _rated = true;
      });
    }
  }

  Future<void> _startAgain() async {
    try {
      await studyRepo.resetStars([for (final q in _questions) q.id]);
      if (!mounted) return;
      _recent.clear();
      setState(() {
        _stars = {};
        _pickNext();
      });
      widget.onChanged();
    } on Failure catch (f) {
      if (mounted) setState(() => _error = f.message);
    }
  }

  Future<void> _addQuestion() async {
    final kit = widget.kit;
    await editQuestion(context, onSave: (d) async {
      final quiz = kit.quiz ?? await studyRepo.createQuiz('${kit.note.title} questions', noteId: kit.note.id);
      await studyRepo.addQuestion(quiz.id,
          prompt: d.prompt,
          options: d.options,
          correctIndex: d.correctIndex,
          explanation: d.explanation,
          position: kit.questions.length);
      widget.onChanged();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    final t = Theme.of(context).textTheme;
    final kit = widget.kit;

    if (_questions.isEmpty) {
      return StudyPage(children: [
        KitEmpty(
          icon: Icons.bolt_outlined,
          title: 'Nothing to practise yet',
          sentence: 'Smart Study asks you questions from this kit, again and again, until you know every one.',
          actions: [
            if (kit.note.hasMaterials)
              FilledButton.icon(
                onPressed: () => buildKitWithAi(context, ref, kit.note.id),
                icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                label: const Text('Build with AI'),
              ),
            OutlinedButton(onPressed: _addQuestion, child: const Text('Write a question')),
          ],
        ),
      ]);
    }

    final level = smartLevel(_questions.map((q) => q.id), _stars, difficulty: _difficulty);
    final q = _current;

    return StudyPage(
      children: [
        Row(
          children: [
            Expanded(
              child: LevelBar(
                label: level.complete
                    ? 'All levels done'
                    : 'Level ${level.level} of ${level.levels}: ${level.name}  ${level.percent}%',
                progress: level.complete ? 1 : level.progress,
                stars: level.starsShown,
              ),
            ),
            IconButton(
              tooltip: 'Start again',
              icon: const Icon(Icons.restart_alt),
              onPressed: _startAgain,
            ),
          ],
        ),
        if (!level.complete) ...[
          const SizedBox(height: Gap.tight),
          Text(
            '${level.left} ${level.left == 1 ? 'question' : 'questions'} left at this level  /  '
            '${(level.mastery * 100).round()}% of the kit mastered',
            style: t.bodySmall,
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: Gap.snug),
          InlineNotice(_error!, error: true, onClose: () => setState(() => _error = null)),
        ],
        const SizedBox(height: Gap.section),
        if (q == null)
          KitEmpty(
            icon: Icons.emoji_events_outlined,
            title: 'Every question mastered',
            sentence: 'You mastered all ${_questions.length} questions. Take a test to check it sticks.',
            actions: [FilledButton(onPressed: _startAgain, child: const Text('Practise again'))],
          )
        else ...[
          Row(
            children: [
              for (var i = 0; i < Stars.max; i++)
                Icon(i < (_stars[q.id] ?? 0) ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: 16, color: i < (_stars[q.id] ?? 0) ? c.warn : c.lineStrong),
              const SizedBox(width: Gap.tight),
              Text(difficultyName(q.difficulty), style: Mono.of(context, size: 12)),
              const Spacer(),
              Text(
                (_stars[q.id] ?? 0) == 0
                    ? 'New question'
                    : Stars.mastered(_stars[q.id])
                        ? 'Mastered'
                        : 'Missed before: ${Stars.max - (_stars[q.id] ?? 0)} more right to master',
                style: t.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: Gap.tight),
          Text(q.prompt, style: t.titleLarge?.copyWith(fontSize: 21, height: 1.4)),
          const SizedBox(height: Gap.page),
          for (var i = 0; i < q.options.length; i++) ...[
            _Option(
              text: q.options[i],
              state: !_revealed
                  ? _OptionState.idle
                  : i == q.correctIndex
                      ? _OptionState.right
                      : i == _chosen
                          ? _OptionState.wrong
                          : _OptionState.faded,
              onTap: _revealed ? null : () => _answer(q, i),
            ),
            const SizedBox(height: Gap.tight + 2),
          ],
          if (_revealed && (q.explanation ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: Gap.tight),
            InlineNotice(q.explanation!),
          ],
          const SizedBox(height: Gap.page),
          Row(
            children: [
              if (!_revealed)
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: c.ink, foregroundColor: c.canvas,
                      shape: const StadiumBorder()),
                  // Looking at the answer counts as a miss, so it comes back.
                  onPressed: () {
                    setState(() {
                      _revealed = true;
                      _rated = true;
                    });
                    _setStars(q.id, Stars.afterAnswer(_stars[q.id] ?? 0, correct: false));
                  },
                  child: const Text('Show answer'),
                )
              else
                FilledButton(
                  style: FilledButton.styleFrom(shape: const StadiumBorder()),
                  onPressed: _next,
                  child: const Text('Next question'),
                ),
              const Spacer(),
              _RoundButton(
                tooltip: 'I knew this',
                icon: Icons.thumb_up_alt_outlined,
                color: c.success,
                wash: c.successWash,
                onTap: () => _thumb(q, up: true),
              ),
              const SizedBox(width: Gap.tight),
              _RoundButton(
                tooltip: 'I did not know this',
                icon: Icons.thumb_down_alt_outlined,
                color: c.danger,
                wash: c.dangerWash,
                onTap: () => _thumb(q, up: false),
              ),
            ],
          ),
          if (!_revealed) ...[
            const SizedBox(height: Gap.snug),
            Center(
              child: TextButton(onPressed: _next, child: const Text('Skip')),
            ),
          ],
        ],
      ],
    );
  }
}

enum _OptionState { idle, right, wrong, faded }

class _Option extends StatelessWidget {
  const _Option({required this.text, required this.state, required this.onTap});
  final String text;
  final _OptionState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    final t = Theme.of(context).textTheme;
    final (bg, edge, ink, icon) = switch (state) {
      _OptionState.right => (c.successWash, c.success, c.ink, Icons.check_circle_outline),
      _OptionState.wrong => (c.dangerWash, c.danger, c.ink, Icons.cancel_outlined),
      _OptionState.faded => (c.surface, c.line, c.inkFaint, null),
      _OptionState.idle => (c.sunken, c.sunken, c.ink, null),
    };
    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.control + 2),
        side: BorderSide(color: edge, width: state == _OptionState.idle ? 1 : 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.page - 4, vertical: Gap.row + 2),
          child: Row(
            children: [
              Expanded(child: Text(text, style: t.bodyLarge?.copyWith(color: ink))),
              if (icon != null) ...[const SizedBox(width: Gap.tight), Icon(icon, color: edge, size: 22)],
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.tooltip, required this.icon, required this.color, required this.wash, required this.onTap});
  final String tooltip;
  final IconData icon;
  final Color color, wash;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Material(
          color: wash,
          shape: CircleBorder(side: BorderSide(color: color, width: 1.5)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(width: 48, height: 48, child: Icon(icon, color: color, size: 22)),
          ),
        ),
      );
}
