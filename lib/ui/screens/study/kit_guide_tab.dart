import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/study.dart';
import '../../../core/failure.dart';
import '../../../state/plan_providers.dart';
import '../../../state/study_providers.dart';
import '../../widgets/study_widgets.dart';
import 'kit_widgets.dart';

/// The AI study guide: an overview, then each topic with a short summary
/// and its key points. Actions: download as a PDF, or copy as text.
class KitGuideTab extends ConsumerStatefulWidget {
  const KitGuideTab({super.key, required this.kit, required this.onChanged});
  final KitData kit;
  final VoidCallback onChanged;

  @override
  ConsumerState<KitGuideTab> createState() => _KitGuideTabState();
}

class _KitGuideTabState extends ConsumerState<KitGuideTab> {
  bool _exporting = false;
  String? _message;
  bool _messageIsError = false;

  void _say(String m, {bool error = false}) {
    if (mounted) {
      setState(() {
        _message = m;
        _messageIsError = error;
      });
    }
  }

  String _plainText(StudyGuide g) {
    final b = StringBuffer()
      ..writeln(widget.kit.note.title)
      ..writeln()
      ..writeln(g.overview);
    for (final s in g.sections) {
      b
        ..writeln()
        ..writeln(s.heading);
      if (s.summary.trim().isNotEmpty) b.writeln(s.summary);
      for (final p in s.points) {
        b.writeln('- $p');
      }
    }
    return b.toString();
  }

  Future<void> _copy(StudyGuide g) async {
    await Clipboard.setData(ClipboardData(text: _plainText(g)));
    _say('The study guide was copied. Paste it anywhere.');
  }

  Future<void> _exportPdf(StudyGuide g) async {
    setState(() => _exporting = true);
    try {
      pw.ThemeData? theme;
      try {
        // IBM Plex, the module's typeface, downloaded once from Google Fonts.
        theme = pw.ThemeData.withFont(
          base: await PdfGoogleFonts.iBMPlexSansRegular(),
          bold: await PdfGoogleFonts.iBMPlexSansBold(),
        );
      } catch (_) {
        theme = null; // offline: the PDF's built-in font is used instead
      }
      final title = widget.kit.note.title;
      final doc = pw.Document(title: title, theme: theme);
      const ink = PdfColor.fromInt(0xFF1C2027);
      const soft = PdfColor.fromInt(0xFF4B5361);
      const accent = PdfColor.fromInt(0xFF1D5FC4);
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(48, 48, 48, 56),
          footer: (ctx) => pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text('ZutLib study guide  /  page ${ctx.pageNumber} of ${ctx.pagesCount}',
                style: const pw.TextStyle(fontSize: 9, color: soft)),
          ),
          build: (ctx) => [
            pw.Text(title, style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: ink)),
            pw.SizedBox(height: 10),
            pw.Paragraph(text: g.overview, style: const pw.TextStyle(fontSize: 11.5, color: soft, lineSpacing: 2)),
            for (final s in g.sections) ...[
              pw.SizedBox(height: 10),
              pw.Text(s.heading, style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: accent)),
              pw.SizedBox(height: 4),
              if (s.summary.trim().isNotEmpty)
                pw.Paragraph(text: s.summary, style: const pw.TextStyle(fontSize: 11, color: ink, lineSpacing: 2)),
              for (final p in s.points)
                pw.Bullet(text: p, style: const pw.TextStyle(fontSize: 11, color: ink), bulletColor: accent),
            ],
          ],
        ),
      );
      final safe = title.replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '').trim();
      await Printing.sharePdf(bytes: await doc.save(), filename: '${safe.isEmpty ? 'study-guide' : safe}.pdf');
    } catch (_) {
      _say('The PDF could not be made on this device. Try "Copy as text" instead.', error: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// Marks a section read (it counts towards today's plan) or unread.
  Future<void> _setRead(String guideId, int section, bool read) async {
    try {
      if (read) {
        await planRepo.markRead(guideId, section);
      } else {
        await planRepo.unmarkRead(guideId, section);
      }
      ref.invalidate(guideReadsProvider(guideId));
      ref.invalidate(activityProvider);
    } on Failure catch (f) {
      _say(f.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    final t = Theme.of(context).textTheme;
    final g = widget.kit.guide;
    final n = widget.kit.note;

    if (g == null) {
      return StudyPage(children: [
        KitEmpty(
          icon: Icons.menu_book_outlined,
          title: 'No study guide yet',
          sentence: n.hasMaterials
              ? 'AI writes a study guide from your materials, with every topic summarised and its key points listed.'
              : 'Add notes, a PDF or a video to this kit first, then AI can write a study guide from them.',
          actions: [
            if (n.hasMaterials)
              FilledButton.icon(
                onPressed: () => buildKitWithAi(context, ref, n.id),
                icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                label: const Text('Build with AI'),
              ),
          ],
        ),
      ]);
    }

    return StudyPage(
      onRefresh: () async => widget.onChanged(),
      children: [
        Row(
          children: [
            const Tag.ai(),
            const SizedBox(width: Gap.tight),
            Expanded(child: Text('Written ${studyDate.format(g.createdAt)}', style: Mono.of(context, size: 12))),
            MenuAnchor(
              builder: (context, controller, _) => FilledButton.tonalIcon(
                onPressed: _exporting ? null : () => controller.isOpen ? controller.close() : controller.open(),
                style: FilledButton.styleFrom(backgroundColor: c.accentWash, foregroundColor: c.accent),
                icon: const Icon(Icons.expand_more, size: 18),
                label: Text(_exporting ? 'Making PDF' : 'Actions'),
              ),
              menuChildren: [
                MenuItemButton(
                  leadingIcon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                  onPressed: () => _exportPdf(g),
                  child: const Text('Download as PDF'),
                ),
                MenuItemButton(
                  leadingIcon: const Icon(Icons.copy_outlined, size: 18),
                  onPressed: () => _copy(g),
                  child: const Text('Copy as text'),
                ),
              ],
            ),
          ],
        ),
        if (_message != null) ...[
          const SizedBox(height: Gap.snug),
          InlineNotice(_message!, error: _messageIsError, onClose: () => setState(() => _message = null)),
        ],
        const SizedBox(height: Gap.page),
        Text(n.title, style: t.headlineSmall?.copyWith(fontSize: 28, fontWeight: FontWeight.w700)),
        const SizedBox(height: Gap.snug),
        Text(g.overview, style: t.bodyLarge?.copyWith(color: c.inkSoft)),
        const SizedBox(height: Gap.section),
        for (var i = 0; i < g.sections.length; i++)
          _Section(
            number: i + 1,
            section: g.sections[i],
            read: (ref.watch(guideReadsProvider(g.id)).valueOrNull ?? const {}).containsKey(i),
            onRead: (read) => _setRead(g.id, i, read),
          ),
        const SizedBox(height: Gap.snug),
        Text('AI can make mistakes. Check the guide against your materials.', style: t.bodySmall),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.number, required this.section, required this.read, required this.onRead});
  final int number;
  final GuideSection section;
  final bool read;
  final ValueChanged<bool> onRead;

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.section),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: c.accentWash, borderRadius: BorderRadius.circular(Radii.control)),
                child: Text('$number', style: Mono.of(context, size: 13, weight: FontWeight.w600, color: c.accent)),
              ),
              const SizedBox(width: Gap.snug),
              Expanded(child: Text(section.heading, style: t.titleLarge)),
            ],
          ),
          if (section.summary.trim().isNotEmpty) ...[
            const SizedBox(height: Gap.tight),
            Text(section.summary, style: t.bodyLarge),
          ],
          if (section.points.isNotEmpty) ...[
            const SizedBox(height: Gap.tight),
            for (final p in section.points)
              Padding(
                padding: const EdgeInsets.only(top: Gap.hair + 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 9, left: 4, right: Gap.snug),
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
                      ),
                    ),
                    Expanded(child: Text(p, style: t.bodyLarge)),
                  ],
                ),
              ),
          ],
          const SizedBox(height: Gap.tight),
          Align(
            alignment: Alignment.centerLeft,
            child: read
                ? TextButton.icon(
                    onPressed: () => onRead(false),
                    icon: Icon(Icons.check_circle, size: 18, color: c.success),
                    label: Text('Read', style: TextStyle(color: c.success)),
                  )
                : OutlinedButton.icon(
                    onPressed: () => onRead(true),
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text('Mark as read'),
                  ),
          ),
        ],
      ),
    );
  }
}
