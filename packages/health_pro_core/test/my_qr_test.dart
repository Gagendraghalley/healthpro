import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:health_pro_core/health_pro_core.dart';
import 'package:health_pro_core/src/auth/install_app_button.dart';
import 'package:health_pro_core/src/people/my_qr_screen.dart';

void main() {
  group('a Health Pro QR code', () {
    const token = '0123456789abcdef0123456789abcdef';

    test('holds only the token', () {
      expect(PersonQr.encode(token), 'healthpro:member:$token');
      expect(PersonQr.tokenIn(' HEALTHPRO:MEMBER:${token.toUpperCase()} '), token);
      expect(PersonQr.tokenIn('healthpro:member:short'), isNull);
      expect(PersonQr.tokenIn('sportshub:gym-member:$token'), isNull);
    });
  });

  testWidgets('My dashboard: their QR code on white in both themes, with their name, details and updates', (tester) async {
    for (final (theme, size) in [(AppTheme.light, const Size(390, 844)), (AppTheme.dark, const Size(1440, 1000))]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        key: UniqueKey(),
        overrides: [
          myPersonProvider.overrideWith((ref) async => const MyPerson(id: 'p1', qrToken: 'abc', name: 'Sonam Choden')),
          myProfileProvider.overrideWith((ref) async =>
              const Profile(id: 'u1', fullName: 'Sonam Choden', role: 'user', memberCode: 'X', email: 'sonam@x.bt')),
          notificationsProvider.overrideWith((ref) => Stream.value([
                AppNotification(id: 'n1', title: 'Payment confirmed', createdAt: DateTime.now().toUtc()),
              ])),
          enabledModulesProvider.overrideWith((ref) async => const <HealthProModule>[]),
        ],
        child: MaterialApp(theme: theme, home: const MyQrScreen()),
      ));
      await tester.pumpAndSettle();
      final qr = tester.widget<QrImageView>(find.byType(QrImageView));
      expect(qr.backgroundColor, Colors.white);
      expect(tester.getSize(find.byType(QrImageView)).width, 176, reason: 'small on the page; Enlarge shows it big');
      expect(find.text('Sonam Choden'), findsNWidgets(2), reason: 'on the pass, and in My details');
      for (final label in ['Enlarge', 'Copy', 'Share', 'Save', 'My details', 'sonam@x.bt', 'Not added']) {
        expect(find.text(label), findsWidgets, reason: label);
      }
      expect(find.text('Latest updates'), findsOneWidget);
      expect(find.text('1 new'), findsOneWidget, reason: 'beside the title');
      expect(find.text('1 new update'), findsOneWidget, reason: 'on the welcome band');
      expect(find.text('Payment confirmed'), findsOneWidget);
      expect(find.textContaining(', Sonam'), findsOneWidget, reason: 'greeted by first name');
      expect(find.text('Get a new QR code'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    // Enlarge: the code big, for the desk's scanner.
    await tester.ensureVisible(find.text('Enlarge'));
    await tester.tap(find.text('Enlarge'));
    await tester.pumpAndSettle();
    expect(find.text('Show this at the front desk'), findsOneWidget);
    expect(tester.getSize(find.byType(QrImageView).last).width, greaterThanOrEqualTo(260), reason: 'big enough to scan');
  });

  testWidgets('Install app: nothing outside a browser (the phone apps are installed already)', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: InstallAppButton())));
    expect(find.text('Install app'), findsNothing);
  });

  test('Install app by hand: each browser named by web/index.html has its steps', () {
    const names = [
      'ios', 'ios-chrome', 'ios-other', 'android', 'samsung', 'android-firefox', 'chrome', 'edge', 'mac-safari', //
      'firefox', 'other',
    ];
    expect(names.map(InstallBrowser.from).toSet(), InstallBrowser.values.toSet(), reason: 'every browser, once');
    expect(InstallBrowser.from('netscape'), InstallBrowser.other);
    for (final browser in InstallBrowser.values) {
      expect(browser.guide.steps, isNotEmpty, reason: '$browser');
    }
  });

  testWidgets('Install app by hand: the steps for this browser, on a phone and in both themes', (tester) async {
    for (final (theme, size) in [(AppTheme.light, const Size(360, 640)), (AppTheme.dark, const Size(1440, 1000))]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final browser in InstallBrowser.values) {
        await tester.pumpWidget(MaterialApp(
          key: UniqueKey(),
          theme: theme,
          home: Scaffold(body: Align(alignment: Alignment.bottomCenter, child: InstallSteps(browser: browser))),
        ));
        expect(find.text('Install Health Pro'), findsOneWidget);
        expect(find.text(browser.guide.steps.first.$2), findsOneWidget, reason: '$browser');
        expect(tester.takeException(), isNull, reason: '$browser at $size');
      }
    }
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: InstallSteps(browser: InstallBrowser.macSafari))));
    expect(find.text('Choose Add to Dock.'), findsOneWidget);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: InstallSteps(browser: InstallBrowser.iosChrome))));
    expect(find.text('Tap Share, in the address bar.'), findsOneWidget, reason: 'Chrome on an iPhone: Share is there');
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: InstallSteps(browser: InstallBrowser.firefox))));
    expect(find.text('Firefox on a computer can\'t install apps.'), findsOneWidget);
  });
}
