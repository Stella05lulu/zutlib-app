import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// ZutLib's look, in one file.
///
/// Every screen uses the theme built here: main.dart installs it through
/// lib/core/theme.dart, and the older `Palette` names there map onto these
/// colours. [StudyScope] is kept so screens that wrap themselves in it keep
/// working; it now hands back the same theme. The rules:
///
///   - IBM Plex Sans for text, IBM Plex Mono for machine values
///     (counts, scores, dates, the requests left today)
///   - grey for structure; one accent, a confident blue, for the main
///     action, the selected tab and progress; teal (`sky`) for AI labels
///     and information; and three signal colours used only for meaning:
///     green for right and "got it", yellow for "not sure", red for wrong,
///     "again" and errors
///   - study kits get a solid colour each from [KitPalette], like course
///     tiles in an online-learning catalogue
///   - flat: no gradients, no shadows, no pure white or pure black, and no
///     purple anywhere
///
/// Every colour the app uses is defined below and nowhere else.
@immutable
class StudyColors extends ThemeExtension<StudyColors> {
  const StudyColors({
    required this.canvas,
    required this.surface,
    required this.sunken,
    required this.line,
    required this.lineStrong,
    required this.ink,
    required this.inkSoft,
    required this.inkFaint,
    required this.sky,
    required this.skyWash,
    required this.accent,
    required this.onAccent,
    required this.accentWash,
    required this.danger,
    required this.dangerWash,
    required this.success,
    required this.successWash,
    required this.warn,
    required this.warnWash,
  });

  /// Page background.
  final Color canvas;

  /// Panels and rows sitting on the page.
  final Color surface;

  /// Recessed areas: inputs, skeleton blocks, progress tracks.
  final Color sunken;

  /// Hairlines between rows and around panels.
  final Color line;

  /// Borders that must be noticed, such as an unselected option.
  final Color lineStrong;

  /// Main text, secondary text, and hints.
  final Color ink, inkSoft, inkFaint;

  /// The light blue: text or icons in [sky], fills in [skyWash].
  final Color sky, skyWash;

  /// The accent: the main action, the selected tab, progress.
  final Color accent, onAccent, accentWash;

  /// Signals: wrong and errors, right, not sure.
  final Color danger, dangerWash, success, successWash, warn, warnWash;

  static const light = StudyColors(
    canvas: Color(0xFFF2F3F5),
    surface: Color(0xFFFAFAFB),
    sunken: Color(0xFFE6E8EC),
    line: Color(0xFFD8DBE1),
    lineStrong: Color(0xFFA9AFB9),
    ink: Color(0xFF1C2027),
    inkSoft: Color(0xFF4B5361),
    inkFaint: Color(0xFF7A8290),
    sky: Color(0xFF1F6F78),
    skyWash: Color(0xFFDDEFF1),
    accent: Color(0xFF1D5FC4),
    onAccent: Color(0xFFF6F9FD),
    accentWash: Color(0xFFE1EBF9),
    danger: Color(0xFFB3361F),
    dangerWash: Color(0xFFF8E4DF),
    success: Color(0xFF237A47),
    successWash: Color(0xFFDFF1E6),
    warn: Color(0xFF8F5B00),
    warnWash: Color(0xFFFAEFD7),
  );

  static const dark = StudyColors(
    canvas: Color(0xFF16181C),
    surface: Color(0xFF1D2025),
    sunken: Color(0xFF262A30),
    line: Color(0xFF30353C),
    lineStrong: Color(0xFF555C67),
    ink: Color(0xFFE6E8EB),
    inkSoft: Color(0xFFAAB1BC),
    inkFaint: Color(0xFF7D8592),
    sky: Color(0xFF8ED2DA),
    skyWash: Color(0xFF173539),
    accent: Color(0xFF86B3F4),
    onAccent: Color(0xFF0D1A2E),
    accentWash: Color(0xFF1B2B44),
    danger: Color(0xFFF2937F),
    dangerWash: Color(0xFF3B201A),
    success: Color(0xFF84D2A2),
    successWash: Color(0xFF16321F),
    warn: Color(0xFFEFC46A),
    warnWash: Color(0xFF3A2E12),
  );

  /// The colours for the current brightness.
  static StudyColors of(BuildContext context) =>
      Theme.of(context).extension<StudyColors>() ??
      (Theme.of(context).brightness == Brightness.dark ? dark : light);

  @override
  StudyColors copyWith({
    Color? canvas,
    Color? surface,
    Color? sunken,
    Color? line,
    Color? lineStrong,
    Color? ink,
    Color? inkSoft,
    Color? inkFaint,
    Color? sky,
    Color? skyWash,
    Color? accent,
    Color? onAccent,
    Color? accentWash,
    Color? danger,
    Color? dangerWash,
    Color? success,
    Color? successWash,
    Color? warn,
    Color? warnWash,
  }) =>
      StudyColors(
        canvas: canvas ?? this.canvas,
        surface: surface ?? this.surface,
        sunken: sunken ?? this.sunken,
        line: line ?? this.line,
        lineStrong: lineStrong ?? this.lineStrong,
        ink: ink ?? this.ink,
        inkSoft: inkSoft ?? this.inkSoft,
        inkFaint: inkFaint ?? this.inkFaint,
        sky: sky ?? this.sky,
        skyWash: skyWash ?? this.skyWash,
        accent: accent ?? this.accent,
        onAccent: onAccent ?? this.onAccent,
        accentWash: accentWash ?? this.accentWash,
        danger: danger ?? this.danger,
        dangerWash: dangerWash ?? this.dangerWash,
        success: success ?? this.success,
        successWash: successWash ?? this.successWash,
        warn: warn ?? this.warn,
        warnWash: warnWash ?? this.warnWash,
      );

  @override
  StudyColors lerp(ThemeExtension<StudyColors>? other, double t) {
    if (other is! StudyColors) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t) ?? a;
    return StudyColors(
      canvas: mix(canvas, other.canvas),
      surface: mix(surface, other.surface),
      sunken: mix(sunken, other.sunken),
      line: mix(line, other.line),
      lineStrong: mix(lineStrong, other.lineStrong),
      ink: mix(ink, other.ink),
      inkSoft: mix(inkSoft, other.inkSoft),
      inkFaint: mix(inkFaint, other.inkFaint),
      sky: mix(sky, other.sky),
      skyWash: mix(skyWash, other.skyWash),
      accent: mix(accent, other.accent),
      onAccent: mix(onAccent, other.onAccent),
      accentWash: mix(accentWash, other.accentWash),
      danger: mix(danger, other.danger),
      dangerWash: mix(dangerWash, other.dangerWash),
      success: mix(success, other.success),
      successWash: mix(successWash, other.successWash),
      warn: mix(warn, other.warn),
      warnWash: mix(warnWash, other.warnWash),
    );
  }
}

/// The solid colour of each study kit's tile, and the text colour that
/// reads on it. The same in light and dark mode, like printed book covers.
abstract final class KitPalette {
  static Color fill(String key) => switch (key) {
        'red' => const Color(0xFFD5402F),
        'yellow' => const Color(0xFFF2B11B),
        'green' => const Color(0xFF26935A),
        'orange' => const Color(0xFFE8702A),
        'teal' => const Color(0xFF158E95),
        'slate' => const Color(0xFF475467),
        _ => const Color(0xFF2563D6),
      };

  static Color onFill(String key) => key == 'yellow' ? const Color(0xFF1C2027) : const Color(0xFFFBFCFD);
}

/// Spacing steps. Screens pick the step that suits the gap (a tight label
/// gap, a row's inner padding, the space between sections) instead of
/// using one number for everything.
abstract final class Gap {
  static const double hair = 4;
  static const double tight = 8;
  static const double snug = 12;
  static const double row = 14;
  static const double page = 20;
  static const double section = 28;
  static const double wide = 40;
}

/// Corner radii: small and consistent, so panels read as flat paper.
abstract final class Radii {
  static const double panel = 10;
  static const double control = 8;
  static const double tag = 4;
}

/// Text styles for machine values: counts, scores, dates, limits.
abstract final class Mono {
  static TextStyle of(BuildContext context,
      {double size = 13, FontWeight weight = FontWeight.w500, Color? color}) {
    return GoogleFonts.ibmPlexMono(
      fontSize: size,
      fontWeight: weight,
      color: color ?? StudyColors.of(context).inkSoft,
      letterSpacing: 0,
    );
  }
}

abstract final class StudyTheme {
  // Built once per brightness, then reused.
  static final _built = <Brightness, ThemeData>{};

  static ThemeData build(Brightness brightness) =>
      _built[brightness] ??= _make(brightness);

  static ThemeData _make(Brightness brightness) {
    final c = brightness == Brightness.dark ? StudyColors.dark : StudyColors.light;

    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.accent,
      onPrimary: c.onAccent,
      secondary: c.sky,
      onSecondary: c.surface,
      error: c.danger,
      onError: c.surface,
      surface: c.surface,
      onSurface: c.ink,
      surfaceTint: c.surface,
      outline: c.line,
      outlineVariant: c.line,
    );

    final base = ThemeData(brightness: brightness, useMaterial3: true).textTheme;
    final plex = GoogleFonts.ibmPlexSansTextTheme(base).apply(
      bodyColor: c.ink,
      displayColor: c.ink,
    );
    // Type scale: display 28, title 22, section 18, body 15, caption 13.
    // Screen titles and section headings use IBM Plex Serif (semibold),
    // which pairs with Plex Sans for reading and Plex Mono for numbers.
    TextStyle serif(double size, double height) =>
        GoogleFonts.ibmPlexSerif(fontSize: size, height: height, fontWeight: FontWeight.w600, color: c.ink);
    final text = plex.copyWith(
      displaySmall: serif(28, 1.2),
      headlineSmall: serif(22, 1.25),
      titleLarge: serif(18, 1.3),
      titleMedium: plex.titleMedium?.copyWith(fontWeight: FontWeight.w600, fontSize: 16, height: 1.35),
      titleSmall: plex.titleSmall?.copyWith(fontWeight: FontWeight.w600, fontSize: 14, color: c.inkSoft),
      bodyLarge: plex.bodyLarge?.copyWith(fontSize: 16, height: 1.55),
      bodyMedium: plex.bodyMedium?.copyWith(fontSize: 15, height: 1.5, color: c.inkSoft),
      bodySmall: plex.bodySmall?.copyWith(fontSize: 13, height: 1.4, color: c.inkFaint),
      labelLarge: plex.labelLarge?.copyWith(fontWeight: FontWeight.w600, fontSize: 14.5),
    );

    OutlineInputBorder border(Color col, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.control),
          borderSide: BorderSide(color: col, width: w),
        );

    final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.control));

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      extensions: [c],
      scaffoldBackgroundColor: c.canvas,
      canvasColor: c.canvas,
      textTheme: text,
      splashFactory: InkRipple.splashFactory,
      dividerTheme: DividerThemeData(color: c.line, thickness: 1, space: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: c.canvas,
        foregroundColor: c.ink,
        surfaceTintColor: c.canvas,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: c.surface,
        elevation: 0,
        shadowColor: c.canvas,
        surfaceTintColor: c.surface,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.panel),
          side: BorderSide(color: c.line),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: Gap.snug, vertical: Gap.row),
        border: border(c.line),
        enabledBorder: border(c.line),
        focusedBorder: border(c.sky, 1.5),
        errorBorder: border(c.danger),
        focusedErrorBorder: border(c.danger, 1.5),
        labelStyle: TextStyle(color: c.inkSoft),
        floatingLabelStyle: TextStyle(color: c.sky),
        hintStyle: TextStyle(color: c.inkFaint),
        helperStyle: TextStyle(color: c.inkFaint),
        errorStyle: TextStyle(color: c.danger),
        counterStyle: GoogleFonts.ibmPlexMono(fontSize: 11.5, color: c.inkFaint),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.accent,
          foregroundColor: c.onAccent,
          disabledBackgroundColor: c.sunken,
          disabledForegroundColor: c.inkFaint,
          elevation: 0,
          shadowColor: c.canvas,
          minimumSize: const Size(0, 46),
          padding: const EdgeInsets.symmetric(horizontal: Gap.page),
          shape: buttonShape,
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.ink,
          disabledForegroundColor: c.inkFaint,
          side: BorderSide(color: c.lineStrong),
          elevation: 0,
          minimumSize: const Size(0, 46),
          padding: const EdgeInsets.symmetric(horizontal: Gap.page - 2),
          shape: buttonShape,
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.ink,
          padding: const EdgeInsets.symmetric(horizontal: Gap.snug),
          shape: buttonShape,
          textStyle: text.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: c.inkSoft),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: buttonShape,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: c.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.panel),
          side: BorderSide(color: c.line),
        ),
        titleTextStyle: text.titleMedium,
        contentTextStyle: text.bodyMedium,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: c.surface,
        elevation: 0,
        modalElevation: 0,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.surface,
        surfaceTintColor: c.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.control),
          side: BorderSide(color: c.line),
        ),
        textStyle: text.bodyMedium?.copyWith(color: c.ink),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.sky,
        linearTrackColor: c.sunken,
      ),
      checkboxTheme: CheckboxThemeData(
        side: BorderSide(color: c.lineStrong, width: 1.5),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: c.surface,
        elevation: 0,
        height: 66,
        indicatorColor: c.accentWash,
        indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.panel + 6)),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              size: 24,
              color: states.contains(WidgetState.selected) ? c.accent : c.inkSoft,
            )),
        labelTextStyle: WidgetStateProperty.resolveWith((states) => text.labelSmall?.copyWith(
              fontSize: 12,
              fontWeight: states.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
              color: states.contains(WidgetState.selected) ? c.ink : c.inkSoft,
            )),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: c.surface,
        elevation: 0,
        indicatorColor: c.accentWash,
        selectedIconTheme: IconThemeData(color: c.accent),
        unselectedIconTheme: IconThemeData(color: c.inkSoft),
        selectedLabelTextStyle: text.labelLarge?.copyWith(color: c.ink),
        unselectedLabelTextStyle: text.labelLarge?.copyWith(color: c.inkSoft, fontWeight: FontWeight.w500),
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: c.danger,
        textColor: c.surface,
        textStyle: GoogleFonts.ibmPlexMono(fontSize: 10.5, fontWeight: FontWeight.w600),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: c.accentWash,
          selectedForegroundColor: c.ink,
          foregroundColor: c.inkSoft,
          side: BorderSide(color: c.line),
          shape: buttonShape,
          textStyle: text.labelLarge,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.surface,
        selectedColor: c.accentWash,
        side: BorderSide(color: c.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.control)),
        labelStyle: text.labelLarge?.copyWith(fontSize: 13.5, color: c.ink),
        elevation: 0,
        pressElevation: 0,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.ink,
        contentTextStyle: text.bodyMedium?.copyWith(color: c.canvas),
        actionTextColor: c.canvas,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.control)),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: c.inkSoft,
        textColor: c.ink,
        contentPadding: const EdgeInsets.symmetric(horizontal: Gap.page - 4, vertical: Gap.hair),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? c.onAccent : c.lineStrong),
        trackColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? c.accent : c.sunken),
        trackOutlineColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? c.accent : c.lineStrong),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: c.accent,
        selectionColor: c.accentWash,
        selectionHandleColor: c.accent,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: c.ink,
          borderRadius: BorderRadius.circular(Radii.tag),
        ),
        textStyle: text.bodySmall?.copyWith(color: c.canvas),
      ),
    );
  }
}

/// Puts the ZutLib theme around a screen, following whatever brightness the
/// app is showing (light, dark or automatic). Since the whole app now uses
/// this theme, it changes nothing; it stays so existing screens keep
/// building.
class StudyScope extends StatelessWidget {
  const StudyScope({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Theme(data: StudyTheme.build(brightness), child: child);
  }
}
