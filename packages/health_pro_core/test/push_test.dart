import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro_core/health_pro_core.dart';
import 'package:health_pro_core/src/push/native_push.dart';
import 'package:health_pro_core/src/push/push_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Push notifications on this device, on the Notifications page, and on the
// phone apps (FCM) as far as they go without Firebase (the sending:
// tests/functions/web_push_test.ts; the database: tests/database/push_test.sql).

Future<void> showCard(WidgetTester tester, PushStatus status) async {
  await tester.pumpWidget(ProviderScope(
    key: UniqueKey(),
    overrides: [pushStatusProvider.overrideWith((ref) async => status)],
    child: MaterialApp(theme: AppTheme.light, home: const Scaffold(body: PushSettingCard())),
  ));
  await tester.pumpAndSettle();
}

void main() {
  test('not set up (no key): push is off, and nobody is asked', () async {
    expect(PushNotifications.configured, isFalse);
    expect(await PushNotifications.status(), PushStatus.unavailable);
  });

  test('the phone apps: what the phone allows', () {
    expect(NativePush.permissionOf(AuthorizationStatus.authorized, ios: false), 'granted');
    expect(NativePush.permissionOf(AuthorizationStatus.provisional, ios: true), 'granted');
    expect(NativePush.permissionOf(AuthorizationStatus.notDetermined, ios: true), 'default');
    // Android 13 and later may ask again; iOS only in its settings.
    expect(NativePush.permissionOf(AuthorizationStatus.denied, ios: false), 'default');
    expect(NativePush.permissionOf(AuthorizationStatus.denied, ios: true), 'denied');
    expect(NativePush.permissionOf(AuthorizationStatus.deniedPermanently, ios: false), 'denied');
  });

  test('the phone apps: a tapped notification opens only Health Pro''s own pages', () {
    expect(NativePush.linkOf({'link': '/gyms/my'}), '/gyms/my');
    expect(NativePush.linkOf({}), '/notifications');
    expect(NativePush.linkOf({'link': 'https://evil.example'}), '/notifications');
    expect(NativePush.linkOf({'link': '//evil.example'}), '/notifications');
  });

  test('the phone apps: on for the person who turned it on, not whoever signs in next', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await NativePush.current('pem'), isNull);
    await NativePush.remember('pem', 'fid-of-this-phone');
    expect(await NativePush.current('pem'), 'fid-of-this-phone');
    expect(await NativePush.current('kinley'), isNull);
    expect(await NativePush.current(null), isNull);
  });

  testWidgets('on this device: on, off, blocked, or install first (iPhone)', (tester) async {
    await showCard(tester, PushStatus.off);
    expect(find.text('Push notifications: Off on this device'), findsOneWidget);
    expect(find.text('Turn on'), findsOneWidget);

    await showCard(tester, PushStatus.on);
    expect(find.text('Push notifications: On, on this device'), findsOneWidget);
    expect(find.text('Turn off'), findsOneWidget);

    await showCard(tester, PushStatus.blocked);
    expect(find.textContaining('Allow notifications for Health Pro'), findsOneWidget);
    expect(find.text('Turn on'), findsNothing);

    await showCard(tester, PushStatus.needsInstall);
    expect(find.textContaining('Add to Home Screen'), findsOneWidget);

    await showCard(tester, PushStatus.unavailable);
    expect(find.textContaining('Push notifications'), findsNothing);
  });
}
