import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/supabase.dart';

/// Keeps the last copy of what a screen loaded, so study kits, the
/// catalogue, borrowing and notifications still open without internet.
///
/// Only raw rows from the database are kept (plain JSON), per signed-in
/// account, and all of it is removed when that person signs out. Writes
/// are never cached: changing anything still needs a connection.
abstract final class OfflineCache {
  static const _prefix = 'zl.cache.';
  static const _maxBytes = 400 * 1024;

  /// True while some screen is showing a saved copy instead of fresh data.
  static final offline = ValueNotifier<bool>(false);

  static String _key(String name) => '$_prefix${currentUserId ?? 'anon'}.$name';

  /// Loads rows with [fetch]. On success the rows are saved under [name];
  /// if the network fails, the saved rows are returned instead (and
  /// [offline] turns on). Any other error is passed on unchanged.
  static Future<List<Map<String, dynamic>>> rows(String name, Future<Object?> Function() fetch) async {
    try {
      final data = await fetch();
      final list = [for (final r in (data as List)) Map<String, dynamic>.from(r as Map)];
      offline.value = false;
      unawaited(_save(name, list));
      return list;
    } catch (e) {
      if (!isNetworkError(e)) rethrow;
      final saved = await _load(name);
      if (saved == null) rethrow;
      offline.value = true;
      return saved;
    }
  }

  /// One saved value (a map) under [name], with the same rules as [rows].
  static Future<Map<String, dynamic>?> single(String name, Future<Object?> Function() fetch) async {
    final list = await rows(name, () async {
      final v = await fetch();
      return v == null ? <Object?>[] : [v];
    });
    return list.isEmpty ? null : list.first;
  }

  /// Errors that mean "no connection", not "the server said no". Checked
  /// by name so the same code works on phones and on the web.
  static bool isNetworkError(Object e) {
    final s = '${e.runtimeType} $e'.toLowerCase();
    return s.contains('socketexception') ||
        s.contains('clientexception') ||
        s.contains('failed host lookup') ||
        s.contains('connection refused') ||
        s.contains('connection closed') ||
        s.contains('network is unreachable') ||
        s.contains('xmlhttprequest error') ||
        s.contains('failed to fetch') ||
        s.contains('timeoutexception');
  }

  static Future<void> _save(String name, List<Map<String, dynamic>> list) async {
    try {
      final text = jsonEncode(list);
      if (text.length > _maxBytes) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key(name), text);
    } catch (_) {
      // A full or blocked store only means no offline copy.
    }
  }

  static Future<List<Map<String, dynamic>>?> _load(String name) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final text = prefs.getString(_key(name));
      if (text == null) return null;
      return [for (final r in jsonDecode(text) as List) Map<String, dynamic>.from(r as Map)];
    } catch (_) {
      return null;
    }
  }

  /// Removes every saved copy (on sign-out), for every account.
  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final k in prefs.getKeys().where((k) => k.startsWith(_prefix)).toList()) {
        await prefs.remove(k);
      }
      offline.value = false;
    } catch (_) {
      // Nothing to clear.
    }
  }
}
