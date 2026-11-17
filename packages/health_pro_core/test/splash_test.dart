import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro_core/health_pro_core.dart';

/// The image the mark asked for.
String shownImage(WidgetTester tester) {
  final image = tester.widget<Image>(find.byType(Image)).image;
  return (image as AssetImage).assetName;
}

/// Every picture the logo shows.
List<String> shownImages(WidgetTester tester) =>
    [for (final image in tester.widgetList<Image>(find.byType(Image))) (image.image as AssetImage).assetName];

void main() {
  group('the logo', () {
    testWidgets('navy lettering in light, white lettering in dark, no tile', (tester) async {
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: const HealthProLogo()));
      expect(shownImages(tester), [endsWith('/logo_base.webp'), endsWith('/logo_heartbeat.webp')]);
      expect(find.bySemanticsLabel('Health Pro'), findsOneWidget);

      await tester.pumpWidget(MaterialApp(theme: AppTheme.dark, home: const HealthProLogo(markOnly: true)));
      await tester.pumpAndSettle(); // the theme fades from light to dark
      expect(shownImage(tester), endsWith('/mark_on_dark.webp'));
      expect(find.byType(DecoratedBox), findsNothing);
    });

    testWidgets('places that are navy in both themes ask for the white one', (tester) async {
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: const HealthProLogo(onDark: true)));
      expect(shownImages(tester), [endsWith('/logo_base_on_dark.webp'), endsWith('/logo_heartbeat_on_dark.webp')]);
    });

    testWidgets('is as wide as its shape, and shrinks to fit a narrow place', (tester) async {
      Widget page(Widget child) => Directionality(textDirection: TextDirection.ltr, child: Center(child: child));
      await tester.pumpWidget(page(const HealthProLogo(height: 54, onDark: true)));
      expect(tester.getSize(find.byType(HealthProLogo)), const Size(54 * HealthProLogo.aspectRatio, 54));
      await tester.pumpWidget(page(const SizedBox(width: 120, child: HealthProLogo(height: 54, onDark: true))));
      expect(tester.getSize(find.byType(HealthProLogo)).width, 120);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the heartbeat traces slowly, rests, and goes again; settling never hangs', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: HealthProLogo(onDark: true)));
      expect(find.byType(ShaderMask), findsNothing); // a moment's pause first
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 1500));
      expect(find.byType(ShaderMask), findsWidgets); // tracing
      await tester.pumpAndSettle(); // the trace ends; the rest is a timer, not frames
      expect(find.byType(ShaderMask), findsNothing);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 1500));
      expect(find.byType(ShaderMask), findsWidgets); // and again
    });

    testWidgets('stands still with Reduce motion, and where it is saved as a picture', (tester) async {
      for (final logo in [
        const MediaQuery(data: MediaQueryData(disableAnimations: true), child: HealthProLogo(onDark: true)),
        const HealthProLogo(onDark: true, animate: false),
      ]) {
        await tester.pumpWidget(MaterialApp(home: logo));
        await tester.pump(const Duration(seconds: 3));
        expect(find.byType(ShaderMask), findsNothing);
        expect(tester.binding.hasScheduledFrame, isFalse);
      }
    });

    test('every picture it can ask for is in the package', () {
      for (final part in HealthProLogo.parts) {
        for (final onDark in [false, true]) {
          final path = HealthProLogo.assetFor(part, onDark: onDark);
          expect(File(path).existsSync(), isTrue, reason: path);
        }
      }
    });
  });

  group('the splash', () {
    Future<void> showSplash(WidgetTester tester, Size screen, {ThemeData? theme}) async {
      tester.view.physicalSize = screen;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(theme: theme, home: const HealthProSplash()));
    }

    testWidgets('the logo is dead centre, 240 wide on a phone, as the launch screens draw it', (tester) async {
      await showSplash(tester, const Size(390, 844));
      final logo = tester.getRect(find.byType(HealthProLogo));
      expect(logo.center, const Offset(195, 422));
      expect(logo.width, 240);
      expect(logo.height, closeTo(240 * 598 / 2048, 0.01));
    });

    testWidgets('the heartbeat starts tracing at once', (tester) async {
      await showSplash(tester, const Size(390, 844));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1200));
      expect(find.descendant(of: find.byType(HealthProLogo), matching: find.byType(ShaderMask)), findsWidgets);
    });

    testWidgets('320 wide on a computer', (tester) async {
      await showSplash(tester, const Size(1440, 900));
      final logo = tester.getRect(find.byType(HealthProLogo));
      expect(logo.center, const Offset(720, 450));
      expect(logo.width, 320);
    });

    testWidgets('white lettering on navy, in the light theme too, and it says it is loading', (tester) async {
      final semantics = tester.ensureSemantics();
      await showSplash(tester, const Size(390, 844), theme: AppTheme.light);
      expect(shownImages(tester), [endsWith('/logo_base_on_dark.webp'), endsWith('/logo_heartbeat_on_dark.webp')]);
      expect(find.bySemanticsLabel('Loading'), findsOneWidget);
      // The bar sits under the logo.
      final logo = tester.getRect(find.byType(HealthProLogo));
      final bar = tester.getRect(find.bySemanticsLabel('Loading'));
      expect(bar.top, closeTo(logo.bottom + HealthProSplash.barGap, 0.001));
      expect(bar.center.dx, logo.center.dx);
      semantics.dispose();
    });
  });

  testWidgets('the gate shows the splash until ready, then fades to the page', (tester) async {
    Widget gate(bool ready) => MaterialApp(home: SplashGate(ready: ready, builder: (_) => const Text('the page')));
    await tester.pumpWidget(gate(false));
    expect(find.byType(HealthProSplash), findsOneWidget);
    expect(find.text('the page'), findsNothing);

    await tester.pumpWidget(gate(true));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byType(HealthProSplash), findsOneWidget, reason: 'still fading out');
    expect(find.text('the page'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.byType(HealthProSplash), findsNothing);
    expect(find.text('the page'), findsOneWidget);
  });

  testWidgets('signed in, the frame shows the splash while the modules load', (tester) async {
    final modules = Completer<List<HealthProModule>>();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWithValue('u1'),
        enabledModulesProvider.overrideWith((ref) => modules.future),
      ],
      child: const MaterialApp(home: AppShell(location: '/home', child: Text('the page'))),
    ));
    expect(find.byType(HealthProSplash), findsOneWidget);
    expect(find.text('the page'), findsNothing);

    modules.complete(const []);
    await tester.pumpAndSettle();
    expect(find.byType(HealthProSplash), findsNothing);
    expect(find.text('the page'), findsOneWidget);
  });

  testWidgets('the loader spins, and says what it is waiting for', (tester) async {
    final semantics = tester.ensureSemantics();
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: const Center(child: HealthProLoader(size: 56, semanticsLabel: 'Loading gyms')),
      ));
      expect(tester.getSize(find.byType(HealthProLoader)), const Size(56, 56));
      expect(find.bySemanticsLabel('Loading gyms'), findsOneWidget);
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }
      expect(tester.binding.hasScheduledFrame, isTrue);
    }
    // Small: the orange arc alone.
    await tester.pumpWidget(const MaterialApp(home: Center(child: HealthProLoader(size: 20))));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets("pages waiting on data show the shape of what's coming, shimmering", (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: AsyncValueView<int>(value: const AsyncLoading(), data: (n) => Text('$n')),
    ));
    expect(find.byType(LoadingSkeleton), findsOneWidget);
    expect(find.byType(Shimmer), findsOneWidget);
    expect(find.bySemanticsLabel('Loading'), findsOneWidget);
  });

  testWidgets('a skeleton fits a small box and a list alike', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Column(children: [SizedBox(height: 60, child: LoadingSkeleton()), LoadingSkeleton.rows()]),
    ));
    expect(tester.takeException(), isNull);
  });
}
