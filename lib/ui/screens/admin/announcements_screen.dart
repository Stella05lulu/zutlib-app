import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/failure.dart';
import '../../../core/theme.dart' show kNavClearance;
import '../../../core/theme/app_theme.dart';
import '../../../data/governance_repository.dart';
import '../../../models/profile.dart' show kStudentDepartments;
import '../../../state/governance_providers.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/notification_bell.dart';
import '../../widgets/study_widgets.dart';

/// Announcements, for administrators and the super admin: post, edit and
/// remove. Students see the latest on Home and all live ones in Updates.
/// Every change is audited by the database (0019).
class AnnouncementsScreen extends ConsumerStatefulWidget {
  const AnnouncementsScreen({super.key});

  @override
  ConsumerState<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends ConsumerState<AnnouncementsScreen> {
  String? _message;
  bool _isError = false;
  String _filter = 'live'; // live, ended, all

  Future<void> _run(String done, Future<void> Function() action) async {
    try {
      await action();
      ref.invalidate(announcementsProvider);
      ref.invalidate(auditLogProvider);
      if (mounted) {
        setState(() {
          _message = done;
          _isError = false;
        });
      }
    } on Failure catch (f) {
      if (mounted) {
        setState(() {
          _message = f.message;
          _isError = true;
        });
      }
    }
  }

  Future<void> _edit([Announcement? a]) async {
    final result = await showDialog<_Draft>(context: context, builder: (_) => _EditDialog(existing: a));
    if (result == null) return;
    await _run(a == null ? 'Announcement posted.' : 'Announcement updated.', () => governanceRepo.saveAnnouncement(
          id: a?.id,
          title: result.title,
          body: result.body,
          department: result.department,
          endsOn: result.endsOn,
        ));
  }

  Future<void> _remove(Announcement a) async {
    final ok = await confirmDelete(context,
        what: 'this announcement', consequence: 'Students stop seeing it straight away. The audit log keeps a record.');
    if (ok) await _run('Announcement removed.', () => governanceRepo.removeAnnouncement(a.id));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(announcementsProvider);
    return StudyScope(
      child: Builder(builder: (context) {
        final t = Theme.of(context).textTheme;
        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: StudyPage(
              bottom: kNavClearance,
              onRefresh: () async {
                ref.invalidate(announcementsProvider);
                try {
                  await ref.read(announcementsProvider.future);
                } catch (_) {
                  // Shown on screen.
                }
              },
              children: [
                Row(children: [
                  const ShellMenuButton(),
                  Expanded(child: Text('Announcements', style: t.headlineSmall)),
                  const NotificationBell(),
                ]),
                const SizedBox(height: Gap.hair),
                Text('Shown to students on Home and in Updates.', style: t.bodyMedium),
                const SizedBox(height: Gap.snug),
                Row(children: [
                  Expanded(
                    child: Wrap(spacing: Gap.tight, runSpacing: Gap.tight, children: [
                      for (final (k, label) in const [('live', 'Live'), ('ended', 'Ended'), ('all', 'All')])
                        ChoiceChip(label: Text(label), selected: _filter == k, onSelected: (_) => setState(() => _filter = k)),
                    ]),
                  ),
                  FilledButton.icon(
                    onPressed: () => _edit(),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('New'),
                  ),
                ]),
                if (_message != null) ...[
                  const SizedBox(height: Gap.snug),
                  InlineNotice(_message!, error: _isError, onClose: () => setState(() => _message = null)),
                ],
                const SizedBox(height: Gap.snug),
                StudyAsync<List<Announcement>>(
                  value: async,
                  onRetry: () => ref.invalidate(announcementsProvider),
                  skeleton: const RowsSkeleton(rows: 4),
                  isEmpty: (v) => v.isEmpty,
                  empty: const StudyEmptyState('No announcements yet. Post one to reach every student.'),
                  data: (all) {
                    final shown = [
                      for (final a in all)
                        if (_filter == 'all' || (_filter == 'ended') == a.hasEnded) a,
                    ];
                    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Text('${shown.length} ${shown.length == 1 ? 'announcement' : 'announcements'}', style: t.bodySmall),
                      const SizedBox(height: Gap.tight),
                      if (shown.isEmpty)
                        const StudyEmptyState('None in this list.', compact: true)
                      else
                        RowGroup(children: [
                          for (final a in shown)
                            StudyRow(
                              title: a.title,
                              detail: a.body,
                              meta: [
                                DateFormat('d MMM yyyy').format(a.createdAt),
                                a.department == null ? 'Everyone' : a.department!,
                                if (a.endsOn != null) 'ends ${DateFormat('d MMM').format(a.endsOn!)}',
                              ].join('  /  '),
                              tags: [
                                Tag(a.hasEnded ? 'Ended' : 'Live', sky: a.hasEnded),
                                if (a.isSample) const Tag('Sample'),
                              ],
                              trailing: PopupMenuButton<String>(
                                tooltip: 'Options for ${a.title}',
                                onSelected: (v) => v == 'edit' ? _edit(a) : _remove(a),
                                itemBuilder: (_) => const [
                                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                                  PopupMenuItem(value: 'remove', child: Text('Remove')),
                                ],
                              ),
                              onTap: () => _edit(a),
                            ),
                        ]),
                    ]);
                  },
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

class _Draft {
  const _Draft(this.title, this.body, this.department, this.endsOn);
  final String title;
  final String body;
  final String? department;
  final DateTime? endsOn;
}

class _EditDialog extends StatefulWidget {
  const _EditDialog({this.existing});
  final Announcement? existing;

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late final _title = TextEditingController(text: widget.existing?.title ?? '');
  late final _body = TextEditingController(text: widget.existing?.body ?? '');
  late String? _dept = widget.existing?.department;
  late DateTime? _ends = widget.existing?.endsOn;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _ends != null && !_ends!.isBefore(today) ? _ends! : today.add(const Duration(days: 7)),
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
      helpText: 'Show until',
    );
    if (picked != null) setState(() => _ends = picked);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'New announcement' : 'Edit announcement'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(controller: _title, maxLength: 120, decoration: const InputDecoration(labelText: 'Title')),
            TextField(
              controller: _body,
              maxLength: 2000,
              minLines: 3,
              maxLines: 8,
              decoration: const InputDecoration(labelText: 'Message'),
            ),
            DropdownButtonFormField<String?>(
              initialValue: _dept,
              decoration: const InputDecoration(labelText: 'Who sees it'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Every student')),
                for (final d in kStudentDepartments) DropdownMenuItem<String?>(value: d, child: Text('$d students')),
              ],
              onChanged: (v) => setState(() => _dept = v),
            ),
            const SizedBox(height: Gap.snug),
            Row(children: [
              Expanded(
                child: Text(_ends == null ? 'No end date' : 'Shown until ${DateFormat('EEE d MMM yyyy').format(_ends!)}'),
              ),
              if (_ends != null) TextButton(onPressed: () => setState(() => _ends = null), child: const Text('Clear')),
              TextButton(onPressed: _pickDate, child: const Text('End date')),
            ]),
            if (_error != null) Text(_error!, style: TextStyle(color: StudyColors.of(context).danger)),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          onPressed: () {
            if (_title.text.trim().length < 3 || _body.text.trim().length < 3) {
              return setState(() => _error = 'Give it a title and a message of at least 3 characters.');
            }
            Navigator.pop(context, _Draft(_title.text.trim(), _body.text.trim(), _dept, _ends));
          },
          child: Text(widget.existing == null ? 'Post' : 'Save'),
        ),
      ],
    );
  }
}
