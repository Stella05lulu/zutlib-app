import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Configuration read once at startup. Nothing secret lives here: the anon
/// key is designed to be public, and every rule that protects data is
/// enforced by row level security in the database, not by this client.
class Env {
  const Env._();

  static String get supabaseUrl => _require('SUPABASE_URL');
  static String get supabaseAnonKey => _require('SUPABASE_ANON_KEY');

  static String _require(String key) {
    final value = dotenv.env[key];
    if (value == null || value.isEmpty) {
      throw StateError(
        'Missing $key. Copy .env.example to .env and fill it in.',
      );
    }
    return value;
  }
}
