import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/governance_repository.dart';
import '../../widgets/app_drawer.dart' show InitialsAvatar;
import '../../widgets/shelves.dart';
import '../../widgets/study_widgets.dart';

/// Read-only View as, super admin only. The server returns a picture of
/// what one student or librarian sees (view_as_start, 0021); no session or
/// token is ever made for them, nothing on this screen can change data,
/// and their study notes and kits are never included. Opening and leaving
/// are both written to the audit log.
class ViewAsScreen extends StatefulWidget {
  const ViewAsScreen({super.key, required this.userId});
  final String userId;

  @override
  State<ViewAsScreen> createState() => _ViewAsScreenState();
}

class _ViewAsScreenState extends State<ViewAsScreen> {
  ViewAsData? _data;
  String? _error;
  bool _ended = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() => _error = null);
    try {
      final d = await governanceRepo.viewAsStart(widget.userId);
      if (mounted) setState(() => _data = d);
    } on Failure catch (f) {
      if (mounted) setState(() => _error = f.message);
    }
  }

  Future<void> _reload() async {
    try {
      final d = await governanceRepo.viewAsData(widget.userId);
      if (mounted) setState(() => _data = d);
    } on Failure catch (f) {
      if (mounted) setState(() => _error = f.message);
    }
  }

  Future<void> _end() async {
    if (_ended) return;
    _ended = true;
    if (_data != null) {
      try {
        await governanceRepo.viewAsEnd(widget.userId);
      } on Failure {
        // Leaving still works; the start was recorded.
      }
    }
  }

  Future<void> _exit() async {
    await _end();
    if (mounted) context.pop();
  }

  @override
  void dispose() {
    _end();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return StudyScope(
      child: Builder(builder: (context) {
        final c = StudyColors.of(context);
        final t = Theme.of(context).textTheme;
        return PopScope(
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) _end();
          },
          child: Scaffold(
            body: SafeArea(
              child: Column(children: [
                // The banner stays on screen the whole time.
                Semantics(
                  liveRegion: true,
                  child: Container(
                    width: double.infinity,
                    color: c.warnWash,
                    padding: const EdgeInsets.fromLTRB(Gap.page, Gap.tight, Gap.tight, Gap.tight),
                    child: Row(children: [
                      Icon(Icons.visibility_outlined, size: 20, color: c.warn),
                      const SizedBox(width: Gap.tight),
                      Expanded(
                        child: Text(
                          d == null ? 'View as. Read only' : 'Viewing as ${d.name}. Read only',
                          style: t.titleSmall?.copyWith(color: c.warn),
                        ),
                      ),
                      TextButton(onPressed: _exit, child: const Text('Exit')),
                    ]),
                  ),
                ),
                Expanded(
                  child: StudyPage(
                    onRefresh: _reload,
                    children: [
                      if (_error != null)
                        StudyErrorState(message: _error!, onRetry: _start)
                      else if (d == null)
                        const RowsSkeleton(rows: 6)
                      else
                        _Picture(d: d),
                    ],
                  ),
                ),
              ]),
            ),
          ),
        );
      }),
    );
  }
}

class _Picture extends StatelessWidget {
  const _Picture({required this.d});
  final ViewAsData d;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = d.profile;
    final name = d.name;
    final parts = name.trim().split(RegExp(r'\s+')).where((x) => x.isNotEmpty).toList();
    final initials = parts.isEmpty
        ? '?'
        : (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
    final date = DateFormat('d MMM yyyy');
    DateTime? when(Object? v) => v == null ? null : DateTime.tryParse(v as String)?.toLocal();
    String statusLabel(String s) => switch (s) {
          'submitted' => 'Submitted',
          'under_review' => 'Under review',
          'approved' => 'Approved',
          'collected' => 'On loan',
          'returned' => 'Returned',
          'rejected' => 'Rejected',
          'cancelled' => 'Cancelled',
          _ => s,
        };

    final borrows = d.list('borrows');
    final saved = d.list('saved');
    final notices = d.list('announcements');
    final updates = d.list('updates');
    final library = d.library;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          InitialsAvatar(initials, size: 56),
          const SizedBox(width: Gap.snug),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: t.headlineSmall),
              Text(
                [
                  d.role == 'librarian' ? 'Librarian' : 'Student',
                  if (p['department'] != null) '${p['department']}',
                  if (p['year_of_study'] != null) 'Year ${p['year_of_study']}',
                ].join('  /  '),
                style: t.bodyMedium,
              ),
            ]),
          ),
        ]),
        const SizedBox(height: Gap.tight),
        Text('Study notes, kits, plans and progress are private and are never shown here.', style: t.bodySmall),
        if (library != null) ...[
          const ShelfHeading('Their Today screen'),
          StatGrid(children: [
            StatTile(value: '${library.waitingCount}', label: 'Waiting for a decision'),
            StatTile(value: '${library.collectionsCount}', label: 'Collections due today'),
            StatTile(value: '${library.overdueCount}', label: 'Overdue copies'),
            StatTile(value: '${library.lowStockCount}', label: 'Books with none on the shelf'),
          ]),
        ],
        if (d.role == 'student') ...[
          const ShelfHeading('Borrowing'),
          if (borrows.isEmpty)
            const StudyEmptyState('No borrowing yet.', compact: true)
          else
            RowGroup(children: [
              for (final b in borrows)
                StudyRow(
                  title: (b['title'] ?? '') as String,
                  detail: [
                    'Asked ${when(b['requested_at']) == null ? '' : date.format(when(b['requested_at'])!)}',
                    if (when(b['due_date']) != null) 'due ${date.format(when(b['due_date'])!)}',
                  ].join('  /  '),
                  detailLines: 1,
                  tags: [Tag(statusLabel((b['status'] ?? '') as String))],
                ),
            ]),
          const ShelfHeading('Saved'),
          if (saved.isEmpty)
            const StudyEmptyState('Nothing saved.', compact: true)
          else
            RowGroup(children: [
              for (final s in saved)
                StudyRow(title: (s['title'] ?? '') as String, detail: (s['course_code'] ?? '') as String?, detailLines: 1),
            ]),
        ],
        const ShelfHeading('Announcements they see'),
        if (notices.isEmpty)
          const StudyEmptyState('No live announcements for them.', compact: true)
        else
          RowGroup(children: [
            for (final a in notices) StudyRow(title: (a['title'] ?? '') as String, detail: (a['body'] ?? '') as String?),
          ]),
        const ShelfHeading('Their updates'),
        if (updates.isEmpty)
          const StudyEmptyState('No updates.', compact: true)
        else
          RowGroup(children: [
            for (final u in updates)
              StudyRow(
                title: (u['subject'] ?? '') as String,
                detail: (u['body'] ?? '') as String?,
                meta: when(u['created_at']) == null ? null : studyDateTime.format(when(u['created_at'])!),
                tags: [if (u['read_at'] == null) const Tag('Unread')],
              ),
          ]),
      ],
    );
  }
}
