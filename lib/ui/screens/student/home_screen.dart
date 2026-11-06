import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme.dart' show kNavClearance;
import '../../../core/theme/app_theme.dart';
import '../../../data/resource_repository.dart' show ResourceFilters;
import '../../../models/borrow_request.dart';
import '../../../models/resource.dart';
import '../../../models/study.dart' show KitColorX;
import '../../../state/governance_providers.dart';
import '../../../state/plan_providers.dart';
import '../../../state/providers.dart';
import '../../../state/study_providers.dart';
import '../../../study/planner.dart';
import '../../../study/practice.dart';
import '../../../study/progress.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/notification_bell.dart';
import '../../widgets/shelves.dart';
import '../../widgets/study_widgets.dart';
import '../plan/plan_widgets.dart' show MasteryBar;

/// The student's Home, in the order a student needs it: a greeting, one
/// card saying what to do now (today's plan, the kit to carry on with, or
/// how to start), three numbers, the latest announcement, quick links, and
/// rows of things to carry on with. Every row comes from live data, and a
/// row with nothing in it is left out.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(myBorrowingProvider);
    ref.invalidate(announcementsProvider);
    ref.invalidate(savedProvider);
    ref.invalidate(recentResourcesProvider);
    ref.invalidate(progressDataProvider);
    ref.invalidate(kitListProvider);
    refreshPlans(ref);
    ref.invalidate(recommendationsProvider);
    try {
      await ref.read(myBorrowingProvider.future);
    } catch (_) {
      // Each section shows its own state.
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).valueOrNull;
    final borrows = ref.watch(myBorrowingProvider);
    final firstName = (profile?.fullName.trim().split(RegExp(r'\s+')).first) ?? '';

    return StudyScope(
      child: Builder(builder: (context) {
        final t = Theme.of(context).textTheme;
        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: StudyPage(
              bottom: kNavClearance,
              onRefresh: () => _refresh(ref),
              children: [
                Row(children: [
                  const ShellMenuButton(),
                  const Spacer(),
                  const NotificationBell(),
                  const SizedBox(width: Gap.tight),
                  if (profile != null)
                    Semantics(
                      button: true,
                      label: 'Account',
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => context.go('/profile'),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: InitialsAvatar(profile.initials, size: 36),
                        ),
                      ),
                    ),
                ]),
                const SizedBox(height: Gap.snug),
                Text(_greeting(DateTime.now()), style: t.bodyLarge?.copyWith(color: StudyColors.of(context).inkSoft)),
                Text(firstName.isEmpty ? 'Welcome back' : firstName, style: t.displaySmall),
                if (profile != null && (profile.department != null || profile.yearOfStudy != null)) ...[
                  const SizedBox(height: Gap.hair),
                  Text(
                    [
                      if (profile.department != null) profile.department!,
                      if (profile.yearOfStudy != null) 'Year ${profile.yearOfStudy}',
                    ].join('  /  '),
                    style: t.bodyMedium,
                  ),
                ],
                const SizedBox(height: Gap.page),
                const _TodayCard(),
                const SizedBox(height: Gap.page),
                _Numbers(borrows: borrows.valueOrNull),
                const _Announcement(),
                const ShelfHeading('Quick access'),
                _QuickGrid(children: [
                  _Quick('Past papers', Icons.description_outlined, Tone.accent, () {
                    ref.read(filtersProvider.notifier).state = const ResourceFilters(type: ResourceType.pastPaper);
                    context.go('/browse');
                  }),
                  _Quick('Books', Icons.menu_book_outlined, Tone.success, () {
                    ref.read(filtersProvider.notifier).state = const ResourceFilters(type: ResourceType.book);
                    context.go('/browse');
                  }),
                  _Quick('Study kits', Icons.school_outlined, Tone.sky, () => context.go('/study')),
                  _Quick('Plan', Icons.event_note_outlined, Tone.warn, () => context.go('/plan')),
                  _Quick('Saved', Icons.bookmark_border, Tone.danger, () => context.push('/saved')),
                  _Quick('My progress', Icons.insights_outlined, Tone.accent, () => context.push('/progress')),
                ]),
                const _ContinueStudying(),
                const _UpcomingExams(),
                const _ForYourCourses(),
                const _Recent(),
                const _Saved(),
                const SizedBox(height: Gap.page),
              ],
            ),
          ),
        );
      }),
    );
  }
}

String _greeting(DateTime now) => now.hour < 12
    ? 'Good morning'
    : now.hour < 17
        ? 'Good afternoon'
        : 'Good evening';

/// Quick links as tiles: three per row on a phone, six on a wide screen.
class _QuickGrid extends StatelessWidget {
  const _QuickGrid({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final perRow = box.maxWidth >= 640 ? 6 : 3;
      final w = (box.maxWidth - Gap.tight * (perRow - 1)) / perRow;
      return Wrap(
        spacing: Gap.tight,
        runSpacing: Gap.tight,
        children: [for (final c in children) SizedBox(width: w, child: c)],
      );
    });
  }
}

class _Quick extends StatelessWidget {
  const _Quick(this.label, this.icon, this.tone, this.onTap);
  final String label;
  final IconData icon;
  final Tone tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    final t = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.panel), side: BorderSide(color: c.line)),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Radii.panel),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.tight, vertical: Gap.snug),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconChip(icon, tone: tone, size: 40),
                const SizedBox(height: Gap.tight),
                Text(label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.labelLarge?.copyWith(color: c.ink)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The one thing to do now, as the page's single strong block: today's
/// plan if there is one, otherwise the kit studied last, otherwise how to
/// begin. Flat accent fill, light text.
class _TodayCard extends ConsumerWidget {
  const _TodayCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plans = ref.watch(upcomingPlansProvider).valueOrNull ?? const <PlanView>[];
    final kits = ref.watch(kitListProvider).valueOrNull ?? const <KitSummary>[];
    final today = [for (final v in plans) if (v.today != null) for (final task in v.today!.tasks) (v, task)];

    if (today.isNotEmpty) {
      final done = today.where((x) => x.$1.done(x.$2)).length;
      final next = today.where((x) => !x.$1.done(x.$2)).firstOrNull;
      final exam = ([...plans]..sort((a, b) => a.plan.examDate.compareTo(b.plan.examDate))).first;
      return _HeroCard(
        icon: Icons.event_note_outlined,
        lead: 'Today\'s plan',
        title: next == null ? 'All done for today' : next.$2.title,
        detail: next == null
            ? 'Every task is ticked. ${examCountdown(exam.plan.examDate, DateTime.now())}.'
            : '$done of ${today.length} tasks done  /  ${exam.note.title}: '
                '${examCountdown(exam.plan.examDate, DateTime.now()).toLowerCase()}',
        progress: done / today.length,
        action: next == null ? 'Open plan' : 'Continue',
        onTap: () => next == null ? context.go('/plan') : context.push('/plan/${next.$1.plan.id}'),
      );
    }
    if (kits.isNotEmpty) {
      final last = ([...kits]..sort((a, b) => b.note.updatedAt.compareTo(a.note.updatedAt))).first;
      return _HeroCard(
        icon: Icons.school_outlined,
        lead: 'Pick up where you left off',
        title: last.note.title,
        detail: 'Last studied ${daysAgo(last.note.updatedAt)}. Add your exam date and ZutLib plans each day for you.',
        action: 'Open kit',
        onTap: () => context.push('/study/note/${last.note.id}'),
      );
    }
    return _HeroCard(
      icon: Icons.auto_awesome_outlined,
      lead: 'Get started',
      title: 'Make your first study kit',
      detail: 'Add a PDF, a past paper or a lecture video, and ZutLib writes a guide, flashcards and a practice test.',
      action: 'Make a kit',
      onTap: () => context.go('/study'),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.icon,
    required this.lead,
    required this.title,
    required this.detail,
    required this.action,
    required this.onTap,
    this.progress,
  });
  final IconData icon;

  /// A short line of context above the title, in sentence case.
  final String lead;
  final String title;
  final String detail;
  final String action;
  final VoidCallback onTap;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    final t = Theme.of(context).textTheme;
    final soft = c.onAccent.withValues(alpha: 0.82);
    return Material(
      color: c.accent,
      borderRadius: BorderRadius.circular(Radii.panel + 4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Gap.page),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: c.onAccent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, size: 18, color: c.onAccent),
                ),
                const SizedBox(width: Gap.tight),
                Expanded(child: Text(lead, style: t.labelLarge?.copyWith(color: soft))),
              ]),
              const SizedBox(height: Gap.snug),
              Text(title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.headlineSmall?.copyWith(color: c.onAccent)),
              const SizedBox(height: Gap.hair),
              Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodyMedium?.copyWith(color: soft)),
              if (progress != null) ...[
                const SizedBox(height: Gap.snug),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress!.clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: c.onAccent.withValues(alpha: 0.22),
                    color: c.onAccent,
                  ),
                ),
              ],
              const SizedBox(height: Gap.page),
              FilledButton(
                onPressed: onTap,
                style: FilledButton.styleFrom(
                  backgroundColor: c.onAccent,
                  foregroundColor: c.accent,
                  minimumSize: const Size(48, 44),
                ),
                child: Text(action),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Books on loan, the next due date with a countdown, and the study streak.
class _Numbers extends ConsumerWidget {
  const _Numbers({required this.borrows});
  final List<BorrowRequest>? borrows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onLoan = [for (final b in borrows ?? const <BorrowRequest>[]) if (b.status == BorrowStatus.collected) b];
    final dated = [for (final b in onLoan) if (b.dueDate != null) b]..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));
    final next = dated.isEmpty ? null : dated.first;
    final progress = ref.watch(progressDataProvider).valueOrNull;
    final streak = progress == null ? null : attemptStreak(progress.attempts.map((a) => a.at), DateTime.now());

    String countdown(int days) => days < 0
        ? '${-days} ${-days == 1 ? 'day' : 'days'} overdue'
        : days == 0
            ? 'due today'
            : 'in $days ${days == 1 ? 'day' : 'days'}';

    return StatGrid(children: [
      StatTile(
        value: borrows == null ? '...' : '${onLoan.length}',
        label: onLoan.length == 1 ? 'Book on loan' : 'Books on loan',
        icon: Icons.menu_book_outlined,
        tone: Tone.sky,
        onTap: () => context.go('/borrowing'),
      ),
      StatTile(
        value: next == null ? 'None' : DateFormat('d MMM').format(next.dueDate!),
        label: 'Next due date',
        detail: next == null ? null : countdown(next.daysUntilDue ?? 0),
        alert: next != null && (next.daysUntilDue ?? 0) <= 1,
        icon: Icons.event_outlined,
        tone: next != null && (next.daysUntilDue ?? 0) <= 1 ? Tone.warn : Tone.accent,
        onTap: () => context.go('/borrowing'),
      ),
      StatTile(
        value: streak == null ? '...' : '$streak',
        label: streak == 1 ? 'Day study streak' : 'Days study streak',
        detail: streak == null ? null : (streak == 0 ? 'Take a test to start one' : 'From your test and quiz days'),
        icon: Icons.local_fire_department_outlined,
        tone: Tone.warn,
        onTap: () => context.push('/progress'),
      ),
    ]);
  }
}

class _Announcement extends ConsumerWidget {
  const _Announcement();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = ref.watch(latestAnnouncementProvider);
    if (a == null) return const SizedBox.shrink();
    final c = StudyColors.of(context);
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: Gap.page),
      child: Container(
        padding: const EdgeInsets.fromLTRB(Gap.page - 4, Gap.snug, Gap.tight, Gap.hair),
        decoration: BoxDecoration(
          color: c.skyWash,
          borderRadius: BorderRadius.circular(Radii.panel),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const IconChip(Icons.campaign_outlined, tone: Tone.accent, size: 34),
            const SizedBox(width: Gap.snug),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.title, style: t.titleMedium),
                  const SizedBox(height: Gap.hair),
                  Text(a.body, style: t.bodyMedium, maxLines: 3, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: Gap.hair),
                  Row(children: [
                    Text(DateFormat('d MMM yyyy').format(a.createdAt), style: Mono.of(context, size: 12)),
                    if (a.isSample) ...[const SizedBox(width: Gap.tight), const Tag('Sample')],
                    const Spacer(),
                    TextButton(onPressed: () => context.push('/updates'), child: const Text('All updates')),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The kit studied most recently, with its mastery bar.
class _ContinueStudying extends ConsumerWidget {
  const _ContinueStudying();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kits = ref.watch(kitListProvider).valueOrNull ?? const <KitSummary>[];
    if (kits.isEmpty) return const SizedBox.shrink();
    // Without a plan for today, the card at the top already shows this kit.
    final plans = ref.watch(upcomingPlansProvider).valueOrNull ?? const <PlanView>[];
    if (!plans.any((v) => v.today != null && v.today!.tasks.isNotEmpty)) return const SizedBox.shrink();
    final last = ([...kits]..sort((a, b) => b.note.updatedAt.compareTo(a.note.updatedAt))).first;
    final kit = ref.watch(kitProvider(last.note.id)).valueOrNull;
    final progress = ref.watch(progressDataProvider).valueOrNull;
    final attemptsHere = [for (final a in progress?.attempts ?? const <AttemptRecord>[]) if (a.noteId == last.note.id) a.at];
    final lastStudied = [last.note.updatedAt, ...attemptsHere].reduce((a, b) => a.isAfter(b) ? a : b);
    double? mastery;
    if (kit != null) {
      final parts = <double>[
        if (kit.cards.isNotEmpty) deckMastery(kit.cards.map((x) => x.id), kit.boxes),
        if (kit.questions.isNotEmpty) smartLevel(kit.questions.map((x) => x.id), kit.stars).mastery,
      ];
      mastery = parts.isEmpty ? 0 : parts.reduce((a, b) => a + b) / parts.length;
    }
    final c = StudyColors.of(context);
    final t = Theme.of(context).textTheme;
    final fill = KitPalette.fill(last.note.color.wire);
    final on = KitPalette.onFill(last.note.color.wire);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ShelfHeading('Continue studying', onSeeAll: () => context.go('/study')),
        Material(
          color: c.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.panel), side: BorderSide(color: c.line)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => context.push('/study/note/${last.note.id}'),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 96,
                    color: fill,
                    alignment: Alignment.center,
                    child: Text(
                      (last.note.courseCode ?? '').isNotEmpty ? last.note.courseCode! : 'Kit',
                      textAlign: TextAlign.center,
                      style: Mono.of(context, size: 13, weight: FontWeight.w600, color: on),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(Gap.snug),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(last.note.title, style: t.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: Gap.hair),
                          Text('Last studied ${daysAgo(lastStudied)}', style: t.bodySmall),
                          const SizedBox(height: Gap.tight),
                          if (mastery != null) MasteryBar(value: mastery) else const Bone(height: 8),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _UpcomingExams extends ConsumerWidget {
  const _UpcomingExams();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plans = ref.watch(upcomingPlansProvider).valueOrNull ?? const <PlanView>[];
    if (plans.isEmpty) return const SizedBox.shrink();
    final sorted = [...plans]..sort((a, b) => a.plan.examDate.compareTo(b.plan.examDate));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ShelfHeading('Upcoming exams', onSeeAll: () => context.go('/plan')),
        RowGroup(children: [
          for (final v in sorted.take(3))
            StudyRow(
              title: v.note.title,
              detail: '${examCountdown(v.plan.examDate, DateTime.now())}  /  '
                  '${DateFormat('EEE d MMM').format(v.plan.examDate)}',
              detailLines: 1,
              tags: [Tag(v.health.label)],
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () => context.push('/plan/${v.plan.id}'),
            ),
        ]),
      ],
    );
  }
}

class _ForYourCourses extends ConsumerWidget {
  const _ForYourCourses();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recs = ref.watch(recommendationsProvider).valueOrNull ?? const [];
    if (recs.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ShelfHeading('For your courses', onSeeAll: () => context.go('/browse')),
        ResourceShelf(
          items: [for (final r in recs) r.item],
          reasons: {for (final r in recs) r.item.id: r.reason},
        ),
      ],
    );
  }
}

class _Recent extends ConsumerWidget {
  const _Recent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(recentResourcesProvider).valueOrNull ?? const <Resource>[];
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ShelfHeading('Recently added', onSeeAll: () {
          ref.read(filtersProvider.notifier).state = const ResourceFilters();
          context.go('/browse');
        }),
        ResourceShelf(items: items),
      ],
    );
  }
}

class _Saved extends ConsumerWidget {
  const _Saved();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(savedProvider).valueOrNull ?? const <Resource>[];
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ShelfHeading('Saved', onSeeAll: () => context.push('/saved')),
        ResourceShelf(items: items.take(12).toList()),
      ],
    );
  }
}
