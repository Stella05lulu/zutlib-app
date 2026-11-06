import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/reminders.dart';
import '../../../state/plan_providers.dart';
import '../../../state/providers.dart';
import '../../widgets/brand.dart';
import '../../widgets/course_picker.dart';
import '../../widgets/study_widgets.dart';

/// A student's first visit: three short pages on what ZutLib does, then
/// their year, courses and reminder time. The answers set up "For your
/// courses", new-paper notices and study reminders. Shown once; it can be
/// skipped.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pages = PageController();
  int _page = 0;
  int? _year;
  List<String> _courses = [];
  TimeOfDay _reminder = const TimeOfDay(hour: 18, minute: 0);
  bool _saving = false;
  String? _error;

  static const _intro = [
    (Icons.explore_outlined, 'Find past papers fast',
        'Search by course code, year or title. Every past paper, test and set of notes in the ZUT library, on your phone.'),
    (Icons.library_books_outlined, 'Borrow without leaving your ID',
        'Ask for a book in the app. The librarian sees your verified details, and the app reminds you before it is due.'),
    (Icons.event_note_outlined, 'Study with a plan',
        'Turn any paper or notes into a study kit with AI, then add your exam date. ZutLib plans each day until the exam.'),
  ];

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _finish({required bool skipped}) async {
    final profile = ref.read(profileProvider).valueOrNull;
    if (profile == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await accountRepo.updateProfile(
        fullName: profile.fullName,
        department: profile.department,
        yearOfStudy: skipped ? profile.yearOfStudy : _year,
        courses: skipped ? profile.courses : _courses,
        reminderTime:
            '${_reminder.hour.toString().padLeft(2, '0')}:${_reminder.minute.toString().padLeft(2, '0')}',
        notifyUploads: profile.notifyUploads,
        notifyStudy: profile.notifyStudy,
        finishOnboarding: true,
      );
      if (!skipped) await Reminders.requestPermission();
      ref.invalidate(profileProvider);
      await ref.read(profileProvider.future);
      if (mounted) context.go('/home');
    } on Failure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _next() {
    _pages.nextPage(duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    return StudyScope(
      child: Builder(builder: (context) {
        final c = StudyColors.of(context);
        final t = Theme.of(context).textTheme;
        final last = _intro.length;
        return Scaffold(
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Gap.page, Gap.snug, Gap.tight, 0),
                      child: Row(
                        children: [
                          const ZutLibLogo(height: 26),
                          const Spacer(),
                          TextButton(
                            onPressed: _saving ? null : () => _finish(skipped: true),
                            child: const Text('Skip'),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: PageView(
                        controller: _pages,
                        onPageChanged: (i) => setState(() => _page = i),
                        children: [
                          for (final (icon, title, body) in _intro)
                            Padding(
                              padding: const EdgeInsets.all(Gap.wide - 8),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 88,
                                    height: 88,
                                    decoration: BoxDecoration(
                                      color: c.accentWash,
                                      borderRadius: BorderRadius.circular(Radii.panel + 8),
                                    ),
                                    child: Icon(icon, size: 40, color: c.accent),
                                  ),
                                  const SizedBox(height: Gap.section),
                                  Text(title, style: t.headlineSmall, textAlign: TextAlign.center),
                                  const SizedBox(height: Gap.snug),
                                  Text(body, style: t.bodyLarge?.copyWith(color: c.inkSoft), textAlign: TextAlign.center),
                                ],
                              ),
                            ),
                          _Survey(
                            year: _year,
                            courses: _courses,
                            reminder: _reminder,
                            onYear: (v) => setState(() => _year = v),
                            onCourses: (v) => setState(() => _courses = v),
                            onReminder: (v) => setState(() => _reminder = v),
                          ),
                        ],
                      ),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Gap.page),
                        child: InlineNotice(_error!, error: true, onClose: () => setState(() => _error = null)),
                      ),
                    Padding(
                      padding: const EdgeInsets.all(Gap.page),
                      child: Row(
                        children: [
                          for (var i = 0; i <= last; i++)
                            Container(
                              width: i == _page ? 20 : 8,
                              height: 8,
                              margin: const EdgeInsets.only(right: Gap.hair + 2),
                              decoration: BoxDecoration(
                                color: i == _page ? c.accent : c.lineStrong,
                                borderRadius: BorderRadius.circular(Radii.tag),
                              ),
                            ),
                          const Spacer(),
                          FilledButton(
                            onPressed: _saving ? null : (_page < last ? _next : () => _finish(skipped: false)),
                            child: Text(_page < last ? 'Next' : (_saving ? 'Saving' : 'Start using ZutLib')),
                          ),
                        ],
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

class _Survey extends StatelessWidget {
  const _Survey({
    required this.year,
    required this.courses,
    required this.reminder,
    required this.onYear,
    required this.onCourses,
    required this.onReminder,
  });

  final int? year;
  final List<String> courses;
  final TimeOfDay reminder;
  final ValueChanged<int?> onYear;
  final ValueChanged<List<String>> onCourses;
  final ValueChanged<TimeOfDay> onReminder;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final time = '${reminder.hour.toString().padLeft(2, '0')}:${reminder.minute.toString().padLeft(2, '0')}';
    return ListView(
      padding: const EdgeInsets.all(Gap.page),
      children: [
        Text('A little about you', style: t.headlineSmall),
        const SizedBox(height: Gap.hair),
        Text('So ZutLib can suggest the right papers and remind you at the right time. '
            'You can change these later in Account.', style: t.bodyMedium),
        const SizedBox(height: Gap.page),
        Text('Year of study', style: t.titleSmall),
        const SizedBox(height: Gap.tight),
        Wrap(
          spacing: Gap.tight,
          runSpacing: Gap.tight,
          children: [
            for (var y = 1; y <= 6; y++)
              ChoiceChip(label: Text('Year $y'), selected: year == y, onSelected: (_) => onYear(y)),
          ],
        ),
        const SizedBox(height: Gap.page),
        Text('Your courses this semester', style: t.titleSmall),
        const SizedBox(height: Gap.tight),
        CoursePicker(courses: courses, onChanged: onCourses),
        const SizedBox(height: Gap.page),
        Text('Daily study reminder', style: t.titleSmall),
        const SizedBox(height: Gap.tight),
        OutlinedButton.icon(
          onPressed: () async {
            final picked = await showTimePicker(context: context, initialTime: reminder);
            if (picked != null) onReminder(picked);
          },
          icon: const Icon(Icons.alarm_outlined, size: 18),
          label: Text('Remind me at $time'),
        ),
      ],
    );
  }
}
