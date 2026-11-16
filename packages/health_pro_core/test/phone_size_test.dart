import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro_core/health_pro_core.dart';
import 'package:health_pro_core/src/theme/phone_size.dart';

// On a phone everything is a little smaller (HealthProApp wraps the app in
// PhoneSized); tablets and computers stay as they were.

/// What [PhoneSized] gives a page on a screen of [size], with the device's
/// text at [textScale].
Future<(TextScaler, VisualDensity)> seen(WidgetTester tester, Size size, {double textScale = 1}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  late TextScaler scaler;
  late VisualDensity density;
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    builder: (context, child) => PhoneSized(child: child!),
    home: Builder(builder: (context) {
      scaler = MediaQuery.textScalerOf(context);
      density = Theme.of(context).visualDensity;
      return const Scaffold(body: Text('Health Pro'));
    }),
  ));
  return (scaler, density);
}

void main() {
  testWidgets('a phone: text a little smaller, controls a little denser', (tester) async {
    final (scaler, density) = await seen(tester, const Size(390, 844));
    expect(scaler.scale(16), closeTo(16 * PhoneSize.textFactor, 0.001));
    expect(density, PhoneSize.density);
  });

  testWidgets('a phone on its side is still a phone', (tester) async {
    final (scaler, _) = await seen(tester, const Size(844, 390));
    expect(scaler.scale(16), lessThan(16));
  });

  testWidgets('a tablet or a computer: as before', (tester) async {
    for (final size in const [Size(820, 1180), Size(1440, 900)]) {
      final (scaler, density) = await seen(tester, size);
      expect(scaler.scale(16), 16, reason: '$size');
      expect(density, isNot(PhoneSize.density), reason: '$size');
    }
  });

  testWidgets('bigger text asked for on the phone stays as they chose', (tester) async {
    final (scaler, density) = await seen(tester, const Size(390, 844), textScale: 1.3);
    expect(scaler.scale(16), closeTo(16 * 1.3, 0.001));
    expect(density, PhoneSize.density, reason: 'controls still a little denser');
  });
}
