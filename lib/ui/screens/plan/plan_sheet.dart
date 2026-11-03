import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/plan.dart';
import '../../../services/reminders.dart';
import '../../../state/plan_providers.dart';
import '../../../state/providers.dart';
import '../../../state/study_providers.dart';
import '../../../study/planner.dart';
import '../../widgets/study_widgets.dart';

/// Add an exam (or change one): which kit, the exam date, the days you can
/// study and how long each session is. Returns the saved plan.
Future<StudyPlan?> showPlanSheet(BuildContext context, {String? noteId, StudyPlan? existing}) {
  return showModalBottomSheet<StudyPlan>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => StudyScope(child: _PlanSheet(noteId: existing?.noteId ?? noteId, existing: existing)),
  );
}

class _PlanSheet extends ConsumerStatefulWidget {
  const _PlanSheet({this.noteId, this.existing});
  final String? noteId;
  final StudyPlan? existing;

  @override
  ConsumerState<_PlanSheet> createState() => _PlanSheetState();
}

class _PlanSheetState extends ConsumerState<_PlanSheet> {
  String? _noteId;
  DateTime? _exam;
  int _days = StudyDays.all;
  int _minutes = 30;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _noteId = widget.noteId;
    _exam = e?.examDate;
    _days = e?.studyDays ?? StudyDays.all;
    _minutes = e?.minutes ?? 30;
  }

  Future<void> _pickDate() async {
    final today = dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _exam ?? today.add(const Duration(days: 14)),
      firstDate: today.add(const Duration(days: 1)),
      lastDate: today.add(const Duration(days: 365)),
      helpText: 'Exam date',
    );
    if (picked != null) setState(() => _exam = picked);
  }

  Future<void> _save() async {
    final noteId = _noteId;
    final exam = _exam;
    if (noteId == null) return setState(() => _error = 'Choose the study kit for this exam.');
    if (exam == null) return setState(() => _error = 'Choose the exam date.');
    if (_days == 0) return setState(() => _error = 'Choose at least one day you can study.');
    if (studyDates(PlanSettings(examDate: exam, startDate: DateTime.now(), studyDays: _days), DateTime.now()).isEmpty) {
      return setState(() => _error = 'None of the days you ticked fall before the exam. '
          'Tick at least one day between today and the exam.');
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final e = widget.existing;
      StudyPlan saved;
      if (e == null) {
        saved = await planRepo.create(noteId: noteId, examDate: exam, studyDays: _days, minutes: _minutes);
        await accountRepo.logEvent('plan_created');
        // Daily reminders need the phone's permission (asked once).
        await Reminders.requestPermission();
      } else {
        await planRepo.update(e.id, examDate: exam, studyDays: _days, minutes: _minutes);
        saved = StudyPlan(
            id: e.id, noteId: e.noteId, examDate: exam, studyDays: _days, minutes: _minutes, startDate: e.startDate);
      }
      if (!mounted) return;
      refreshPlans(ref);
      Reminders.rescheduleSoon(ref);
      Navigator.of(context).pop(saved);
    } on Failure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final kits = ref.watch(kitListProvider).valueOrNull ?? const [];
    final plans = ref.watch(plansProvider).valueOrNull ?? const [];
    final planned = {for (final p in plans) if (p.id != widget.existing?.id) p.noteId};
    final choices = [for (final k in kits) if (!planned.contains(k.note.id)) k];
    final reminder = ref.watch(profileProvider).valueOrNull?.reminderTime ?? '18:00';
    final studyCount = _exam == null
        ? 0
        : studyDates(PlanSettings(examDate: _exam!, startDate: DateTime.now(), studyDays: _days), DateTime.now()).length;

    return Padding(
      padding: EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, MediaQuery.viewInsetsOf(context).bottom + Gap.page),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.existing == null ? 'Add an exam' : 'Change this plan', style: t.headlineSmall),
            const SizedBox(height: Gap.hair),
            Text('ZutLib spreads the kit over the days you have: learn first, then practise, then test.',
                style: t.bodyMedium),
            const SizedBox(height: Gap.page),
            if (widget.existing == null && widget.noteId == null) ...[
              Text('Study kit', style: t.titleSmall),
              const SizedBox(height: Gap.tight),
              if (choices.isEmpty)
                const InlineNotice('Make a study kit first: every plan is built from one kit.')
              else
                DropdownButtonFormField<String>(
                  initialValue: _noteId,
                  isExpanded: true,
                  hint: const Text('Choose a kit'),
                  items: [
                    for (final k in choices)
                      DropdownMenuItem(value: k.note.id, child: Text(k.note.title, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() => _noteId = v),
                ),
              const SizedBox(height: Gap.page),
            ],
            Text('Exam date', style: t.titleSmall),
            const SizedBox(height: Gap.tight),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.event_outlined, size: 18),
              label: Text(_exam == null ? 'Choose a date' : DateFormat('EEEE d MMMM yyyy').format(_exam!)),
            ),
            const SizedBox(height: Gap.page),
            Text('Days you can study', style: t.titleSmall),
            const SizedBox(height: Gap.tight),
            Wrap(
              spacing: Gap.tight,
              runSpacing: Gap.tight,
              children: [
                for (var wd = 1; wd <= 7; wd++)
                  FilterChip(
                    label: Text(StudyDays.labels[wd - 1]),
                    selected: _days & StudyDays.bit(wd) != 0,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _days = StudyDays.toggle(_days, wd)),
                  ),
              ],
            ),
            if (_exam != null && studyCount == 0) ...[
              const SizedBox(height: Gap.tight),
              const InlineNotice('None of these days fall before the exam, so the plan would be empty. '
                  'Tick at least one day between today and the exam.', error: true),
            ],
            const SizedBox(height: Gap.page),
            Text('Minutes per session', style: t.titleSmall),
            const SizedBox(height: Gap.tight),
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: [for (final m in kPlanMinutes) ButtonSegment(value: m, label: Text('$m'))],
              selected: {_minutes},
              onSelectionChanged: (s) => setState(() => _minutes = s.first),
            ),
            const SizedBox(height: Gap.page),
            Text(
              [
                if (_exam != null && studyCount > 0) '$studyCount study ${studyCount == 1 ? 'day' : 'days'} before the exam.',
                'Daily reminder at $reminder (change it in Account, Edit profile).',
              ].join(' '),
              style: t.bodySmall,
            ),
            if (_error != null) ...[
              const SizedBox(height: Gap.snug),
              InlineNotice(_error!, error: true, onClose: () => setState(() => _error = null)),
            ],
            const SizedBox(height: Gap.page),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving' : (widget.existing == null ? 'Build my plan' : 'Save changes')),
            ),
          ],
        ),
      ),
    );
  }
}
