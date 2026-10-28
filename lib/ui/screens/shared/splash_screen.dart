import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/failure.dart';
import '../../../core/supabase.dart';
import '../../../core/theme.dart';
import '../../../state/providers.dart';

/// The gate. It resolves the session and profile once, then hands over.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});
  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  String? _inviteError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _decide());
  }

  Future<void> _decide() async {
    // Opened from an invite email: turn the link into a session first.
    final invite = ref.read(pendingInviteProvider);
    if (invite != null) {
      ref.read(pendingInviteProvider.notifier).state = null;
      try {
        await authRepo.acceptInvite(invite);
        ref.invalidate(profileProvider);
      } on Failure catch (f) {
        // Reloading the page after accepting reuses the old link; if a
        // session already exists, carry on as normal.
        if (auth.currentSession == null) {
          if (mounted) setState(() => _inviteError = f.message);
          return;
        }
      }
    }
    if (auth.currentSession == null) {
      if (mounted) context.go('/login');
      return;
    }
    if (!isVerified) {
      if (mounted) context.go('/verify');
      return;
    }
    final profile = await ref.read(profileProvider.future);
    if (!mounted) return;
    if (profile == null) {
      await auth.signOut();
      if (mounted) context.go('/login');
      return;
    }
    context.go(ref.read(homeRouteProvider));
  }

  @override
  Widget build(BuildContext context) {
    final error = _inviteError;
    if (error != null) {
      return Scaffold(
        backgroundColor: Palette.canvas,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(Insets.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('This invite link did not work',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: Insets.sm),
                  Text(error, style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: Insets.lg),
                  OutlinedButton(
                    onPressed: () => context.go('/login'),
                    child: const Text('Go to sign in'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: Palette.blueDeep,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('ZutLib',
                style: TextStyle(
                  color: Palette.onAccent,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.8,
                )),
            SizedBox(height: Insets.lg),
            SizedBox(
              width: 22, height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.2, color: Palette.onAccent.withValues(alpha: 0.54)),
            ),
          ],
        ),
      ),
    );
  }
}
