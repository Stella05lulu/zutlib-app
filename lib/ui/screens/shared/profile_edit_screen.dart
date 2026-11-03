import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/profile.dart';
import '../../../services/reminders.dart';
import '../../../state/plan_providers.dart';
import '../../../state/providers.dart';
import '../../widgets/common.dart' show showMessage;
import '../../widgets/course_picker.dart';
import '../../widgets/study_widgets.dart';

/// Edit your own details: name, department, year, courses and reminder
/// settings. Email and role stay with administrators.
class ProfileEditScreen extends ConsumerStatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  ConsumerState<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends ConsumerState<ProfileEditScreen> {
  final _name = TextEditingController();
  String? _department;
  int? _year;
  List<String> _courses = [];
  TimeOfDay _reminder = const TimeOfDay(hour: 18, minute: 0);
  bool _uploads = true;
  bool _study = true;
  bool _loaded = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _load(Profile p) {
    if (_loaded) return;
    _loaded = true;
    _name.text = p.fullName;
    _department = p.department;
    _year = p.yearOfStudy;
    _courses = [...p.courses];
    final (h, m) = p.reminderHourMinute;
    _reminder = TimeOfDay(hour: h, minute: m);
    _uploads = p.notifyUploads;
    _study = p.notifyStudy;
  }

  String get _reminderText =>
      '${_reminder.hour.toString().padLeft(2, '0')}:${_reminder.minute.toString().padLeft(2, '0')}';

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return setState(() => _error = 'Enter your full name.');
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await accountRepo.updateProfile(
        fullName: _name.text.trim(),
        department: _department,
        yearOfStudy: _year,
        courses: _courses,
        reminderTime: _reminderText,
        notifyUploads: _uploads,
        notifyStudy: _study,
      );
      ref.invalidate(profileProvider);
      ref.invalidate(recommendationsProvider);
      Reminders.rescheduleSoon(ref);
      if (!mounted) return;
      showMessage(context, 'Profile saved.');
      context.pop();
    } on Failure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).valueOrNull;
    if (profile != null) _load(profile);
    final student = profile?.role == UserRole.student;

    return StudyScope(
      child: Builder(builder: (context) {
        final t = Theme.of(context).textTheme;
        return Scaffold(
          appBar: const StudyTopBar(title: 'Edit profile'),
          body: profile == null
              ? const StudyPage(children: [RowsSkeleton(rows: 4)])
              : StudyPage(children: [
                  Text('Your details', style: t.titleMedium),
                  const SizedBox(height: Gap.snug),
                  TextField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Full name'),
                  ),
                  const SizedBox(height: Gap.snug),
                  DropdownButtonFormField<String>(
                    initialValue: _department,
                    decoration: const InputDecoration(labelText: 'Department'),
                    items: [for (final d in kStudentDepartments) DropdownMenuItem(value: d, child: Text(d))],
                    onChanged: (v) => setState(() => _department = v),
                  ),
                  if (student) ...[
                    const SizedBox(height: Gap.snug),
                    DropdownButtonFormField<int>(
                      initialValue: _year,
                      decoration: const InputDecoration(labelText: 'Year of study'),
                      items: [for (var y = 1; y <= 6; y++) DropdownMenuItem(value: y, child: Text('Year $y'))],
                      onChanged: (v) => setState(() => _year = v),
                    ),
                    const SectionLabel('Your courses'),
                    CoursePicker(courses: _courses, onChanged: (v) => setState(() => _courses = v)),
                    const SectionLabel('Reminders'),
                    RowGroup(children: [
                      ListTile(
                        title: const Text('Daily study reminder'),
                        subtitle: Text('On study days in your plans, at $_reminderText'),
                        trailing: TextButton(
                          onPressed: () async {
                            final picked = await showTimePicker(context: context, initialTime: _reminder);
                            if (picked != null) setState(() => _reminder = picked);
                          },
                          child: const Text('Change time'),
                        ),
                      ),
                      SwitchListTile(
                        title: const Text('Study and exam reminders'),
                        value: _study,
                        onChanged: (v) => setState(() => _study = v),
                      ),
                      SwitchListTile(
                        title: const Text('New papers for my courses'),
                        value: _uploads,
                        onChanged: (v) => setState(() => _uploads = v),
                      ),
                    ]),
                  ],
                  const SizedBox(height: Gap.page),
                  Text('Your email address and role can only be changed by an administrator.', style: t.bodySmall),
                  if (_error != null) ...[
                    const SizedBox(height: Gap.snug),
                    InlineNotice(_error!, error: true, onClose: () => setState(() => _error = null)),
                  ],
                  const SizedBox(height: Gap.page),
                  FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving' : 'Save')),
                ]),
        );
      }),
    );
  }
}
