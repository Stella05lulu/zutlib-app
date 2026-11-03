import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/study.dart';
import '../../../state/study_providers.dart';
import '../../../study/practice.dart';
import '../../widgets/study_widgets.dart';
import '../shared/pdf_viewer_screen.dart';
import '../../../state/plan_providers.dart';
import '../../../study/planner.dart' show dateOnly, examCountdown;
import '../plan/plan_sheet.dart';
import 'kit_widgets.dart';

/// The kit's front page: what it is built on, AI help, and a way into
/// each of the other parts, like a course's overview page.
class KitMaterialsTab extends ConsumerStatefulWidget {
  const KitMaterialsTab({super.key, required this.kit, required this.onChanged, required this.onOpenTab});
  final KitData kit;
  final VoidCallback onChanged;
  final ValueChanged<int> onOpenTab;

  @override
  ConsumerState<KitMaterialsTab> createState() => _KitMaterialsTabState();
}

class _KitMaterialsTabState extends ConsumerState<KitMaterialsTab> {
  String? _error;
  bool _opening = false;

  /// On the web the PDF opens inside the app (a new tab would be blocked
  /// as a pop-up); phones hand it to the device's PDF reader.
  Future<void> _openPdf() async {
    setState(() => _opening = true);
    final n = widget.kit.note;
    final error = await openPdf(context, title: n.pdfLabel ?? n.title, loadUrl: () => studyRepo.pdfUrl(n));
    if (mounted) {
      setState(() {
        _opening = false;
        _error = error;
      });
    }
  }

  Future<void> _openVideo() async {
    final ok = await launchUrl(Uri.parse(widget.kit.note.youtubeUrl!), mode: LaunchMode.externalApplication);
    if (!ok && mounted) setState(() => _error = 'Could not open the video on this device.');
  }

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    final t = Theme.of(context).textTheme;
    final kit = widget.kit;
    final n = kit.note;
    final fill = KitPalette.fill(n.color.wire);
    final on = KitPalette.onFill(n.color.wire);
    final level = smartLevel(kit.questions.map((q) => q.id), kit.stars);
    final mastery = deckMastery(kit.cards.map((x) => x.id), kit.boxes);

    return StudyPage(
      onRefresh: () async => widget.onChanged(),
      children: [
        // ---------------------------------------------------- banner
        Container(
          decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(Radii.panel + 4)),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned(
                right: -20,
                bottom: -30,
                child: Icon(kitSourceIcon(n), size: 150, color: on.withValues(alpha: 0.14)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Gap.page, Gap.page, Gap.page, Gap.page),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(n.title,
                        style: t.headlineSmall?.copyWith(color: on, fontWeight: FontWeight.w700, fontSize: 26)),
                    const SizedBox(height: Gap.tight),
                    Text(
                      [n.sourceLabel, if (n.courseCode != null) n.courseCode!, 'Made ${studyDate.format(n.createdAt)}']
                          .join('  /  '),
                      style: t.bodyMedium?.copyWith(color: on),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: Gap.snug),
          InlineNotice(_error!, error: true, onClose: () => setState(() => _error = null)),
        ],
        const SizedBox(height: Gap.snug),
        _PlanLink(noteId: n.id),

        // ---------------------------------------------------- AI
        if (kit.guide == null) ...[
          const SizedBox(height: Gap.page),
          n.hasMaterials
              ? KitEmpty(
                  icon: Icons.auto_awesome_outlined,
                  title: 'Build this kit with AI',
                  sentence: 'One request makes a study guide, flashcards and a bank of practice questions '
                      'from your materials.',
                  actions: [
                    FilledButton.icon(
                      onPressed: () => buildKitWithAi(context, ref, n.id),
                      icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                      label: const Text('Build with AI'),
                    ),
                  ],
                )
              : KitEmpty(
                  icon: Icons.edit_note_outlined,
                  title: 'No materials yet',
                  sentence: 'Add your own flashcards and questions, or add notes so AI can build the kit for you.',
                  actions: [
                    OutlinedButton(onPressed: () => context.push('/study/note/${n.id}/edit'), child: const Text('Add notes')),
                    OutlinedButton(onPressed: () => widget.onOpenTab(3), child: const Text('Add flashcards')),
                  ],
                ),
        ],
        const _AiAllowance(),

        // ---------------------------------------------------- course content
        const SectionLabel('In this kit'),
        RowGroup(children: [
          _ContentRow(
            icon: Icons.menu_book_outlined,
            title: 'Study guide',
            detail: kit.guide == null ? 'Not made yet' : '${kit.guide!.sections.length} topics',
            onTap: () => widget.onOpenTab(1),
          ),
          _ContentRow(
            icon: Icons.bolt_outlined,
            title: 'Smart study',
            detail: kit.questions.isEmpty
                ? 'No questions yet'
                : level.complete
                    ? 'Every question mastered'
                    : 'Level ${level.level}: ${level.percent}%',
            progress: kit.questions.isEmpty ? null : level.mastery,
            onTap: () => widget.onOpenTab(2),
          ),
          _ContentRow(
            icon: Icons.style_outlined,
            title: 'Flashcards',
            detail: kit.cards.isEmpty
                ? 'No cards yet'
                : '${kit.cards.length} cards, ${(mastery * 100).round()}% known',
            progress: kit.cards.isEmpty ? null : mastery,
            onTap: () => widget.onOpenTab(3),
          ),
          _ContentRow(
            icon: Icons.assignment_outlined,
            title: 'Tests',
            detail: kit.questions.isEmpty ? 'Needs questions first' : '${kit.questions.length} questions to draw from',
            onTap: () => widget.onOpenTab(4),
          ),
        ]),

        // ---------------------------------------------------- materials
        const SectionLabel('Materials'),
        if (n.hasPdf)
          RowGroup(children: [
            StudyRow(
              title: n.pdfLabel ?? 'PDF',
              detail: n.hasLibraryPdf ? 'From the ZutLib library' : 'Your upload. Only you can see it.',
              trailing: OutlinedButton.icon(
                onPressed: _opening ? null : _openPdf,
                icon: const Icon(Icons.open_in_new, size: 16),
                label: Text(_opening ? 'Opening' : 'Open'),
              ),
            ),
          ]),
        if (n.hasVideo)
          RowGroup(children: [
            StudyRow(
              title: 'YouTube video',
              detail: n.youtubeUrl,
              detailLines: 1,
              trailing: OutlinedButton.icon(
                onPressed: _openVideo,
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Watch'),
              ),
            ),
          ]),
        if (n.hasPdf || n.hasVideo) const SizedBox(height: Gap.tight),
        RowGroup(children: [
          StudyRow(
            title: 'Your notes',
            detail: n.body.trim().isEmpty
                ? (n.hasPdf || n.hasVideo
                    ? 'Optional. Anything you type here is sent to AI along with the materials above.'
                    : 'Nothing typed yet.')
                : n.preview,
            detailLines: 3,
            trailing: TextButton(
              onPressed: () => context.push('/study/note/${n.id}/edit'),
              child: Text(n.body.trim().isEmpty ? 'Add' : 'Edit'),
            ),
          ),
        ]),
        const SizedBox(height: Gap.page),
        Text(
          'AI can make mistakes. Check what it writes against your materials. Content sent to the free '
          'Gemini tier may be used by Google to improve its products, so do not upload anything private.',
          style: t.bodySmall?.copyWith(color: c.inkFaint),
        ),
      ],
    );
  }
}

class _ContentRow extends StatelessWidget {
  const _ContentRow({required this.icon, required this.title, required this.detail, required this.onTap, this.progress});
  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback onTap;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    final t = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Gap.page - 4, vertical: Gap.row),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: c.accentWash, borderRadius: BorderRadius.circular(Radii.control)),
              child: Icon(icon, color: c.accent, size: 22),
            ),
            const SizedBox(width: Gap.snug),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: t.titleMedium),
                  const SizedBox(height: 2),
                  Text(detail, style: t.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (progress != null) ...[
                    const SizedBox(height: Gap.tight),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(value: progress, minHeight: 5, color: c.accent),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: Gap.tight),
            Icon(Icons.chevron_right, color: c.inkFaint),
          ],
        ),
      ),
    );
  }
}

/// "7 of 10 AI requests left today", read from the database.
class _AiAllowance extends ConsumerWidget {
  const _AiAllowance();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(aiStatusProvider).valueOrNull;
    if (status == null) return const SizedBox.shrink();
    final c = StudyColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: Gap.snug),
      child: Row(
        children: [
          Icon(Icons.auto_awesome_outlined, size: 16, color: c.sky),
          const SizedBox(width: Gap.hair + 2),
          Text('${status.remaining} of ${status.dailyLimit} AI requests left today',
              style: Mono.of(context, size: 12, color: status.remaining == 0 ? c.danger : c.inkSoft)),
        ],
      ),
    );
  }
}

/// "Exam in 5 days: view plan", or a way to plan this kit for an exam.
class _PlanLink extends ConsumerWidget {
  const _PlanLink({required this.noteId});
  final String noteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = StudyColors.of(context);
    final t = Theme.of(context).textTheme;
    final plan = ref.watch(planForKitProvider(noteId)).valueOrNull;
    final upcoming = plan != null && !dateOnly(plan.examDate).isBefore(dateOnly(DateTime.now()));
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.panel), side: BorderSide(color: c.line)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          if (upcoming) {
            await context.push('/plan/${plan.id}');
          } else {
            await showPlanSheet(context, noteId: noteId, existing: plan);
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.page - 4, vertical: Gap.snug),
          child: Row(
            children: [
              Icon(Icons.event_note_outlined, color: c.accent),
              const SizedBox(width: Gap.snug),
              Expanded(
                child: Text(
                  upcoming
                      ? '${examCountdown(plan.examDate, DateTime.now())}. See today\'s plan.'
                      : 'Have an exam on this? Add it and get a day-by-day plan.',
                  style: t.bodyLarge?.copyWith(color: c.ink),
                ),
              ),
              Icon(Icons.chevron_right, color: c.inkFaint),
            ],
          ),
        ),
      ),
    );
  }
}
