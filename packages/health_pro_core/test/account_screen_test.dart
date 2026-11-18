import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:health_pro_core/health_pro_core.dart';
import 'package:health_pro_core/src/profiles/account_screens.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Account extends Fake implements ProfileRepository {
  final saved = <String?>[];
  final removed = <String>[];

  @override
  Future<({String? primary, String? accent})?> theme(String userId) async => (primary: null, accent: null);

  @override
  Future<void> update(String userId,
      {required String fullName, String? phone, String? dzongkhag, required String? avatarUrl}) async {
    saved.add(avatarUrl);
  }

  @override
  Future<void> removePhoto(String userId, String url) async => removed.add(url);
}

void main() {
  const me = Profile(id: 'u1', fullName: 'Pema Dorji', role: 'user', memberCode: '4K7P9Q', email: 'pema@sportshub.bt');

  Future<void> show(WidgetTester tester, Widget page, Size size, {Profile profile = me, _Account? account, bool router = false}) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        myProfileProvider.overrideWith((ref) async => profile),
        currentUserIdProvider.overrideWithValue('u1'),
        profileRepositoryProvider.overrideWithValue(account ?? _Account()),
      ],
      child: router
          ? MaterialApp.router(
              theme: AppTheme.light,
              routerConfig: GoRouter(routes: [
                GoRoute(path: '/', builder: (_, __) => page),
                GoRoute(path: CoreRoutes.account, builder: (_, __) => const Text('Account page')),
              ]),
            )
          : MaterialApp(theme: AppTheme.light, home: page),
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

  for (final width in [1440.0, 900.0, 390.0]) {
    testWidgets('Edit profile lays out across the page without spilling at $width wide', (tester) async {
      await show(tester, const EditProfileScreen(), Size(width, 1100));
      expect(tester.takeException(), isNull);
      expect(find.text('Upload photo'), findsOneWidget);
      expect(find.text('Remove'), findsNothing);
      expect(find.text('Save changes'), findsOneWidget);
    });
  }

  testWidgets('Edit profile: taking the photo off saves none and clears the old file', (tester) async {
    const pictured = Profile(
        id: 'u1',
        fullName: 'Pema Dorji',
        role: 'user',
        memberCode: '4K7P9Q',
        email: 'pema@sportshub.bt',
        avatarUrl: 'https://x.supabase.co/storage/v1/object/public/profile-photos/u1/1.jpg');
    final account = _Account();
    await show(tester, const EditProfileScreen(), const Size(1280, 1000),
        profile: pictured, account: account, router: true);
    expect(find.text('Change photo'), findsOneWidget);
    double unsaved() => tester
        .widget<AnimatedOpacity>(find.ancestor(of: find.text('You have unsaved changes'), matching: find.byType(AnimatedOpacity)))
        .opacity;
    expect(unsaved(), 0);

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Upload photo'), findsOneWidget);
    expect(find.text('PD'), findsOneWidget);
    expect(unsaved(), 1);

    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(account.saved, [null]);
    expect(account.removed, [pictured.avatarUrl]);
    expect(find.text('Account page'), findsOneWidget);
  });
}
