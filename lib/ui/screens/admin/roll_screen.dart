import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/failure.dart';
import '../../../core/theme.dart';
import '../../../data/admin_repository.dart';
import '../../../state/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/state_views.dart';

/// The roll is the source of eligibility. Only an administrator writes it,
/// and no client can read it except through this screen.
class RollScreen extends ConsumerStatefulWidget {
  const RollScreen({super.key});
  @override
  ConsumerState<RollScreen> createState() => _RollScreenState();
}

class _RollScreenState extends ConsumerState<RollScreen> {
  final _search = TextEditingController();
  bool _importing = false;

  @override
  void dispose() { _search.dispose(); super.dispose(); }

  Future<void> _import() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: ['csv'], withData: true);
    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.first.bytes;
    if (bytes == null) return;

    setState(() => _importing = true);
    try {
      final count = await adminRepo.importRoll(utf8.decode(bytes, allowMalformed: true));
      ref.invalidate(rollProvider);
      if (mounted) showMessage(context, 'Imported $count records.');
    } on Failure catch (f) {
      if (mounted) showMessage(context, f.message, isError: true);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(rollProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Student roll'),
        actions: [
          TextButton.icon(
            onPressed: _importing ? null : _import,
            icon: _importing
                ? const SizedBox(
                    height: 15, width: 15,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.upload_file, size: 19),
            label: const Text('Import CSV'),
          ),
          const SizedBox(width: Insets.sm),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: Palette.surface,
            padding: const EdgeInsets.fromLTRB(
                Insets.md, 0, Insets.md, Insets.md),
            child: Readable(
              maxWidth: 900,
              child: TextField(
                controller: _search,
                onChanged: (v) =>
                    ref.read(rollSearchProvider.notifier).state = v,
                decoration: const InputDecoration(
                  hintText: 'Search by student number or surname',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: AsyncView<List<RollEntry>>(
              value: async,
              onRetry: () => ref.invalidate(rollProvider),
              data: (rows) {
                if (rows.isEmpty) {
                  return EmptyView(
                    icon: Icons.badge_outlined,
                    headline: 'No roll loaded',
                    body: 'Import a CSV with student_number, surname, '
                        'programme, department and intake_year columns. '
                        'Nobody can register until this exists.',
                    action: FilledButton(
                        onPressed: _import, child: const Text('Import a CSV')),
                  );
                }
                final columns = catalogGridColumns(MediaQuery.sizeOf(context).width);
                return GridView.builder(
                  padding: const EdgeInsets.fromLTRB(
                Insets.md, Insets.md, Insets.md, kNavClearance),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: Insets.md,
                    crossAxisSpacing: Insets.md,
                    mainAxisExtent: 224,
                  ),
                  itemCount: rows.length,
                  itemBuilder: (_, i) => RollCard(entry: rows[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// A directory tile: an initials avatar standing in for a photo, a status
/// tag overlaid on the banner the way a catalogue tags a card, then the
/// student's number and the roll details below.
class RollCard extends StatelessWidget {
  const RollCard({super.key, required this.entry});
  final RollEntry entry;

  String get _initials {
    final first = entry.firstName;
    if (first != null && first.isNotEmpty) {
      return (first[0] + (entry.surname.isNotEmpty ? entry.surname[0] : ''))
          .toUpperCase();
    }
    return entry.surname.isNotEmpty ? entry.surname[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    final name = [entry.firstName, entry.surname]
        .where((s) => s != null && s.isNotEmpty)
        .join(' ');

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              Container(
                height: 92,
                width: double.infinity,
                color: Palette.canvas,
                alignment: Alignment.center,
                child: Container(
                  height: 52, width: 52,
                  decoration: BoxDecoration(
                      color: Palette.blueWash, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: Text(_initials,
                      style: TextStyle(
                        color: Palette.blueDeep,
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      )),
                ),
              ),
              Positioned(
                left: 8, bottom: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: (entry.claimed ? Palette.good : Palette.ink)
                        .withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(Corners.chip),
                  ),
                  child: Text(
                    entry.claimed ? 'REGISTERED' : 'NOT YET USED',
                    style: TextStyle(
                      color: Palette.onAccent,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ),
            ],
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Insets.sm, Insets.sm, Insets.sm, 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(entry.studentNumber,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            height: 1.25,
                            color: Palette.ink,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(name.isEmpty ? '—' : name,
                          style: Theme.of(context).textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                  Row(
                    children: [
                      Icon(Icons.event_outlined,
                          size: 14, color: Palette.inkFaint),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '${entry.programme} · ${entry.department} · '
                          'Intake ${entry.intakeYear}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Palette.inkSoft,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
