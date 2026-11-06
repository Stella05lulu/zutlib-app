import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../widgets/pdf_frame_stub.dart' if (dart.library.js_interop) '../../widgets/pdf_frame_web.dart';
import '../../widgets/study_widgets.dart';

/// Opens a PDF inside the app. On the web it is the browser's own reader in
/// a frame (a new tab opened after waiting for the signed link counts as a
/// pop-up, and browsers block it without a word). On phones the pages are
/// drawn by the app so they can be zoomed.
///
/// [loadUrl] makes the short-lived signed link. Returns an error message
/// for the caller to show, or null when the PDF opened.
Future<String?> openPdf(BuildContext context,
    {required String title, required Future<String> Function() loadUrl}) async {
  if (canEmbedPdf) {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PdfViewerScreen(title: title, loadUrl: loadUrl),
    ));
    return null;
  }
  try {
    final ok = await launchUrl(Uri.parse(await loadUrl()), mode: LaunchMode.externalApplication);
    return ok ? null : 'Could not open the PDF on this device.';
  } on Failure catch (f) {
    return f.message;
  }
}

class PdfViewerScreen extends StatefulWidget {
  const PdfViewerScreen({super.key, required this.title, required this.loadUrl});
  final String title;
  final Future<String> Function() loadUrl;

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  late Future<String> _url = widget.loadUrl();

  @override
  Widget build(BuildContext context) {
    return StudyScope(
      child: FutureBuilder<String>(
        future: _url,
        builder: (context, snap) {
          final url = snap.data;
          return Scaffold(
            appBar: StudyTopBar(title: widget.title, actions: [
              if (url != null)
                IconButton(
                  tooltip: kIsWeb ? 'Open in a new tab' : 'Open in another app',
                  icon: const Icon(Icons.open_in_new),
                  // A direct tap with the link already in hand, so the
                  // browser allows the new tab.
                  onPressed: () => launchUrl(Uri.parse(url),
                      mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
                      webOnlyWindowName: '_blank'),
                ),
            ]),
            body: switch (snap) {
              AsyncSnapshot(hasError: true, :final error) => Padding(
                  padding: const EdgeInsets.all(Gap.page),
                  child: StudyErrorState(
                    message: error is Failure ? error.message : 'Could not load the PDF.',
                    onRetry: () => setState(() => _url = widget.loadUrl()),
                  ),
                ),
              AsyncSnapshot(hasData: true) => PdfFrame(url: url!, title: widget.title),
              _ => const Padding(padding: EdgeInsets.all(Gap.page), child: TextSkeleton(paragraphs: 4)),
            },
          );
        },
      ),
    );
  }
}
