import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Confirms an account action and asks why it is being done. Returns the
/// reason, or null if the person cancels. The reason is stored in the audit
/// log by the server, next to who did what and when.
Future<String?> askReason(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _ReasonDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      destructive: destructive,
    ),
  );
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.destructive,
  });
  final String title;
  final String message;
  final String confirmLabel;
  final bool destructive;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _reason = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _confirm() {
    final v = _reason.text.trim();
    if (v.length < 3) return setState(() => _error = 'Say briefly why. It is kept in the audit log.');
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.message),
          const SizedBox(height: Gap.page),
          TextField(
            controller: _reason,
            autofocus: true,
            maxLength: 500,
            minLines: 2,
            maxLines: 4,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(labelText: 'Reason', errorText: _error),
            onSubmitted: (_) => _confirm(),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          style: widget.destructive ? TextButton.styleFrom(foregroundColor: c.danger) : null,
          onPressed: _confirm,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
