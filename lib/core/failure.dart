import 'package:supabase_flutter/supabase_flutter.dart';

/// A failure the interface can show a person without leaking internals.
class Failure implements Exception {
  const Failure(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;

  /// Turns anything thrown by the client library into something readable.
  /// Errors explain what happened and what to do; they never apologise and
  /// they are never vague.
  static Failure from(Object error) {
    if (error is Failure) return error;

    if (error is AuthException) {
      final m = error.message.toLowerCase();
      if (m.contains('invalid login')) {
        return const Failure('That email and password do not match an account.');
      }
      if (m.contains('email not confirmed')) {
        return const Failure(
          'Verify your email address first. Check your inbox for the link.',
          code: 'unverified',
        );
      }
      if (m.contains('rate limit') || m.contains('too many')) {
        return const Failure('Too many attempts. Wait a minute and try again.');
      }
      return Failure(error.message);
    }

    if (error is PostgrestException) {
      final code = error.code ?? '';
      if (code == '23505') {
        return const Failure('That already exists.');
      }
      if (code == '23514') {
        return const Failure('The database refused that change because it breaks a rule.');
      }
      if (code == '23503') {
        return const Failure(
            'This is still referenced elsewhere, for example by borrowing '
            'history, so it cannot be removed.');
      }
      // Rules the database explains in its own words (see 0009_hardening).
      if (code == '42501' &&
          (error.message.startsWith('You cannot') ||
              error.message.startsWith('At least one'))) {
        return Failure(error.message);
      }
      if (code == '42501' || code.startsWith('PGRST')) {
        return const Failure('You do not have access to that.');
      }
      return Failure(error.message);
    }

    if (error is FunctionException) {
      final details = error.details;
      if (details is Map && details['message'] is String) {
        return Failure(details['message'] as String,
            code: details['error'] as String?);
      }
      return const Failure('The server could not complete that request.');
    }

    if (error is StorageException) {
      return Failure(error.message);
    }

    return const Failure('Something went wrong. Try again.');
  }
}
