import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/env.dart';
import 'core/router.dart';
import 'core/theme.dart';
import 'state/theme_mode.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  await Supabase.initialize(
    url: Env.supabaseUrl,
    anonKey: Env.supabaseAnonKey,
  );
  final prefs = await SharedPreferences.getInstance();
  runApp(ProviderScope(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    child: const ZutLibApp(),
  ));
}

class ZutLibApp extends ConsumerWidget {
  const ZutLibApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'ZutLib',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ref.watch(themeModeProvider),
      themeAnimationDuration: Duration.zero,
      routerConfig: router,
      builder: (context, child) =>
          _PaletteScope(child: child ?? const SizedBox.shrink()),
    );
  }
}

/// Screens read Palette colours directly. When the brightness flips (from
/// the setting, or from the phone in Automatic mode) this switches the
/// palette and asks every widget below to redraw in place. Nothing is
/// rebuilt from scratch, so typed text, scroll position and open pages
/// all stay as they were.
class _PaletteScope extends StatefulWidget {
  const _PaletteScope({required this.child});
  final Widget child;

  @override
  State<_PaletteScope> createState() => _PaletteScopeState();
}

class _PaletteScopeState extends State<_PaletteScope> {
  Brightness? _last;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    Palette.setBrightness(brightness);
    if (_last != null && _last != brightness) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        void redraw(Element e) {
          e.markNeedsBuild();
          e.visitChildren(redraw);
        }
        (context as Element).visitChildren(redraw);
      });
    }
    _last = brightness;
    return widget.child;
  }
}
