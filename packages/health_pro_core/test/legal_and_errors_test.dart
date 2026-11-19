import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro_core/health_pro_core.dart';
import 'package:health_pro_core/src/admin/app_errors_screen.dart';
import 'package:health_pro_core/src/legal/legal_pages.dart';

const phone = Size(360, 780);
const laptop = Size(1280, 800);

Future<void> show(WidgetTester tester, Widget page, Size size, {List<Override> overrides = const []}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(overrides: overrides, child: MaterialApp(home: page)));
  await tester.pumpAndSettle();
}

final errors = [
  AppError.fromJson({
    'id': 1,
    'message': 'Null check operator used on a null value',
    'stack': '#0 main.dart.js 12:40\n#1 main.dart.js 88:2',
    'page': '/gyms/g1/manage/check-in',
    'platform': 'android',
    'times': 14,
    'first_seen': '2026-11-17T08:00:00Z',
    'last_seen': '2026-11-18T09:30:00Z',
    'user_id': 'u1',
    'profiles': {'full_name': 'Karma Choden', 'email': 'karma@x.bt'},
  }),
  AppError.fromJson({
    'id': 2,
    'message': 'RangeError (index): Index out of range: no indices are valid: 0',
    'page': '/welcome',
    'platform': 'web',
    'times': 1,
    'first_seen': '2026-11-18T07:00:00Z',
    'last_seen': '2026-11-18T07:00:00Z',
  }),
];

List<Override> adminWith(List<AppError> list, {Set<String> permissions = const {}, bool superAdmin = true}) => [
      myAccessProvider
          .overrideWith((ref) async => PlatformAccess(isSuperAdmin: superAdmin, isActive: true, permissions: permissions)),
      appErrorsProvider.overrideWith((ref) async => list),
    ];

void main() {
  group('error reports', () {
    late List<Map<String, String?>> sent;
    late ErrorReporter reporter;

    setUp(() {
      sent = [];
      reporter = ErrorReporter((params) async => sent.add(params), platform: 'web', page: () => '/gyms/g1/manage');
    });

    StackTrace stackAt(String top, {int lines = 5}) =>
        StackTrace.fromString([top, for (var i = 1; i < lines; i++) '#$i frame $i'].join('\n'));

    test('an error goes with its page, platform and the top of its stack', () async {
      expect(reporter.report(StateError('No member'), stackAt('#0 members.dart 10:4', lines: 80)), isTrue);
      await pumpEventQueue();
      expect(sent.single['error_message'], 'Bad state: No member');
      expect(sent.single['at_page'], '/gyms/g1/manage');
      expect(sent.single['on_platform'], 'web');
      expect(sent.single['error_stack']!.split('\n'), hasLength(60));
    });

    test('the same error goes once a run; the same message elsewhere is another', () async {
      expect(reporter.report(StateError('x'), stackAt('#0 a.dart 1:1')), isTrue);
      expect(reporter.report(StateError('x'), stackAt('#0 a.dart 1:1')), isFalse);
      expect(reporter.report(StateError('x'), stackAt('#0 b.dart 2:2')), isTrue);
      await pumpEventQueue();
      expect(sent, hasLength(2));
    });

    test('a lost connection is not an error to fix', () {
      for (final e in [
        'ClientException: Failed to fetch, uri=https://x.supabase.co/rest/v1/venues',
        'SocketException: Network is unreachable',
        'TimeoutException after 0:00:20.000000: Future not completed',
        'HTTP request failed, statusCode: 404, https://x.supabase.co/storage/v1/a.webp',
      ]) {
        expect(reporter.report(Exception(e), null), isFalse, reason: e);
      }
      expect(reporter.report(StateError('Real trouble'), null), isTrue);
    });

    test('at most ten a run, and long messages are cut', () async {
      expect(reporter.report(StateError('y' * 3000), null), isTrue);
      for (var i = 0; i < 20; i++) {
        reporter.report(StateError('error $i'), null);
      }
      await pumpEventQueue();
      expect(sent, hasLength(ErrorReporter.maxPerRun));
      expect(sent.first['error_message'], hasLength(1000));
      expect(sent.first['error_stack'], isNull);
    });

    test('a report that can\'t go is let go quietly', () async {
      final failing = ErrorReporter((_) async => throw Exception('offline'), platform: 'android');
      expect(failing.report(StateError('z'), null), isTrue);
      await pumpEventQueue();
    });

    test('who it happened to, as far as the viewer may see', () {
      expect(errors[0].who, 'Karma Choden');
      expect(errors[1].who, 'A visitor');
      expect(
        AppError.fromJson({...{for (final e in ['id', 'message', 'times']) e: e == 'message' ? 'm' : 1},
          'first_seen': '2026-11-18T07:00:00Z', 'last_seen': '2026-11-18T07:00:00Z', 'user_id': 'u9'}).who,
        'Someone signed in',
      );
    });
  });

  group('App errors page', () {
    for (final size in [phone, laptop]) {
      final at = size == phone ? 'phone' : 'laptop';

      testWidgets('lists them and opens one on a $at', (tester) async {
        await show(tester, const AdminErrorsScreen(), size, overrides: adminWith(errors));
        expect(tester.takeException(), isNull);
        expect(find.text('Null check operator used on a null value'), findsOneWidget);
        expect(find.text('14×'), findsOneWidget);

        await tester.tap(find.text('Null check operator used on a null value'));
        await tester.pumpAndSettle();
        expect(find.text('App error'), findsOneWidget);
        expect(find.textContaining('#0 main.dart.js 12:40'), findsOneWidget);
        expect(find.textContaining('Karma Choden', findRichText: true), findsOneWidget);
        expect(find.text('Clear, it\'s fixed'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('says when there are none', (tester) async {
      await show(tester, const AdminErrorsScreen(), phone, overrides: adminWith(const []));
      expect(find.text('No errors'), findsOneWidget);
    });

    testWidgets('is for those with errors.view', (tester) async {
      await show(tester, const AdminErrorsScreen(), phone,
          overrides: adminWith(errors, superAdmin: false, permissions: {PlatformPermission.users}));
      expect(find.text("Your role doesn't include this"), findsOneWidget);
      expect(find.text('Null check operator used on a null value'), findsNothing);
    });
  });

  group('privacy policy and terms', () {
    test('anyone opens them, signed in or not', () {
      for (final page in [CoreRoutes.privacy, CoreRoutes.terms]) {
        for (final signedIn in [false, true]) {
          expect(
            guardRoute(uri: Uri.parse(page), pattern: page, signedIn: signedIn, publicPatterns: CoreRoutes.publicPaths),
            isNull,
            reason: '$page, signed in: $signedIn',
          );
        }
      }
    });

    for (final (name, page) in [('privacy policy', const PrivacyPolicyScreen()), ('terms', const TermsScreen())]) {
      for (final size in [phone, laptop]) {
        testWidgets('the $name read to the end on a ${size == phone ? 'phone' : 'laptop'}', (tester) async {
          await show(tester, page, size);
          expect(find.textContaining('run by ${LegalInfo.company}'), findsOneWidget);
          await tester.scrollUntilVisible(find.text('Contact us'), 300, scrollable: find.byType(Scrollable).first);
          await tester.pumpAndSettle();
          expect(find.textContaining(LegalInfo.contactEmail.isEmpty ? 'coming soon' : LegalInfo.contactEmail), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('the sign-up form and the account page link to both', (tester) async {
      await show(tester, const Scaffold(body: Center(child: LegalLinks(lead: 'By registering, you agree to the'))), phone);
      expect(find.text('Terms of use'), findsOneWidget);
      expect(find.text('Privacy policy'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final size in [phone, laptop]) {
      testWidgets('the links open them over the page on a ${size == phone ? 'phone' : 'laptop'}, and switch in place', (tester) async {
        await show(tester, const Scaffold(body: Center(child: LegalLinks(lead: 'By registering, you agree to the'))), size);
        await tester.tap(find.text('Privacy policy'));
        await tester.pumpAndSettle();
        expect(find.text('In short'), findsOneWidget);
        expect(find.textContaining('don\'t sell your information'), findsOneWidget);
        expect(find.text('By registering, you agree to the'), findsOneWidget, reason: 'the page stays underneath');

        await tester.tap(find.text('Terms of use').last);
        await tester.pumpAndSettle();
        expect(find.textContaining('never holds your money'), findsOneWidget);
        expect(find.textContaining('don\'t sell your information'), findsNothing);

        await tester.scrollUntilVisible(find.text('Contact us'), 300, scrollable: find.byType(Scrollable).last);
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        expect(find.text('In short'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
