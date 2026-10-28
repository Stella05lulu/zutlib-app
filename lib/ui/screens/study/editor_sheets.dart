import 'package:flutter/material.dart';

import '../../../core/failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/study.dart';
import '../../widgets/study_widgets.dart';

/// The small editors that slide up from the bottom: a summary, a
/// flashcard, a quiz question. Each one runs [onSave] itself and stays
/// open with the error shown inline if saving fails, so nothing typed is
/// lost.

Future<bool?> _showSheet(BuildContext context, Widget sheet) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.panel)),
    ),
    builder: (_) => sheet,
  );
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({
    required this.heading,
    required this.children,
    required this.saving,
    required this.onSave,
    this.error,
  });

  final String heading;
  final List<Widget> children;
  final bool saving;
  final VoidCallback onSave;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Gap.page, Gap.page, Gap.page, Gap.section),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(heading, style: Theme.of(context).textTheme.titleMedium)),
                    TextButton(
                      onPressed: saving ? null : () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: Gap.hair),
                    FilledButton(onPressed: saving ? null : onSave, child: Text(saving ? 'Saving' : 'Save')),
                  ],
                ),
                const SizedBox(height: Gap.page),
                if (error != null) ...[
                  InlineNotice(error!, error: true),
                  const SizedBox(height: Gap.snug),
                ],
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ summary

/// Returns true if a summary was saved.
Future<bool?> editSummary(
  BuildContext context, {
  String initial = '',
  required Future<void> Function(String body) onSave,
}) =>
    _showSheet(context, _SummarySheet(initial: initial, onSave: onSave));

class _SummarySheet extends StatefulWidget {
  const _SummarySheet({required this.initial, required this.onSave});
  final String initial;
  final Future<void> Function(String body) onSave;

  @override
  State<_SummarySheet> createState() => _SummarySheetState();
}

class _SummarySheetState extends State<_SummarySheet> {
  late final _ctl = TextEditingController(text: widget.initial);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final body = _ctl.text.trim();
    if (body.isEmpty) {
      setState(() => _error = 'Write the summary first.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(body);
      if (mounted) Navigator.pop(context, true);
    } on Failure catch (f) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = f.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => _SheetFrame(
        heading: widget.initial.isEmpty ? 'Write a summary' : 'Edit summary',
        saving: _saving,
        error: _error,
        onSave: _save,
        children: [
          TextField(
            controller: _ctl,
            autofocus: true,
            minLines: 6,
            maxLines: 14,
            maxLength: StudyLimits.summary,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'The main points of this note, in your own words.',
            ),
          ),
        ],
      );
}

// ------------------------------------------------------------------ flashcard

Future<bool?> editFlashcard(
  BuildContext context, {
  Flashcard? card,
  required Future<void> Function(String front, String back) onSave,
}) =>
    _showSheet(context, _CardSheet(card: card, onSave: onSave));

class _CardSheet extends StatefulWidget {
  const _CardSheet({required this.card, required this.onSave});
  final Flashcard? card;
  final Future<void> Function(String front, String back) onSave;

  @override
  State<_CardSheet> createState() => _CardSheetState();
}

class _CardSheetState extends State<_CardSheet> {
  late final _front = TextEditingController(text: widget.card?.front ?? '');
  late final _back = TextEditingController(text: widget.card?.back ?? '');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _front.dispose();
    _back.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final front = _front.text.trim();
    final back = _back.text.trim();
    if (front.isEmpty || back.isEmpty) {
      setState(() => _error = 'A card needs both a question and an answer.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(front, back);
      if (mounted) Navigator.pop(context, true);
    } on Failure catch (f) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = f.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => _SheetFrame(
        heading: widget.card == null ? 'New card' : 'Edit card',
        saving: _saving,
        error: _error,
        onSave: _save,
        children: [
          TextField(
            controller: _front,
            autofocus: true,
            minLines: 2,
            maxLines: 5,
            maxLength: StudyLimits.cardFront,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Front (question)'),
          ),
          const SizedBox(height: Gap.tight),
          TextField(
            controller: _back,
            minLines: 2,
            maxLines: 8,
            maxLength: StudyLimits.cardBack,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Back (answer)'),
          ),
        ],
      );
}

// ------------------------------------------------------------------ question

/// What the question editor hands back.
class QuestionDraft {
  const QuestionDraft({
    required this.prompt,
    required this.options,
    required this.correctIndex,
    this.explanation,
  });
  final String prompt;
  final List<String> options;
  final int correctIndex;
  final String? explanation;
}

Future<bool?> editQuestion(
  BuildContext context, {
  QuizQuestion? question,
  required Future<void> Function(QuestionDraft draft) onSave,
}) =>
    _showSheet(context, _QuestionSheet(question: question, onSave: onSave));

class _QuestionSheet extends StatefulWidget {
  const _QuestionSheet({required this.question, required this.onSave});
  final QuizQuestion? question;
  final Future<void> Function(QuestionDraft draft) onSave;

  @override
  State<_QuestionSheet> createState() => _QuestionSheetState();
}

class _QuestionSheetState extends State<_QuestionSheet> {
  late final _prompt = TextEditingController(text: widget.question?.prompt ?? '');
  late final _explanation = TextEditingController(text: widget.question?.explanation ?? '');
  late final List<TextEditingController> _options = [
    for (final o in (widget.question?.options ?? const ['', '', '', ''])) TextEditingController(text: o),
  ];
  late int _correct = widget.question?.correctIndex ?? 0;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _prompt.dispose();
    _explanation.dispose();
    for (final c in _options) {
      c.dispose();
    }
    super.dispose();
  }

  void _addOption() {
    if (_options.length >= StudyLimits.maxOptions) return;
    setState(() => _options.add(TextEditingController()));
  }

  void _removeOption(int i) {
    if (_options.length <= StudyLimits.minOptions) return;
    setState(() {
      _options.removeAt(i).dispose();
      if (_correct == i) {
        _correct = 0;
      } else if (_correct > i) {
        _correct -= 1;
      }
    });
  }

  Future<void> _save() async {
    final prompt = _prompt.text.trim();
    final texts = [for (final c in _options) c.text.trim()];
    String? problem;
    if (prompt.isEmpty) {
      problem = 'Write the question.';
    } else if (texts.any((t) => t.isEmpty)) {
      problem = 'Fill in every option, or remove the empty ones.';
    } else if (texts.map((t) => t.toLowerCase()).toSet().length != texts.length) {
      problem = 'Two options are the same. Make each one different.';
    }
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final explanation = _explanation.text.trim();
      await widget.onSave(QuestionDraft(
        prompt: prompt,
        options: texts,
        correctIndex: _correct,
        explanation: explanation.isEmpty ? null : explanation,
      ));
      if (mounted) Navigator.pop(context, true);
    } on Failure catch (f) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = f.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    return _SheetFrame(
      heading: widget.question == null ? 'New question' : 'Edit question',
      saving: _saving,
      error: _error,
      onSave: _save,
      children: [
        TextField(
          controller: _prompt,
          autofocus: widget.question == null,
          minLines: 2,
          maxLines: 5,
          maxLength: StudyLimits.questionPrompt,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Question'),
        ),
        const SizedBox(height: Gap.tight),
        Text('Options. Tap the circle next to the correct one.',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: Gap.tight),
        for (var i = 0; i < _options.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: Gap.tight),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: _correct == i ? 'Correct answer' : 'Mark as correct',
                  onPressed: () => setState(() => _correct = i),
                  icon: Icon(
                    _correct == i ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    color: _correct == i ? c.sky : c.lineStrong,
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _options[i],
                    maxLength: StudyLimits.option,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'Option ${i + 1}',
                      counterText: '',
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove option',
                  onPressed: _options.length > StudyLimits.minOptions ? () => _removeOption(i) : null,
                  icon: const Icon(Icons.remove_circle_outline, size: 20),
                ),
              ],
            ),
          ),
        if (_options.length < StudyLimits.maxOptions)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _addOption,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add an option'),
            ),
          ),
        const SizedBox(height: Gap.snug),
        TextField(
          controller: _explanation,
          minLines: 1,
          maxLines: 4,
          maxLength: StudyLimits.explanation,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Why it is correct',
            helperText: 'Optional. Shown after the quiz is marked.',
          ),
        ),
      ],
    );
  }
}
