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

  /// Registration does not call signUp. Eligibility has to be established
  /// against the institutional roll first, and the roll is not readable by
  /// any client, so the check happens inside an edge function.
  Future<String> register({
    required String studentNumber,
    required String surname,
    required String email,
    required String password,
  }) async {
    try {
      final res = await db.functions.invoke('register', body: {
        'student_number': studentNumber,
        'surname': surname,
        'email': email,
        'password': password,
        'redirect_to': kLoginCallbackRedirect,
      });
      final data = res.data;
      if (data is Map && data['message'] is String) {
        return data['message'] as String;
      }
      return 'Account created. Check your email to verify the address.';
    } catch (e) {
      throw Failure.from(e);
    }
  }

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
