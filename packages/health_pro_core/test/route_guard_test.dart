import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro_core/health_pro_core.dart';

void main() {
  const public = {...CoreRoutes.publicPaths, '/gyms', '/gyms/:id'};

  String? guard(String location,
          {String? pattern, bool signedIn = false, String? moduleKey, Set<String>? enabled}) =>
      guardRoute(
        uri: Uri.parse(location),
        pattern: pattern ?? Uri.parse(location).path,
        signedIn: signedIn,
        publicPatterns: public,
        moduleKey: moduleKey,
        enabledModuleKeys: enabled,
      );

  test('the starting code is changed before anything else opens', () {
    String? forced(String location) => guardRoute(
        uri: Uri.parse(location), pattern: location, signedIn: true, publicPatterns: public, mustChooseCode: true);
    expect(forced('/'), CoreRoutes.setCode);
    expect(forced(CoreRoutes.home), CoreRoutes.setCode);
    expect(forced(CoreRoutes.signIn), CoreRoutes.setCode);
    expect(forced(CoreRoutes.setCode), isNull);
  });

  test('/ goes home when signed in, to Welcome otherwise', () {
    expect(guard('/', signedIn: true), CoreRoutes.home);
    expect(guard('/'), CoreRoutes.welcome);
  });

  test('visitors open public pages, including ones with ids', () {
    expect(guard('/gyms'), isNull);
    expect(guard('/gyms/abc', pattern: '/gyms/:id'), isNull);
    expect(guard(CoreRoutes.registerVenue), isNull);
  });

  test('visitors sign in first for everything else, then come back', () {
    expect(guard('/my-gym'), '/sign-in?next=%2Fmy-gym');
    expect(guard('/gyms/abc/manage/plans', pattern: '/gyms/:id/manage/plans'),
        CoreRoutes.signInFor('/gyms/abc/manage/plans'));
  });

  test('signing out on a private page goes to Welcome, not back to it after the next sign-in', () {
    String? out(String location, String pattern) => guardRoute(
        uri: Uri.parse(location), pattern: pattern, signedIn: false, publicPatterns: public, justSignedOut: true);
    expect(out('/gyms/abc/manage/reports', '/gyms/:id/manage/reports'), CoreRoutes.welcome);
    expect(out('/gyms/abc', '/gyms/:id'), isNull, reason: 'public pages stay open');
  });

  test('signed-in users skip the sign-in pages, to ?next= when it is ours', () {
    expect(guard('/sign-in', signedIn: true), CoreRoutes.home);
    expect(guard('/sign-in?next=%2Fmy-gym', pattern: '/sign-in', signedIn: true), '/my-gym');
    expect(guard('/sign-in?next=https%3A%2F%2Fevil.example', pattern: '/sign-in', signedIn: true), CoreRoutes.home);
    expect(guard('/verify', signedIn: true), isNull, reason: 'the code page sends them on itself');
  });

  test("a module's pages close while it is turned off", () {
    expect(guard('/gyms', moduleKey: 'gym_membership', enabled: {'coaching'}), CoreRoutes.welcome);
    expect(guard('/my-gym', signedIn: true, moduleKey: 'gym_membership', enabled: {'coaching'}), CoreRoutes.home);
    expect(guard('/gyms', moduleKey: 'gym_membership', enabled: {'gym_membership'}), isNull);
    expect(guard('/gyms', moduleKey: 'gym_membership'), isNull, reason: 'not known yet: let them in');
  });

  test('safeNext keeps only pages of this app', () {
    expect(safeNext('/gyms/1'), '/gyms/1');
    expect(safeNext('//evil.example'), isNull);
    expect(safeNext('https://evil.example'), isNull);
    expect(safeNext(null), isNull);
  });

  test('an expired email link in the address is not a page', () {
    expect(
      hasNonPageFragment(Uri.parse(
          'http://localhost:8080/?error=access_denied#error=access_denied&error_code=otp_expired&error_description=Email+link+is+invalid+or+has+expired')),
      isTrue,
    );
    expect(hasNonPageFragment(Uri.parse('http://localhost:8080/#/welcome')), isFalse);
    expect(hasNonPageFragment(Uri.parse('http://localhost:8080/')), isFalse);
  });
}
