import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro_core/health_pro_core.dart';
import 'package:health_pro_core/src/profiles/account_screens.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Account extends Fake implements ProfileRepository {
  @override
  Future<({String? primary, String? accent})?> theme(String userId) async => (primary: null, accent: null);
}

void main() {
  const me = Profile(id: 'u1', fullName: 'Pema Dorji', role: 'user', memberCode: '4K7P9Q', email: 'pema@sportshub.bt');

  Future<void> show(WidgetTester tester, Widget page, Size size) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        myProfileProvider.overrideWith((ref) async => me),
        currentUserIdProvider.overrideWithValue('u1'),
        profileRepositoryProvider.overrideWithValue(_Account()),
      ],
      child: MaterialApp(theme: AppTheme.light, home: page),
    ));
    await tester.pumpAndSettle();
  }

  // Side by side, the details and preferences cards share a height. A row
  // that measured its wrapping subtitle as one line once spilled out of it.
  for (final width in [1180.0, 960.0, 390.0]) {
    testWidgets('Account lays out without spilling at $width wide', (tester) async {
      await show(tester, const AccountScreen(), Size(width, 1800));
      expect(tester.takeException(), isNull);
      expect(find.text('Reduce motion'), findsOneWidget);
      expect(find.text('4K7P9Q'), findsOneWidget);
      expect(find.text('PD'), findsOneWidget);
    });
  }

  testWidgets('Edit profile: the initials follow the name being typed', (tester) async {
    await show(tester, const EditProfileScreen(), const Size(390, 900));
    expect(tester.takeException(), isNull);
    expect(find.text('PD'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, 'Karma Wangmo');
    await tester.pump();
    expect(find.text('KW'), findsOneWidget);
  });
}
