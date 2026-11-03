import 'package:flutter/material.dart';

import 'theme/app_theme.dart';

/// The older colour names used by the library, borrowing, staff and admin
/// screens. Since version 2 they are the same colours as the study screens
/// (lib/core/theme/app_theme.dart), so the whole app has one flat look:
/// IBM Plex, grey structure, one blue accent, and red, green and amber only
/// where they carry meaning. No gradients, glass, glows or shadows.
class AppColors {
  const AppColors({
    required this.ink,
    required this.inkSoft,
    required this.inkFaint,
    required this.accent,
    required this.accentDeep,
    required this.accentWash,
    required this.onAccent,
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
  final Color canvas, surface, line;
  final Color good, goodWash, warn, warnWash, bad, badWash, neutralWash;
  final Color highlight, onHighlight;

  static AppColors _from(StudyColors c, {required Color accentDeep}) => AppColors(
        ink: c.ink,
        inkSoft: c.inkSoft,
        inkFaint: c.inkFaint,
        accent: c.accent,
        accentDeep: accentDeep,
        accentWash: c.accentWash,
        onAccent: c.onAccent,
        canvas: c.canvas,
        surface: c.surface,
        line: c.line,
        good: c.success,
        goodWash: c.successWash,
        warn: c.warn,
        warnWash: c.warnWash,
        bad: c.danger,
        badWash: c.dangerWash,
        neutralWash: c.sunken,
        highlight: c.warnWash,
        onHighlight: c.warn,
      );

  static final light = _from(StudyColors.light, accentDeep: const Color(0xFF174E9F));
  static final dark = _from(StudyColors.dark, accentDeep: const Color(0xFFB2CEF7));
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
  static Color get onHighlight => _c.onHighlight;
}

/// Spacing on a 4-point scale. The study screens use the finer [Gap] steps
/// from app_theme.dart; both scales share the same base.
abstract final class Insets {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 40.0;
}

/// Corner radii, matching [Radii] so every panel, field and tag in the app
/// has the same small, flat corners.
abstract final class Corners {
  static const card = Radii.panel;
  static const field = Radii.control;
  static const chip = Radii.tag;
}

/// Breakpoint above which the shell switches from bottom tabs to a side rail.
const double kWideBreakpoint = 900;

/// Space at the bottom of scrolling pages, so the last item never sits
/// against the bottom navigation bar.
const double kNavClearance = 32;

/// The app's theme: the one built in app_theme.dart, for either brightness.
ThemeData buildTheme(Brightness brightness) => StudyTheme.build(brightness);
