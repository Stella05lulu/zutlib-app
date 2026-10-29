// How the app reads the links in ZutLib's emails (supabase/templates/).
//
//   flutter test
import 'package:flutter_test/flutter_test.dart';

import 'package:zutlib/state/providers.dart';

void main() {
  EmailLink? read(String url) => EmailLink.fromUri(Uri.parse(url));

  test('an invite link is read', () {
    final l = read('http://localhost:5000/?token_hash=abc123&type=invite');
    expect(l?.type, 'invite');
    expect(l?.tokenHash, 'abc123');
  });

  test('a password reset link is read', () {
    expect(read('http://localhost:5000/?token_hash=abc&type=recovery')?.type, 'recovery');
  });

  test('a sign-up confirmation link is read', () {
    expect(read('http://localhost:5000/?token_hash=abc&type=signup')?.type, 'signup');
  });

  test('the hash route after the link does not matter', () {
    expect(read('http://localhost:5000/?token_hash=abc&type=invite#/login')?.tokenHash, 'abc');
  });

  test('an expired link reported by Supabase becomes a failed link', () {
    final l = read('http://localhost:5000/?error=access_denied&error_code=otp_expired'
        '&error_description=Email+link+is+invalid+or+has+expired#/login');
    expect(l?.type, EmailLink.failed);
    expect(l?.tokenHash, 'otp_expired');
  });

  test('anything else is ignored', () {
    expect(read('http://localhost:5000/'), isNull);
    expect(read('http://localhost:5000/?type=invite'), isNull);
    expect(read('http://localhost:5000/?token_hash=abc&type=magiclink'), isNull);
    expect(read('http://localhost:5000/?code=d87a2794'), isNull);
  });
}
