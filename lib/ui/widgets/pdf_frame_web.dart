import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

/// The browser's own PDF reader, embedded in the page. Loading the file in
/// a frame needs no new tab, so the browser's pop-up blocker never sees it.
class PdfFrame extends StatefulWidget {
  const PdfFrame({super.key, required this.url, required this.title});
  final String url, title;

  @override
  State<PdfFrame> createState() => _PdfFrameState();
}

class _PdfFrameState extends State<PdfFrame> {
  static int _next = 0;
  late final String _viewType = 'zutlib-pdf-${_next++}';

  @override
  void initState() {
    super.initState();
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) {
      return web.HTMLIFrameElement()
        ..src = widget.url
        ..title = widget.title
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%';
    });
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _viewType);
}

const bool canEmbedPdf = true;
