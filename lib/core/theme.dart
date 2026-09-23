import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// One set of colours per brightness. Udemy-style layout: bold near-black or
/// white text, one blue accent (often as a gradient) for actions and
/// selection, and a soft highlight yellow for small tags.
class AppColors {
  const AppColors({
    required this.ink,
    required this.inkSoft,
    required this.inkFaint,
    required this.accent,
    required this.accentDeep,
    required this.accentWash,
    required this.onAccent,
    required this.violet,
    required this.teal,
    required this.canvas,
    required this.surface,
    required this.line,
    required this.good,
    required this.goodWash,
    required this.warn,
    required this.warnWash,
    required this.bad,
    required this.badWash,
    required this.neutralWash,
    required this.highlight,
    required this.onHighlight,
  });

  final Color ink, inkSoft, inkFaint;
  final Color accent, accentDeep, accentWash, onAccent;
  final Color violet, teal;
  final Color canvas, surface, line;
  final Color good, goodWash, warn, warnWash, bad, badWash, neutralWash;
  final Color highlight, onHighlight;

  static const light = AppColors(
    ink: Color(0xFF1C1D1F),
    inkSoft: Color(0xFF55607A),
    inkFaint: Color(0xFF8A93A8),
    accent: Color(0xFF2563EB),
    accentDeep: Color(0xFF1E40AF),
    accentWash: Color(0xFFE8F0FE),
    onAccent: Color(0xFFFFFFFF),
    violet: Color(0xFF6366F1),
    teal: Color(0xFF06B6D4),
    canvas: Color(0xFFF8FAFE),
    surface: Color(0xFFFFFFFF),
    line: Color(0xFFDAE1EC),
    good: Color(0xFF0E7C5A),
    goodWash: Color(0xFFE3F5EE),
    warn: Color(0xFF9A5B00),
    warnWash: Color(0xFFFDF0DC),
    bad: Color(0xFFB3261E),
    badWash: Color(0xFFFCE9E7),
    neutralWash: Color(0xFFEFF1F5),
    highlight: Color(0xFFECEB98),
    onHighlight: Color(0xFF3D3C0A),
  );

  static const dark = AppColors(
    ink: Color(0xFFFFFFFF),
    inkSoft: Color(0xFFC3CAD8),
    inkFaint: Color(0xFF8C95A8),
    accent: Color(0xFF6EA8FF),
    accentDeep: Color(0xFF9CC3FF),
    accentWash: Color(0xFF0F1E3A),
    onAccent: Color(0xFF04112B),
    violet: Color(0xFF6366F1),
    teal: Color(0xFF06B6D4),
    canvas: Color(0xFF000000),
    surface: Color(0xFF12151C),
    line: Color(0xFF262C38),
    good: Color(0xFF5DD3A8),
    goodWash: Color(0xFF10302A),
    warn: Color(0xFFF2B35B),
    warnWash: Color(0xFF3A2A12),
    bad: Color(0xFFFF8A80),
    badWash: Color(0xFF3B1714),
    neutralWash: Color(0xFF26262E),
    highlight: Color(0xFFECEB98),
    onHighlight: Color(0xFF3D3C0A),
  );
}

/// The colours for whichever mode is currently showing. main.dart switches
/// this whenever the app's brightness changes and rebuilds every screen, so
/// screens can keep writing `Palette.ink` and get the right colour.
///
/// `blue`, `blueDeep` and `blueWash` are the accent colours.
abstract final class Palette {
  static AppColors _c = AppColors.light;
  static bool get isDark => identical(_c, AppColors.dark);
  static void setBrightness(Brightness b) =>
      _c = b == Brightness.dark ? AppColors.dark : AppColors.light;

  static Color get ink => _c.ink;
  static Color get inkSoft => _c.inkSoft;
  static Color get inkFaint => _c.inkFaint;

  static Color get blue => _c.accent;
  static Color get blueDeep => _c.accentDeep;
  static Color get blueWash => _c.accentWash;
  static Color get onAccent => _c.onAccent;

  static Color get violet => _c.violet;
  static Color get teal => _c.teal;

  static Color get canvas => _c.canvas;
  static Color get surface => _c.surface;
  static Color get line => _c.line;

  static Color get good => _c.good;
  static Color get goodWash => _c.goodWash;
  static Color get warn => _c.warn;
  static Color get warnWash => _c.warnWash;
  static Color get bad => _c.bad;
  static Color get badWash => _c.badWash;
  static Color get neutralWash => _c.neutralWash;

  static Color get highlight => _c.highlight;

  /// The signature blue gradient: buttons, avatar, banner, nav bubble.
  /// Always dark enough for white text on top, in both modes.
  static LinearGradient get accentGradient => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
      );
  static Color get onHighlight => _c.onHighlight;
}

abstract final class Insets {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 40.0;
}

/// Soft, rounded corners to suit the frosted-glass panels.
abstract final class Corners {
  static const card = 20.0;
  static const field = 12.0;
  static const chip = 8.0;
}

/// Breakpoint above which the shell switches from bottom tabs to a side rail.
const double kWideBreakpoint = 900;

/// Extra space at the bottom of scrolling pages so the last item can scroll
/// clear of the floating glass nav bar.
const double kNavClearance = 110;

ThemeData buildTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? AppColors.dark : AppColors.light;
  final isDark = brightness == Brightness.dark;

  final scheme = ColorScheme.fromSeed(
    seedColor: c.accent,
    brightness: brightness,
    primary: c.accent,
    onPrimary: c.onAccent,
    surface: c.surface,
    onSurface: c.ink,
    error: c.bad,
  );

  final base = isDark
      ? ThemeData(brightness: Brightness.dark).textTheme
      : ThemeData(brightness: Brightness.light).textTheme;
  final text = GoogleFonts.interTextTheme(base).apply(
    bodyColor: c.ink,
    displayColor: c.ink,
  );

  OutlineInputBorder border(Color col, {double width = 1}) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(Corners.field),
        borderSide: BorderSide(color: col, width: width),
      );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.canvas,
    textTheme: text.copyWith(
      headlineMedium: text.headlineMedium?.copyWith(
          fontWeight: FontWeight.w800, letterSpacing: -0.4, height: 1.2),
      headlineSmall: text.headlineSmall?.copyWith(
          fontWeight: FontWeight.w800, letterSpacing: -0.3),
      titleLarge: text.titleLarge?.copyWith(
          fontWeight: FontWeight.w800, letterSpacing: -0.2),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      bodyMedium: text.bodyMedium?.copyWith(height: 1.5, color: c.inkSoft),
      bodySmall: text.bodySmall?.copyWith(color: c.inkFaint, height: 1.4),
      labelLarge: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: c.canvas,
      surfaceTintColor: Colors.transparent,
      foregroundColor: c.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      systemOverlayStyle:
          isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      titleTextStyle: text.titleLarge?.copyWith(
          fontWeight: FontWeight.w800, color: c.ink, letterSpacing: -0.2),
    ),
    cardTheme: CardThemeData(
      color: c.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Corners.card),
        side: BorderSide(color: c.line),
      ),
    ),
    dividerTheme: DividerThemeData(color: c.line, space: 1, thickness: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      border: border(c.line),
      enabledBorder: border(c.line),
      focusedBorder: border(c.accent, width: 2),
      errorBorder: border(c.bad),
      focusedErrorBorder: border(c.bad, width: 2),
      labelStyle: TextStyle(color: c.inkSoft),
      hintStyle: TextStyle(color: c.inkFaint),
      floatingLabelStyle: TextStyle(color: c.accent, fontWeight: FontWeight.w700),
      helperStyle: TextStyle(color: c.inkFaint),
      prefixIconColor: c.inkFaint,
      suffixIconColor: c.inkFaint,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        disabledBackgroundColor: Colors.transparent,
        disabledForegroundColor: Colors.white.withValues(alpha: 0.85),
        shadowColor: Colors.transparent,
        // Every filled button gets the blue gradient.
        backgroundBuilder: (context, states, child) => Opacity(
          opacity: states.contains(WidgetState.disabled) ? 0.55 : 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Corners.field),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF2563EB)
                      .withValues(alpha: isDark ? 0.45 : 0.30),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: child,
          ),
        ),
        minimumSize: const Size(0, 50),
        padding: const EdgeInsets.symmetric(horizontal: 22),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Corners.field)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.ink,
        minimumSize: const Size(0, 50),
        padding: const EdgeInsets.symmetric(horizontal: 22),
        side: BorderSide(color: c.ink, width: 1.2),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Corners.field)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.accent,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: c.accent,
      foregroundColor: c.onAccent,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: c.accentWash,
        selectedForegroundColor: c.accentDeep,
        foregroundColor: c.inkSoft,
        side: BorderSide(color: c.line),
      ),
    ),
    chipTheme: ChipThemeData(
      side: BorderSide.none,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Corners.chip)),
      labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: c.surface,
      indicatorColor: c.accentWash,
      selectedIconTheme: IconThemeData(color: c.accentDeep),
      unselectedIconTheme: IconThemeData(color: c.inkFaint),
      selectedLabelTextStyle: text.labelMedium
          ?.copyWith(fontWeight: FontWeight.w600, color: c.accentDeep),
      unselectedLabelTextStyle: text.labelMedium?.copyWith(color: c.inkSoft),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.ink,
      contentTextStyle: TextStyle(color: c.canvas),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Corners.field)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: c.surface,
      surfaceTintColor: Colors.transparent,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: c.inkSoft,
      textColor: c.ink,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: Insets.md, vertical: 4),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: c.accent),
  );
}
