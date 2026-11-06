import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

/// The PDF reader on phones and desktops: the file is downloaded once and
/// its pages drawn inside the app, so it can be pinched to zoom (or zoomed
/// with the + and - buttons) and dragged around. It used to be handed to
/// the browser, which showed it at one fixed size.
class PdfFrame extends StatefulWidget {
  const PdfFrame({super.key, required this.url, required this.title});
  final String url, title;

  @override
  State<PdfFrame> createState() => _PdfFrameState();
}

class _PdfFrameState extends State<PdfFrame> {
  static const _minScale = 1.0, _maxScale = 5.0;

  final _zoom = TransformationController();
  final _pages = <Uint8List>[];
  bool _done = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final bytes = await _download(widget.url);
      // Pages arrive one at a time, so the first shows before the rest.
      await for (final page in Printing.raster(bytes, dpi: 160)) {
        final png = await page.toPng();
        if (!mounted) return;
        setState(() => _pages.add(png));
      }
      if (mounted) setState(() => _done = true);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  static Future<Uint8List> _download(String url) async {
    final client = HttpClient();
    try {
      final res = await (await client.getUrl(Uri.parse(url))).close();
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      final out = BytesBuilder(copy: false);
      await for (final chunk in res) {
        out.add(chunk);
      }
      return out.takeBytes();
    } finally {
      client.close();
    }
  }

  double get _scale => _zoom.value.getMaxScaleOnAxis();

  void _zoomTo(double scale) {
    final s = scale.clamp(_minScale, _maxScale);
    _zoom.value = Matrix4.diagonal3Values(s, s, 1);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_failed && _pages.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Could not show this PDF here. Use the open button at the top to read it in another app.',
              textAlign: TextAlign.center),
        ),
      );
    }
    if (_pages.isEmpty) return const Center(child: CircularProgressIndicator());

    return LayoutBuilder(builder: (context, box) {
      final width = box.maxWidth;
      return Stack(children: [
        ColoredBox(
          color: scheme.surfaceContainerHighest,
          child: SizedBox.expand(
            child: InteractiveViewer(
              transformationController: _zoom,
              constrained: false,
              minScale: _minScale,
              maxScale: _maxScale,
              boundaryMargin: EdgeInsets.zero,
              onInteractionEnd: (_) => setState(() {}),
              child: SizedBox(
                width: width,
                child: Column(children: [
                  for (var i = 0; i < _pages.length; i++)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                      child: Semantics(
                        label: 'Page ${i + 1}',
                        child: Image.memory(_pages[i], width: width - 16, fit: BoxFit.fitWidth, gaplessPlayback: true),
                      ),
                    ),
                  if (!_done)
                    const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()),
                  const SizedBox(height: 88),
                ]),
              ),
            ),
          ),
        ),
        Positioned(
          right: 12,
          bottom: 12,
          child: Material(
            elevation: 3,
            color: scheme.surface,
            borderRadius: BorderRadius.circular(28),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: 'Zoom out',
                icon: const Icon(Icons.remove),
                onPressed: _scale > _minScale ? () => _zoomTo(_scale / 1.5) : null,
              ),
              Text('${(_scale * 100).round()}%'),
              IconButton(
                tooltip: 'Zoom in',
                icon: const Icon(Icons.add),
                onPressed: _scale < _maxScale ? () => _zoomTo(_scale * 1.5) : null,
              ),
            ]),
          ),
        ),
      ]);
    });
  }
}

/// Every platform reads PDFs inside the app now.
const bool canEmbedPdf = true;
