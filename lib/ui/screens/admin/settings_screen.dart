import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/failure.dart';
import '../../../core/theme.dart' show kNavClearance;
import '../../../core/theme/app_theme.dart';
import '../../../data/governance_repository.dart';
import '../../../state/governance_providers.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/notification_bell.dart';
import '../../widgets/reason_dialog.dart';
import '../../widgets/reauth.dart';
import '../../widgets/study_widgets.dart';

/// System settings, super admin only. The database reads these values
/// itself: the due date when a copy is collected, the borrowing limit on
/// every request, and sign-up (0018). Each save is audited with the values
/// before and after.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(settingsProvider);
    return StudyScope(
      child: Builder(builder: (context) {
        final t = Theme.of(context).textTheme;
        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: StudyPage(
              bottom: kNavClearance,
              onRefresh: () async {
                ref.invalidate(settingsProvider);
                try {
                  await ref.read(settingsProvider.future);
                } catch (_) {
                  // Shown on screen.
                }
              },
              children: [
                Row(children: [
                  const ShellMenuButton(),
                  Expanded(child: Text('Settings', style: t.headlineSmall)),
                  const NotificationBell(),
                ]),
                const SizedBox(height: Gap.hair),
                Text('Rules the whole library follows. The database enforces them, not just the app.', style: t.bodyMedium),
                const SizedBox(height: Gap.page),
                StudyAsync<SystemSettings>(
                  value: async,
                  onRetry: () => ref.invalidate(settingsProvider),
                  skeleton: const RowsSkeleton(rows: 3),
                  data: (s) => _Form(key: ValueKey(s.updatedAt), initial: s),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

class _Form extends ConsumerStatefulWidget {
  const _Form({super.key, required this.initial});
  final SystemSettings initial;

  @override
  ConsumerState<_Form> createState() => _FormState();
}

class _FormState extends ConsumerState<_Form> {
  late int _days = widget.initial.loanDays;
  late int _max = widget.initial.maxActiveBorrows;
  late bool _open = widget.initial.registrationOpen;
  bool _saving = false;
  String? _message;
  bool _isError = false;

  bool get _changed =>
      _days != widget.initial.loanDays || _max != widget.initial.maxActiveBorrows || _open != widget.initial.registrationOpen;

  Future<void> _save() async {
    if (!_changed) {
      setState(() {
          _message = 'Nothing has changed yet.';
          _isError = false;
        });
      return;
    }
    final reason = await askReason(
      context,
      title: 'Save settings?',
      message: 'This changes the rules for everyone straight away.',
      confirmLabel: 'Save',
    );
    if (reason == null || !mounted) return;
    if (!await confirmRecentSignIn(context)) return;
    setState(() => _saving = true);
    try {
      await governanceRepo.saveSettings(loanDays: _days, maxActiveBorrows: _max, registrationOpen: _open, reason: reason);
      ref.invalidate(settingsProvider);
      ref.invalidate(auditLogProvider);
      if (mounted) {
        setState(() {
          _message = 'Settings saved.';
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
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _stepper(String label, String help, int value, int min, int max, ValueChanged<int> onChanged, String unit) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Gap.page - 4, vertical: Gap.snug),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: t.titleMedium),
            Text(help, style: t.bodySmall),
          ]),
        ),
        IconButton(
          tooltip: 'Less',
          onPressed: value > min ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove),
        ),
        SizedBox(
          width: 64,
          child: Text('$value $unit', textAlign: TextAlign.center, style: Mono.of(context, size: 14, weight: FontWeight.w600)),
        ),
        IconButton(
          tooltip: 'More',
          onPressed: value < max ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_message != null) ...[
        InlineNotice(_message!, error: _isError, onClose: () => setState(() => _message = null)),
        const SizedBox(height: Gap.snug),
      ],
      RowGroup(children: [
        _stepper('Borrowing period', 'Days from collection to the due date.', _days, 1, 90, (v) => setState(() => _days = v), 'days'),
        _stepper('Borrowing limit', 'Active requests and loans one student may have.', _max, 1, 20,
            (v) => setState(() => _max = v), ''),
        SwitchListTile(
          title: Text('Registration open', style: t.titleMedium),
          subtitle: Text(_open ? 'Anyone can sign up and wait for approval.' : 'Closed. Only invited people can join.',
              style: t.bodySmall),
          value: _open,
          onChanged: (v) => setState(() => _open = v),
        ),
      ]),
      const SizedBox(height: Gap.page),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving' : 'Save changes'),
        ),
      ),
      if (widget.initial.updatedAt != null) ...[
        const SizedBox(height: Gap.tight),
        Text('Last changed ${studyDateTime.format(widget.initial.updatedAt!)}', style: t.bodySmall),
      ],
    ]);
  }
}
