import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/failure.dart';
import '../core/supabase.dart';
import '../models/profile.dart';

/// Where the links in account emails send people back to.
///
/// On a phone they reopen the app through the zutlib:// scheme. A browser
/// cannot open that scheme, so on the web the link returns to the address
/// the app is being served from instead. Every one of these must be listed
/// under Supabase -> Authentication -> URL Configuration -> Redirect URLs:
///   zutlib://login-callback
///   zutlib://reset-password
///   http://localhost:5000/**   (flutter run -d chrome --web-port 5000)
String get kResetPasswordRedirect =>
    kIsWeb ? Uri.base.origin : 'zutlib://reset-password';
String get kLoginCallbackRedirect =>
    kIsWeb ? Uri.base.origin : 'zutlib://login-callback';

class AuthRepository {
  const AuthRepository();

  Stream<AuthState> get changes => auth.onAuthStateChange;

  /// Public sign-up. It can only ever make a student account: the database
  /// trigger that creates the profile ignores everything here except the
  /// name and department, and starts the account as pending until an
  /// administrator approves it. Email verification is required before the
  /// person can sign in.
  Future<void> register({
    required String fullName,
    required String department,
    required String email,
    required String password,
  }) async {
    try {
      await auth.signUp(
        email: email.trim(),
        password: password,
        emailRedirectTo: kLoginCallbackRedirect,
        data: {'full_name': fullName.trim(), 'department': department},
      );
    } catch (e) {
      throw Failure.from(e);
    }
  }

  /// Opens the session from an email link: an invite, a password reset or
  /// a sign-up confirmation. The emails point at the app with
  /// ?token_hash=...&type=... (see supabase/templates/).
  Future<void> openEmailLink(String type, String tokenHash) async {
    final otpType = switch (type) {
      'invite' => OtpType.invite,
      'recovery' => OtpType.recovery,
      _ => OtpType.signup,
    };
    try {
      await auth.verifyOTP(type: otpType, tokenHash: tokenHash);
    } catch (e) {
      final f = Failure.from(e);
      final m = f.message.toLowerCase();
      if (m.contains('expired') || m.contains('invalid') || m.contains('not found')) {
        throw Failure(switch (type) {
          'invite' => 'This invite link has expired or was already used. '
              'Ask an administrator to send a new one.',
          'recovery' => 'This password reset link has expired or was already used. '
              'Use "Forgot password?" on the sign-in page to get a new one.',
          _ => 'This confirmation link has expired or was already used. '
              'Try signing in; if your address is not confirmed yet, the app will offer a new link.',
        });
      }
      throw f;
    }
  }

  /// An invited person chooses their password, then the database is told
  /// so the app stops asking.
  Future<void> setFirstPassword(String password) async {
    try {
      await auth.updateUser(UserAttributes(password: password));
    } on AuthException catch (e) {
      // Already this password (for example set through "Forgot password"
      // first): nothing to change, so just finish setting up.
      if (!_isSamePassword(e)) throw Failure.from(e);
    } catch (e) {
      throw Failure.from(e);
    }
    try {
      await db.rpc('mark_password_set');
    } catch (e) {
      throw Failure.from(e);
    }
  }

  static bool _isSamePassword(AuthException e) =>
      e.code == 'same_password' || e.message.toLowerCase().contains('different from the old');

  Future<void> signIn(String email, String password) async {
    try {
      await auth.signInWithPassword(email: email.trim(), password: password);
    } catch (e) {
      throw Failure.from(e);
    }
  }

  Future<void> signOut() => auth.signOut();

  Future<void> resendVerification(String email) async {
    try {
      await auth.resend(
        type: OtpType.signup,
        email: email.trim(),
        emailRedirectTo: kLoginCallbackRedirect,
      );
    } catch (e) {
      throw Failure.from(e);
    }
  }

  Future<void> sendPasswordReset(String email) async {
    try {
      await auth.resetPasswordForEmail(
        email.trim(),
        redirectTo: kResetPasswordRedirect,
      );
    } catch (e) {
      throw Failure.from(e);
    }
  }

  /// Used after the reset link opens the app in recovery mode.
  Future<void> updatePassword(String password) async {
    try {
      await auth.updateUser(UserAttributes(password: password));
    } on AuthException catch (e) {
      // A reset must actually change the password.
      if (_isSamePassword(e)) {
        throw const Failure('Your new password must be different from your old password.');
      }
      throw Failure.from(e);
    } catch (e) {
      throw Failure.from(e);
    }
    try {
      // Choosing a password this way also finishes an unfinished invite, so
      // the app does not ask for a password a second time.
      await db.rpc('mark_password_set');
    } catch (e) {
      throw Failure.from(e);
    }
  }

  Future<Profile?> loadProfile() async {
    final id = currentUserId;
    if (id == null) return null;
    try {
      final row = await db.from('profiles').select().eq('id', id).maybeSingle();
      return row == null ? null : Profile.fromMap(row);
    } catch (e) {
      throw Failure.from(e);
    }
  }
}
