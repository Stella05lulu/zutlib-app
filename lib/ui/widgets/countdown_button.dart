import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/failure.dart';

/// A button that sends an email (a verification link, an invite) and, when
/// Supabase says "too soon", counts down until it can be pressed again.
/// [onPressed] returns the message to show, or throws a [Failure].
class CountdownButton extends StatefulWidget {
  const CountdownButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.onMessage,
    this.outlined = true,
  });

  final String label;
  final Future<String> Function() onPressed;

  /// Called with what happened, and whether it was an error.
  final void Function(String message, bool isError) onMessage;
  final bool outlined;

  @override
  State<CountdownButton> createState() => _CountdownButtonState();
}

class _CountdownButtonState extends State<CountdownButton> {
  Timer? _timer;
  int _left = 0;
  bool _busy = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startCountdown(int seconds) {
    _timer?.cancel();
    setState(() => _left = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _left -= 1);
      if (_left <= 0) t.cancel();
    });
  }

  Future<void> _press() async {
    setState(() => _busy = true);
    try {
      final message = await widget.onPressed();
      widget.onMessage(message, false);
      // Supabase allows one email to the same address per minute by
      // default, so wait that long before offering again.
      if (mounted) _startCountdown(60);
    } on RateLimited catch (r) {
      widget.onMessage(r.message, true);
      if (mounted) _startCountdown(r.seconds);
    } on Failure catch (f) {
      widget.onMessage(f.message, true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final waiting = _left > 0;
    final text = _busy
        ? 'Sending'
        : waiting
            ? '${widget.label} (wait ${_left}s)'
            : widget.label;
    final onPressed = _busy || waiting ? null : _press;
    return widget.outlined
        ? OutlinedButton(onPressed: onPressed, child: Text(text))
        : FilledButton(onPressed: onPressed, child: Text(text));
  }
}
