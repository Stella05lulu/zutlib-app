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
    // Opened from an email link: turn it into a session first.
    final link = ref.read(pendingEmailLinkProvider);
    if (link != null && link.type == EmailLink.failed) {
      ref.read(pendingEmailLinkProvider.notifier).state = null;
      if (auth.currentSession == null) {
        if (mounted) {
          setState(() => _inviteError = link.tokenHash.contains('expired')
              ? 'This email link has expired or was already used. Each link works once. '
                  'Ask for a new one: "Forgot password?" for a password reset, or an '
                  'administrator for an invite.'
              : 'This email link could not be used. Ask for a new one and open it once.');
        }
        return;
      }
    } else if (link != null) {
      ref.read(pendingEmailLinkProvider.notifier).state = null;
      try {
        await authRepo.openEmailLink(link.type, link.tokenHash);
        if (link.type == 'recovery') {
          // Signed in for one purpose only: choosing a new password.
          ref.read(passwordRecoveryProvider.notifier).state = true;
        }
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
                  Text('This link did not work',
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
