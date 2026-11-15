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

  testWidgets('My QR code: big, on white in both themes, with their name', (tester) async {
    for (final (theme, size) in [(AppTheme.light, const Size(390, 844)), (AppTheme.dark, const Size(1440, 1000))]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        key: UniqueKey(),
        overrides: [
          myPersonProvider.overrideWith((ref) async => const MyPerson(id: 'p1', qrToken: 'abc', name: 'Sonam Choden')),
        ],
        child: MaterialApp(theme: theme, home: const MyQrScreen()),
      ));
      await tester.pumpAndSettle();
      final qr = tester.widget<QrImageView>(find.byType(QrImageView));
      expect(qr.backgroundColor, Colors.white);
      expect(tester.getSize(find.byType(QrImageView)).width, greaterThanOrEqualTo(260), reason: 'big enough to scan');
      expect(find.text('Sonam Choden'), findsOneWidget);
      expect(find.text('Get a new QR code'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('Install app: nothing outside a browser (the phone apps are installed already)', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: InstallAppButton())));
    expect(find.text('Install app'), findsNothing);
  });
}
