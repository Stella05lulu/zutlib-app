import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _decide());
  }

  Future<void> _decide() async {
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
