import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro_core/health_pro_core.dart';
import 'package:health_pro_core/src/push/push_notifications.dart';

// Push notifications on this device, on the Notifications page (the
// sending: tests/functions/web_push_test.ts; the database:
// tests/database/push_test.sql).

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
