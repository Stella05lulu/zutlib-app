import 'package:flutter/widgets.dart';

/// Phones open PDFs in the device's own reader instead, so this is never
/// built off the web.
class PdfFrame extends StatelessWidget {
  const PdfFrame({super.key, required this.url, required this.title});
  final String url, title;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

const bool canEmbedPdf = false;
