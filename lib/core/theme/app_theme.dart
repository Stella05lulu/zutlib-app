import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The study assistant's look, in one file.
///
/// The rest of ZutLib keeps its own theme (lib/core/theme.dart). The study
/// screens wrap themselves in [StudyScope], which swaps in the theme built
/// here, so this module can follow its own visual rules without changing
/// any existing screen:
///
///   - IBM Plex Sans for text, IBM Plex Mono for machine values
///     (counts, scores, dates, the requests left today)
///   - grey for structure, light blue used sparingly (AI labels, the
///     correct answer, the back of a flashcard), and one accent colour,
///     burnt orange, for the main action on a screen and for errors
///   - flat: no gradients, no shadows, no pure white or pure black
///
/// Every colour the study screens use is defined below and nowhere else.
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

  /// The single accent: the main action, the selected tab, errors.
  final Color accent, onAccent, accentWash;

  static const light = StudyColors(
    canvas: Color(0xFFF2F3F5),
    surface: Color(0xFFFAFAFB),
    sunken: Color(0xFFE6E8EC),
    line: Color(0xFFD8DBE1),
    lineStrong: Color(0xFFA9AFB9),
    ink: Color(0xFF1C2027),
    inkSoft: Color(0xFF4B5361),
    inkFaint: Color(0xFF7A8290),
    sky: Color(0xFF2D6A9F),
    skyWash: Color(0xFFDCEAF6),
    accent: Color(0xFFB4501A),
    onAccent: Color(0xFFFBF7F4),
    accentWash: Color(0xFFF6E6DC),
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
    sky: Color(0xFF9CC5EA),
    skyWash: Color(0xFF1E3245),
    accent: Color(0xFFE38A52),
    onAccent: Color(0xFF231308),
    accentWash: Color(0xFF3A2416),
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
    );
  }
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
      error: c.accent,
      onError: c.onAccent,
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
    final text = plex.copyWith(
      headlineSmall: plex.headlineSmall?.copyWith(fontWeight: FontWeight.w600, fontSize: 24, height: 1.25),
      titleLarge: plex.titleLarge?.copyWith(fontWeight: FontWeight.w600, fontSize: 20, height: 1.3),
      titleMedium: plex.titleMedium?.copyWith(fontWeight: FontWeight.w600, fontSize: 16, height: 1.35),
      titleSmall: plex.titleSmall?.copyWith(fontWeight: FontWeight.w600, fontSize: 14, color: c.inkSoft),
      bodyLarge: plex.bodyLarge?.copyWith(fontSize: 16, height: 1.55),
      bodyMedium: plex.bodyMedium?.copyWith(fontSize: 14.5, height: 1.5, color: c.inkSoft),
      bodySmall: plex.bodySmall?.copyWith(fontSize: 12.5, height: 1.4, color: c.inkFaint),
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
        titleTextStyle: text.titleMedium,
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
        errorBorder: border(c.accent),
        focusedErrorBorder: border(c.accent, 1.5),
        labelStyle: TextStyle(color: c.inkSoft),
        floatingLabelStyle: TextStyle(color: c.sky),
        hintStyle: TextStyle(color: c.inkFaint),
        helperStyle: TextStyle(color: c.inkFaint),
        errorStyle: TextStyle(color: c.accent),
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

/// Puts the study theme around a study screen, following whatever
/// brightness the app is showing (light, dark or automatic).
class StudyScope extends StatelessWidget {
  const StudyScope({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Theme(data: StudyTheme.build(brightness), child: child);
  }
}
