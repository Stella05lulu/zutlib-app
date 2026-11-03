import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/theme/app_theme.dart';
import '../../../state/plan_providers.dart';
import '../../widgets/study_widgets.dart';

/// The administrator's report for the last 7, 30 or 90 days. Built from
/// anonymous events (no names) and borrowing records by admin_reports().
final reportsProvider = FutureProvider.autoDispose.family<Report, int>((ref, days) async {
  return Report(await accountRepo.reports(days), days);
});

class Report {
  Report(this.raw, this.days);
  final Map<String, dynamic> raw;
  final int days;

  Map<String, dynamic> _map(String k) => Map<String, dynamic>.from((raw[k] as Map?) ?? const {});
  int _int(Map<String, dynamic> m, String k) => ((m[k] as num?) ?? 0).toInt();

  List<(String, int)> _list(String k) => [
        for (final e in (raw[k] as List? ?? const []))
          ((e as Map)['label']?.toString() ?? '', ((e['n'] as num?) ?? 0).toInt()),
      ];

  Map<String, dynamic> get borrowing => _map('borrowing');
  Map<String, dynamic> get study => _map('study');

  int get requests => _int(borrowing, 'requests');
  int get approved => _int(borrowing, 'approved');
  int get rejected => _int(borrowing, 'rejected');
  int get returned => _int(borrowing, 'returned');
  int get onLoan => _int(borrowing, 'on_loan');
  int get overdue => _int(borrowing, 'overdue');
  int get kitsBuilt => _int(study, 'kits_built');
  int get testsTaken => _int(study, 'tests_taken');
  int get plansActive => _int(study, 'plans_active');

  /// Share of books on loan that are overdue, as a whole percentage.
  int get overdueRate => onLoan == 0 ? 0 : (overdue * 100 / onLoan).round();

  List<(String, int)> get searchedCourses => _list('searched_courses');
  List<(String, int)> get openedItems => _list('opened_items');
  List<(String, int)> get borrowedItems => _list('borrowed_items');

  List<(DateTime, int, int)> get weekly => [
        for (final e in (raw['weekly'] as List? ?? const []))
          (
            DateTime.parse((e as Map)['week'] as String),
            ((e['studying'] as num?) ?? 0).toInt(),
            ((e['signups'] as num?) ?? 0).toInt(),
          ),
      ];
}

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  int _days = 30;
  bool _exporting = false;
  String? _message;

  Future<void> _exportPdf(Report r) async {
    setState(() => _exporting = true);
    try {
      pw.ThemeData? theme;
      try {
        theme = pw.ThemeData.withFont(
          base: await PdfGoogleFonts.iBMPlexSansRegular(),
          bold: await PdfGoogleFonts.iBMPlexSansBold(),
        );
      } catch (_) {
        theme = null; // offline: the PDF's built-in font is used
      }
      const ink = PdfColor.fromInt(0xFF1C2027);
      const soft = PdfColor.fromInt(0xFF4B5361);
      const accent = PdfColor.fromInt(0xFF1D5FC4);
      final doc = pw.Document(title: 'ZutLib report', theme: theme);
      pw.Widget table(String title, List<(String, int)> rows) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(height: 14),
              pw.Text(title, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: accent)),
              pw.SizedBox(height: 4),
              if (rows.isEmpty) pw.Text('Nothing recorded yet.', style: const pw.TextStyle(fontSize: 10.5, color: soft)),
              for (final (label, n) in rows)
                pw.Row(children: [
                  pw.Expanded(child: pw.Text(label, style: const pw.TextStyle(fontSize: 10.5, color: ink))),
                  pw.Text('$n', style: const pw.TextStyle(fontSize: 10.5, color: ink)),
                ]),
            ],
          );
      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(48, 48, 48, 56),
        build: (ctx) => [
          pw.Text('ZutLib report', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: ink)),
          pw.Text('Last ${r.days} days, made ${DateFormat('d MMM yyyy').format(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 11, color: soft)),
          table('Borrowing', [
            ('Requests', r.requests),
            ('Approved', r.approved),
            ('Rejected', r.rejected),
            ('Returned', r.returned),
            ('On loan now', r.onLoan),
            ('Overdue now', r.overdue),
          ]),
          table('Study', [('Kits built', r.kitsBuilt), ('Tests taken', r.testsTaken), ('Exam plans active', r.plansActive)]),
          table('Most searched courses', r.searchedCourses),
          table('Most opened items', r.openedItems),
          table('Most borrowed items', r.borrowedItems),
          table('Students studying per week', [
            for (final (week, studying, _) in r.weekly) ('Week of ${DateFormat('d MMM').format(week)}', studying),
          ]),
        ],
      ));
      await Printing.sharePdf(bytes: await doc.save(), filename: 'zutlib-report-${r.days}-days.pdf');
    } catch (_) {
      setState(() => _message = 'The PDF could not be made on this device.');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(reportsProvider(_days));
    return StudyScope(
      child: Builder(builder: (context) {
        final t = Theme.of(context).textTheme;
        final c = StudyColors.of(context);
        final r = async.valueOrNull;
        return Scaffold(
          appBar: StudyTopBar(title: 'Reports', actions: [
            if (r != null)
              TextButton.icon(
                onPressed: _exporting ? null : () => _exportPdf(r),
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: Text(_exporting ? 'Making PDF' : 'Download PDF'),
              ),
          ]),
          body: StudyPage(
            onRefresh: () async => ref.invalidate(reportsProvider(_days)),
            children: [
              Text('How ZutLib is used. Searches and opened items are recorded without names.',
                  style: t.bodyMedium),
              const SizedBox(height: Gap.page),
              SegmentedButton<int>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 7, label: Text('7 days')),
                  ButtonSegment(value: 30, label: Text('30 days')),
                  ButtonSegment(value: 90, label: Text('90 days')),
                ],
                selected: {_days},
                onSelectionChanged: (s) => setState(() => _days = s.first),
              ),
              if (_message != null) ...[
                const SizedBox(height: Gap.snug),
                InlineNotice(_message!, error: true, onClose: () => setState(() => _message = null)),
              ],
              StudyAsync<Report>(
                value: async,
                onRetry: () => ref.invalidate(reportsProvider(_days)),
                skeleton: const Padding(padding: EdgeInsets.only(top: Gap.page), child: RowsSkeleton(rows: 6)),
                data: (r) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SectionLabel('Borrowing'),
                    _Figures(items: [
                      ('Requests', r.requests),
                      ('Approved', r.approved),
                      ('Returned', r.returned),
                      ('On loan now', r.onLoan),
                      ('Overdue now', r.overdue),
                      ('Overdue rate', r.overdueRate),
                    ], percentLast: true),
                    const SectionLabel('Study'),
                    _Figures(items: [
                      ('Kits built', r.kitsBuilt),
                      ('Tests taken', r.testsTaken),
                      ('Exam plans active', r.plansActive),
                    ]),
                    const SectionLabel('Students studying each week'),
                    _WeekBars(weeks: r.weekly),
                    const SectionLabel('Most searched courses'),
                    _Ranked(rows: r.searchedCourses, empty: 'No searches by course yet.'),
                    const SectionLabel('Most opened items'),
                    _Ranked(rows: r.openedItems, empty: 'No items opened yet.'),
                    const SectionLabel('Most borrowed items'),
                    _Ranked(rows: r.borrowedItems, empty: 'No borrow requests in this period.'),
                    const SizedBox(height: Gap.page),
                    Text('Counts include sample data while it is loaded.', style: t.bodySmall?.copyWith(color: c.inkFaint)),
                  ],
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _Figures extends StatelessWidget {
  const _Figures({required this.items, this.percentLast = false});
  final List<(String, int)> items;
  final bool percentLast;

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    final t = Theme.of(context).textTheme;
    return LayoutBuilder(builder: (context, box) {
      final columns = box.maxWidth >= 560 ? 3 : 2;
      final width = (box.maxWidth - Gap.tight * (columns - 1)) / columns;
      return Wrap(
        spacing: Gap.tight,
        runSpacing: Gap.tight,
        children: [
          for (var i = 0; i < items.length; i++)
            Container(
              width: width,
              padding: const EdgeInsets.all(Gap.snug),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(Radii.control),
                border: Border.all(color: c.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    percentLast && i == items.length - 1 ? '${items[i].$2}%' : '${items[i].$2}',
                    style: Mono.of(context, size: 22, weight: FontWeight.w600, color: c.ink),
                  ),
                  Text(items[i].$1, style: t.bodySmall),
                ],
              ),
            ),
        ],
      );
    });
  }
}

class _WeekBars extends StatelessWidget {
  const _WeekBars({required this.weeks});
  final List<(DateTime, int, int)> weeks;

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    final t = Theme.of(context).textTheme;
    final top = weeks.fold<int>(1, (m, w) => w.$2 > m ? w.$2 : m);
    return RowGroup(children: [
      for (final (week, studying, signups) in weeks)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.page - 4, vertical: Gap.tight + 2),
          child: Row(
            children: [
              SizedBox(width: 70, child: Text(DateFormat('d MMM').format(week), style: Mono.of(context, size: 12))),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: studying == 0 ? 0.01 : studying / top,
                    child: Container(height: 10, decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(Radii.tag))),
                  ),
                ),
              ),
              const SizedBox(width: Gap.snug),
              SizedBox(
                width: 108,
                child: Text('$studying studying, $signups new', style: t.bodySmall, textAlign: TextAlign.right),
              ),
            ],
          ),
        ),
    ]);
  }
}

class _Ranked extends StatelessWidget {
  const _Ranked({required this.rows, required this.empty});
  final List<(String, int)> rows;
  final String empty;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return StudyEmptyState(empty, compact: true);
    final c = StudyColors.of(context);
    return RowGroup(children: [
      for (var i = 0; i < rows.length; i++)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.page - 4, vertical: Gap.snug),
          child: Row(
            children: [
              SizedBox(width: 26, child: Text('${i + 1}', style: Mono.of(context, size: 12, color: c.inkFaint))),
              Expanded(child: Text(rows[i].$1, style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: c.ink))),
              Text('${rows[i].$2}', style: Mono.of(context, size: 14, weight: FontWeight.w600, color: c.ink)),
            ],
          ),
        ),
    ]);
  }
}
