import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/failure.dart';
import '../../../core/theme.dart';
import '../../../models/resource.dart';
import '../../../state/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/state_views.dart';

/// The student types nothing about who they are. The identity on the request
/// is the one the roll verified at registration.
class BorrowRequestScreen extends ConsumerStatefulWidget {
  const BorrowRequestScreen({super.key, required this.resourceId});
  final String resourceId;

  @override
  ConsumerState<BorrowRequestScreen> createState() => _BorrowRequestScreenState();
}

class _BorrowRequestScreenState extends ConsumerState<BorrowRequestScreen> {
  DateTime _collection = DateTime.now().add(const Duration(days: 1));
  bool _busy = false;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _collection,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
      helpText: 'When will you collect it?',
    );
    if (picked != null) setState(() => _collection = picked);
  }

  Future<void> _submit() async {
    final profile = ref.read(profileProvider).value;
    if (profile == null) return;
    setState(() => _busy = true);
    try {
      await borrowRepo.apply(
        resourceId: widget.resourceId,
        student: profile,
        collectionDate: _collection,
      );
      refreshBorrowing(ref);
      if (!mounted) return;
      showMessage(context, 'Request submitted. The decision will appear '
          'under Updates.');
      context.go('/borrowing');
    } on Failure catch (f) {
      if (mounted) showMessage(context, f.message, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).valueOrNull;
    final async = ref.watch(resourceProvider(widget.resourceId));

    return Scaffold(
      appBar: AppBar(title: const Text('Apply to borrow')),
      body: AsyncView<Resource>(
        value: async,
        data: (r) => SingleChildScrollView(
          padding: const EdgeInsets.all(Insets.md),
          child: Readable(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(Insets.md),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TypeBadge(r.type),
                        const SizedBox(width: Insets.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r.title,
                                  style: Theme.of(context).textTheme.titleMedium),
                              const SizedBox(height: 3),
                              MetaLine([r.courseCode, '${r.academicYear}']),
                              const SizedBox(height: Insets.sm),
                              Text(r.availabilityLabel,
                                  style: TextStyle(
                                    color: Palette.good,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12.5,
                                  )),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SectionHeading('The librarian will see'),
                Card(
                  child: Column(
                    children: [
                      _Row('Name', profile?.fullName ?? ''),
                      const Divider(height: 1),
                      _Row('Student number', profile?.studentNumber ?? ''),
                      const Divider(height: 1),
                      _Row('Programme', profile?.programme ?? ''),
                    ],
                  ),
                ),
                const SizedBox(height: Insets.sm),
                Text(
                  'These details came from the institutional roll when your '
                  'account was created. You will not be asked for an '
                  'identification document.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SectionHeading('Collection'),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.event_outlined),
                    title: const Text('Planned collection date'),
                    subtitle: Text(dateFmt.format(_collection)),
                    trailing: TextButton(
                      onPressed: _pickDate,
                      child: const Text('Change'),
                    ),
                  ),
                ),
                const SizedBox(height: Insets.lg),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? SizedBox(
                          height: 19, width: 19,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.2, color: Palette.onAccent))
                      : const Text('Submit request'),
                ),
                const SizedBox(height: Insets.sm),
                Text(
                  'A copy is only reserved once a librarian approves the '
                  'request, so submitting does not take it off the shelf.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: Insets.xl),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);
  final String label, value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: Insets.md, vertical: 13),
        child: Row(
          children: [
            SizedBox(
                width: 130,
                child: Text(label,
                    style: Theme.of(context).textTheme.bodyMedium)),
            Expanded(
                child: Text(value,
                    style: const TextStyle(fontWeight: FontWeight.w600))),
          ],
        ),
      );
}
