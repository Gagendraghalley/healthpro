import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:health_pro_core/health_pro_core.dart';

/// The profiles table's two colour columns, per account.
class FakeAccount extends Fake implements ProfileRepository {
  final bool offline;
  final Future<void>? wait;
  final themes = <String, ({String? primary, String? accent})>{};

  FakeAccount({this.offline = false, this.wait});

  @override
  Future<({String? primary, String? accent})?> theme(String userId) async {
    await wait;
    if (offline) throw Exception('offline');
    return themes[userId] ?? (primary: null, accent: null);
  }

  @override
  Future<void> setTheme(String userId, {String? primary, String? accent}) async {
    // A little slower than the device, as a network is.
    await Future<void>.delayed(const Duration(milliseconds: 1));
    if (offline) throw Exception('offline');
    themes[userId] = (primary: primary, accent: accent);
  }
}

void main() {
  final blue = ThemePalette.primaries.firstWhere((s) => s.id == 'blue');
  final plum = ThemePalette.accents.firstWhere((s) => s.id == 'plum');
  Brand brandOf(ThemeData theme) => theme.extension<Brand>()!;

  group('the themes', () {
    test('Health Pro\'s own colours leave both themes as they were', () {
      final light = AppTheme.light;
      expect(light.colorScheme.primary, LightColors.navy);
      expect(light.colorScheme.primaryContainer, const Color(0xFFE6ECF6));
      expect(light.colorScheme.secondary, LightColors.orange);
      expect(light.colorScheme.secondaryContainer, const Color(0xFFFFEDDF));
      expect(light.colorScheme.onSecondaryContainer, const Color(0xFF9A3A0B));
      expect(light.colorScheme.inversePrimary, const Color(0xFFFFB27A));
      expect(brandOf(light).accent, LightColors.orange);
      expect(brandOf(light).accentText, LightColors.orangeText);
      expect(brandOf(light).highlight, BrandColors.orange);
      expect(brandOf(light).glowB, const Color(0x08F97316));

      final dark = AppTheme.dark;
      final seeded = ColorScheme.fromSeed(seedColor: BrandColors.navy, brightness: Brightness.dark);
      expect(dark.colorScheme.primary, BrandColors.orange);
      expect(dark.colorScheme.secondary, const Color(0xFF9CC2FF));
      expect(dark.colorScheme.secondaryContainer, seeded.secondaryContainer);
      expect(brandOf(dark).accent, BrandColors.orange);
      expect(brandOf(dark).glowB, const Color(0x1FFF790F));
      expect(brandOf(dark).themed(BrandColors.orange), BrandColors.orange);
      expect(brandOf(dark).themedShade(const Color(0xFFFFA24D)), const Color(0xFFFFA24D));
    });

    test('a picked primary and accent run through both themes', () {
      final picked = ThemeColors(primary: blue, accent: plum);
      final light = AppTheme.lightWith(picked);
      expect(light.colorScheme.primary, plum.light);
      expect(light.colorScheme.secondary, blue.light);
      expect(brandOf(light).accent, blue.light);
      expect(brandOf(light).accentText, blue.text);
      // The brand's orange (a service's colour) follows; other colours stay.
      expect(brandOf(light).themed(BrandColors.orange), blue.light);
      expect(brandOf(light).themed(BrandColors.green), BrandColors.green);

      final dark = AppTheme.darkWith(picked);
      expect(dark.colorScheme.primary, blue.dark);
      expect(dark.colorScheme.secondary, plum.dark);
      expect(brandOf(dark).highlight, blue.dark);
    });
  });

  group('each account its own', () {
    Future<void> settle() async {
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    ProviderContainer signedIn(Override user, FakeAccount account) {
      final container = ProviderContainer(overrides: [user, profileRepositoryProvider.overrideWithValue(account)]);
      addTearDown(container.dispose);
      return container;
    }

    test('what one person picks is theirs; signed out is Health Pro\'s own', () async {
      SharedPreferences.setMockInitialValues({});
      final who = StateProvider<String?>((ref) => 'u1');
      final account = FakeAccount();
      final container = signedIn(currentUserIdProvider.overrideWith((ref) => ref.watch(who)), account);
      final picked = ThemeColors(primary: blue, accent: plum);
      expect(container.read(themeColorsProvider), ThemeColors.standard);
      await container.read(themeColorsProvider.notifier).setPrimary(blue);
      await container.read(themeColorsProvider.notifier).setAccent(plum);
      expect(container.read(themeColorsProvider), picked);
      expect(account.themes['u1'], (primary: 'blue', accent: 'plum'));

      // Signed out: the welcome and sign-in pages, for everyone.
      container.read(who.notifier).state = null;
      expect(container.read(themeColorsProvider), ThemeColors.standard);
      await container.read(themeColorsProvider.notifier).setPrimary(blue);
      expect(container.read(themeColorsProvider), ThemeColors.standard);

      container.read(who.notifier).state = 'u2';
      await settle();
      expect(container.read(themeColorsProvider), ThemeColors.standard);

      container.read(who.notifier).state = 'u1';
      expect(container.read(themeColorsProvider), picked);
      expect(await ThemeColorsController.saved('u1'), picked);
      expect(await ThemeColorsController.saved('u2'), ThemeColors.standard);
      expect(await ThemeColorsController.saved(null), ThemeColors.standard);
    });

    test('signing in on another device brings their account\'s colours, and keeps them there too', () async {
      SharedPreferences.setMockInitialValues({});
      final account = FakeAccount()..themes['u1'] = (primary: 'blue', accent: 'plum');
      final container = signedIn(currentUserIdProvider.overrideWithValue('u1'), account);
      container.read(themeColorsProvider);
      await settle();
      expect(container.read(themeColorsProvider), ThemeColors(primary: blue, accent: plum));
      expect(await ThemeColorsController.saved('u1'), ThemeColors(primary: blue, accent: plum));
    });

    test('offline, this device\'s colours stay; an id no longer offered is the default', () async {
      SharedPreferences.setMockInitialValues({'theme_primary.u1': 'blue', 'theme_accent.u1': 'gone'});
      final container = signedIn(currentUserIdProvider.overrideWithValue('u1'), FakeAccount(offline: true));
      container.read(themeColorsProvider);
      await settle();
      expect(container.read(themeColorsProvider), ThemeColors(primary: blue));
      await container.read(themeColorsProvider.notifier).setAccent(plum);
      expect(container.read(themeColorsProvider), ThemeColors(primary: blue, accent: plum));
    });

    test('quick picks reach the account in order; Health Pro\'s own is kept as none', () async {
      SharedPreferences.setMockInitialValues({});
      final account = FakeAccount();
      final container = signedIn(currentUserIdProvider.overrideWithValue('u1'), account);
      final colors = container.read(themeColorsProvider.notifier);
      await Future.wait([colors.setPrimary(blue), colors.setAccent(plum)]);
      expect(account.themes['u1'], (primary: 'blue', accent: 'plum'));
      await colors.reset();
      expect(account.themes['u1'], (primary: null, accent: null));
    });

    test('an answer from the account asked before a pick doesn\'t undo it', () async {
      SharedPreferences.setMockInitialValues({});
      final slow = Completer<void>();
      final account = FakeAccount(wait: slow.future)..themes['u1'] = (primary: 'red', accent: null);
      final container = signedIn(currentUserIdProvider.overrideWithValue('u1'), account);
      container.read(themeColorsProvider);
      await container.read(themeColorsProvider.notifier).setPrimary(blue);
      slow.complete();
      await settle();
      expect(container.read(themeColorsProvider), ThemeColors(primary: blue));
    });
  });

  testWidgets('the dialog picks a colour, and Reset goes back to orange', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer(overrides: [
      currentUserIdProvider.overrideWithValue('u1'),
      profileRepositoryProvider.overrideWithValue(FakeAccount()),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (context, ref, _) => MaterialApp(
            theme: AppTheme.lightWith(ref.watch(themeColorsProvider)),
            home: const Scaffold(body: ThemeColorsTile()),
          ),
        ),
      ),
    );
    expect(find.text('Orange and navy'), findsOneWidget);

    await tester.tap(find.byType(ThemeColorsTile));
    await tester.pumpAndSettle();
    expect(find.text('Pick colour theme'), findsOneWidget);

    await tester.tap(find.byTooltip('Blue'));
    await tester.tap(find.byTooltip('Plum'));
    await tester.pumpAndSettle();
    expect(container.read(themeColorsProvider), ThemeColors(primary: blue, accent: plum));
    expect(brandOf(Theme.of(tester.element(find.text('Pick colour theme')))).accent, blue.light);

    await tester.ensureVisible(find.text('Reset to default orange'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset to default orange'));
    await tester.pumpAndSettle();
    expect(container.read(themeColorsProvider), ThemeColors.standard);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Pick colour theme'), findsNothing);
  });

  testWidgets("Ask AI's icon is in the app's colour, the one they picked too, light and dark", (tester) async {
    final blue = ThemePalette.primaries.firstWhere((s) => s.id == 'blue');
    for (final (theme, width) in [
      (AppTheme.light, 1200.0),
      (AppTheme.lightWith(ThemeColors(primary: blue)), 1200.0),
      (AppTheme.darkWith(ThemeColors(primary: blue)), 1200.0),
      (AppTheme.lightWith(ThemeColors(primary: blue)), 390.0),
    ]) {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: Scaffold(body: Center(child: AskAiBarButton(onPressed: () {}))),
      ));
      await tester.pumpAndSettle(); // the theme eases from the last one
      final brand = theme.extension<Brand>()!;
      final icon = tester.widget<RichText>(
          find.descendant(of: find.byIcon(Icons.auto_awesome_rounded), matching: find.byType(RichText)));
      expect(icon.text.style?.color, brand.accent, reason: '${theme.brightness} at $width');
    }
  });
}
