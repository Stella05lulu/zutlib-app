import 'package:flutter/material.dart';

import '../../core/failure.dart';
import '../../core/theme/app_theme.dart';
import '../../state/plan_providers.dart' show accountRepo;
import 'common.dart' show showMessage;
import 'study_widgets.dart';

/// "Send feedback": a short message to the people who run ZutLib. Saved
/// with the app version; administrators read it on their dashboard.
Future<void> showFeedbackSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const StudyScope(child: _FeedbackSheet()),
  );
}

class _FeedbackSheet extends StatefulWidget {
  const _FeedbackSheet();

  @override
  State<_FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends State<_FeedbackSheet> {
  final _text = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_text.text.trim().isEmpty) return setState(() => _error = 'Write a few words first.');
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await accountRepo.sendFeedback(_text.text);
      if (!mounted) return;
      Navigator.of(context).pop();
      showMessage(context, 'Thank you. Your feedback was sent.');
    } on Failure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, MediaQuery.viewInsetsOf(context).bottom + Gap.page),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Send feedback', style: t.headlineSmall),
          const SizedBox(height: Gap.hair),
          Text('Something not working, or an idea to make ZutLib better? Administrators read every message.',
              style: t.bodyMedium),
          const SizedBox(height: Gap.page),
          TextField(
            controller: _text,
            minLines: 4,
            maxLines: 8,
            maxLength: 2000,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Your message'),
          ),
          if (_error != null) ...[
            const SizedBox(height: Gap.tight),
            InlineNotice(_error!, error: true, onClose: () => setState(() => _error = null)),
          ],
          const SizedBox(height: Gap.snug),
          FilledButton(onPressed: _sending ? null : _send, child: Text(_sending ? 'Sending' : 'Send')),
        ],
      ),
    );
  }
}
