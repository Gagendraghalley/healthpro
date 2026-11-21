import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro_core/health_pro_core.dart';
import 'package:health_pro_core/src/auth/sign_in_return.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('An unfinished sign-in says why', () {
    const off = 'This account is turned off. Ask your gym or the Health Pro team to turn it on again.';

    test('an account that is turned off, by email + code', () {
      expect(friendlyError(const AuthException('User is banned', statusCode: '400', code: 'user_banned')), off);
    });

    test('an account that is turned off, back from Google (query, fragment or both)', () {
      expect(
          signInErrorIn(Uri.parse('https://sporthubs.pages.dev/?error=access_denied&error_code=user_banned'
              '&error_description=User+is+banned#/sign-in?next=%2Fgyms%2F1')),
          off);
      expect(
          signInErrorIn(Uri.parse(
              'https://sporthubs.pages.dev/#error=access_denied&error_code=user_banned&error_description=User+is+banned')),
          off);
    });

    test('cancelled at Google, or nothing wrong', () {
      expect(signInErrorIn(Uri.parse('http://localhost:3000/?error=access_denied#/sign-in')),
          'Signing in with Google was cancelled.');
      expect(signInErrorIn(Uri.parse('https://sporthubs.pages.dev/#/sign-in?next=%2Fgyms%2F1')), isNull);
      expect(signInErrorIn(Uri.parse('https://sporthubs.pages.dev/?code=abc#/welcome')), isNull);
    });

    test('the error leaves the address; the page stays, or becomes sign-in', () {
      expect(
          withoutSignInError(Uri.parse('https://sporthubs.pages.dev/?error=access_denied&error_code=user_banned'
              '&error_description=User+is+banned#/sign-in?next=%2Fgyms%2F1')),
          'https://sporthubs.pages.dev/#/sign-in?next=%2Fgyms%2F1');
      expect(
          withoutSignInError(Uri.parse('http://localhost:3000/#error=access_denied&error_description=User+is+banned')),
          'http://localhost:3000/#/sign-in');
    });
  });

  group('Coming back from Google', () {
    test('returns to the sign-in page of the same site, after the #', () {
      expect(webReturnUrl(Uri.parse('https://sporthubs.pages.dev/#/sign-in'), CoreRoutes.signIn),
          'https://sporthubs.pages.dev/#/sign-in');
      expect(webReturnUrl(Uri.parse('http://localhost:3000/#/sign-up?next=%2Fgyms%2F1'), CoreRoutes.signInFor('/gyms/1')),
          'http://localhost:3000/#/sign-in?next=%2Fgyms%2F1');
    });

    test('drops an old code or error in the address', () {
      expect(webReturnUrl(Uri.parse('https://sporthubs.pages.dev/?code=abc#error=access_denied'), CoreRoutes.signIn),
          'https://sporthubs.pages.dev/#/sign-in');
    });

    test('the sign-in page then sends them on to where they were going', () {
      final back = Uri.parse(webReturnUrl(Uri.parse('https://sporthubs.pages.dev/'), CoreRoutes.signInFor('/gyms/1')));
      final page = Uri.parse(back.fragment);
      expect(
        guardRoute(uri: page, pattern: page.path, signedIn: true, publicPatterns: CoreRoutes.publicPaths),
        '/gyms/1',
      );
    });
  });
}
