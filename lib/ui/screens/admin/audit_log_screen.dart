import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart' show kNavClearance;
import '../../../core/theme/app_theme.dart';
import '../../../data/admin_repository.dart' show AuditEntry;
import '../../../state/governance_providers.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/notification_bell.dart';
import '../../widgets/audit_activity.dart';
import '../../widgets/study_widgets.dart';

/// The audit log: every administrator, super admin and borrowing action,
/// newest first. Read only; the database refuses edits and deletes from
/// everyone using the app (0017).
class AuditLogScreen extends ConsumerStatefulWidget {
  const AuditLogScreen({super.key});

  @override
  ConsumerState<AuditLogScreen> createState() => _AuditLogScreenState();
}

const _categories = <(String, String?)>[
  ('All', null),
  ('Accounts', 'admin.'),
  ('Borrowing', 'borrow.'),
  ('System', 'system.'),
];

class _AuditLogScreenState extends ConsumerState<AuditLogScreen> {
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search.text = ref.read(auditSearchProvider);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _details(AuditEntry e) {
    final pretty = const JsonEncoder.withIndent('  ').convert(e.detail);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final t = Theme.of(ctx).textTheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.page),
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e.label, style: t.headlineSmall),
                const SizedBox(height: Gap.tight),
                Text('${e.actorName ?? 'The system'}  /  ${studyDateTime.format(e.at)}', style: t.bodyMedium),
                const SizedBox(height: Gap.tight),
                Text('Action ${e.action}  /  item ${e.targetId}', style: Mono.of(ctx, size: 12)),
                const SizedBox(height: Gap.page),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(Gap.snug),
                  decoration: BoxDecoration(
                    color: StudyColors.of(ctx).sunken,
                    borderRadius: BorderRadius.circular(Radii.control),
                  ),
                  child: SelectableText(pretty, style: Mono.of(ctx, size: 12.5)),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(auditLogProvider);
    final category = ref.watch(auditCategoryProvider);
    return StudyScope(
      child: Builder(builder: (context) {
        final t = Theme.of(context).textTheme;
        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: StudyPage(
              bottom: kNavClearance,
              onRefresh: () async {
                ref.invalidate(auditLogProvider);
                ref.invalidate(auditStatsProvider);
                try {
                  await ref.read(auditLogProvider.future);
                } catch (_) {
                  // Shown on screen.
                }
              },
              children: [
                Row(children: [
                  const ShellMenuButton(),
                  Expanded(child: Text('Audit log', style: t.headlineSmall)),
                  const NotificationBell(),
                ]),
                const SizedBox(height: Gap.hair),
                Text('Who did what, and when. Nobody can edit or delete these entries from the app.', style: t.bodyMedium),
                const SizedBox(height: Gap.page),
                const AuditActivity(),
                const SizedBox(height: Gap.section),
                TextField(
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(hintText: 'Search actions, for example suspend', prefixIcon: Icon(Icons.search, size: 20)),
                  onSubmitted: (v) => ref.read(auditSearchProvider.notifier).state = v,
                ),
                const SizedBox(height: Gap.snug),
                Wrap(spacing: Gap.tight, runSpacing: Gap.tight, children: [
                  for (final (label, prefix) in _categories)
                    ChoiceChip(
                      label: Text(label),
                      selected: category == prefix,
                      onSelected: (_) => ref.read(auditCategoryProvider.notifier).state = prefix,
                    ),
                ]),
                const SizedBox(height: Gap.snug),
                StudyAsync<List<AuditEntry>>(
                  value: async,
                  onRetry: () => ref.invalidate(auditLogProvider),
                  skeleton: const RowsSkeleton(rows: 8),
                  isEmpty: (v) => v.isEmpty,
                  empty: const StudyEmptyState('No entries match.'),
                  data: (items) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text('${items.length} ${items.length == 1 ? 'entry' : 'entries'}${items.length >= 200 ? ', newest 200' : ''}',
                        style: t.bodySmall),
                    const SizedBox(height: Gap.tight),
                    RowGroup(children: [
                      for (final e in items)
                        StudyRow(
                          title: e.label,
                          detail: [
                            e.actorName == null ? 'by the system' : 'by ${e.actorName}',
                            if (e.detail['reason'] != null) '${e.detail['reason']}',
                          ].join('  /  '),
                          detailLines: 1,
                          meta: studyDateTime.format(e.at),
                          trailing: const Icon(Icons.chevron_right, size: 20),
                          onTap: () => _details(e),
                        ),
                    ]),
                  ]),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}
