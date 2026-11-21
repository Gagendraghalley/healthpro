import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro_core/health_pro_core.dart';

void main() {
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
