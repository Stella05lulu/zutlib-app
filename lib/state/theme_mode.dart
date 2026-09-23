import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Filled in by main() before the app starts, so the saved mode is applied
/// on the very first frame with no light-to-dark flash.
final sharedPrefsProvider =
    Provider<SharedPreferences>((_) => throw UnimplementedError());

class ThemeModeController extends StateNotifier<ThemeMode> {
  ThemeModeController(this._prefs) : super(_read(_prefs));

  static const _key = 'theme_mode';
  final SharedPreferences _prefs;

  static ThemeMode _read(SharedPreferences p) {
    final saved = p.getString(_key);
    return ThemeMode.values.firstWhere(
      (m) => m.name == saved,
      orElse: () => ThemeMode.system,
    );
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    await _prefs.setString(_key, mode.name);
  }
}

/// system = Automatic (follows the phone), light, or dark.
final themeModeProvider =
    StateNotifierProvider<ThemeModeController, ThemeMode>(
        (ref) => ThemeModeController(ref.watch(sharedPrefsProvider)));
