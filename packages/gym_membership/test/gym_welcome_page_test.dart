import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_membership/src/welcome/gym_welcome_page.dart';
import 'package:health_pro_core/health_pro_core.dart';

void main() {
  Future<void> show(WidgetTester tester, Size size, {bool dark = false}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp(theme: dark ? AppTheme.dark : AppTheme.light, home: const GymWelcomePage())),
    );
  }

  const sizes = {'phone': Size(390, 844), 'tablet': Size(820, 1180), 'computer': Size(1440, 900)};

  for (final MapEntry(key: name, value: size) in sizes.entries) {
    for (final dark in [false, true]) {
      testWidgets('Welcome fits a $name, ${dark ? 'dark' : 'light'}', (tester) async {
        await show(tester, size, dark: dark);
        // The whole page is laid out (it scrolls as one), so an overflow
        // anywhere on it fails here.
        expect(tester.takeException(), isNull);
        expect(find.text('Perfect Plan'), findsOneWidget);
        expect(find.text('Questions?'), findsOneWidget);
      });
    }
  }

  testWidgets("Ask AI is in the header, before light or dark, and opens Health Pro's assistant", (tester) async {
    await show(tester, sizes['computer']!);
    final askAi = find.text('Ask AI');
    expect(askAi, findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(tester.getCenter(askAi).dx, lessThan(tester.getCenter(find.byType(ThemeModeButton)).dx));
    await tester.tap(askAi);
    await tester.pumpAndSettle();
    expect(find.text('Health Pro assistant'), findsOneWidget);
  });

  testWidgets('on a phone Ask AI is an icon in the header', (tester) async {
    await show(tester, sizes['phone']!);
    expect(find.byTooltip('Ask AI'), findsOneWidget);
    expect(find.text('Ask AI'), findsNothing);
  });

  testWidgets('a question opens to its answer', (tester) async {
    await show(tester, sizes['computer']!);
    const question = 'What payment methods are accepted?';
    // Scrolled to, the questions rise into place; then they're where a
    // second look finds them.
    await tester.ensureVisible(find.text(question));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(question));
    await tester.pumpAndSettle();
    expect(find.textContaining('enter the journal number (JRN)'), findsNothing);
    await tester.tap(find.text(question));
    await tester.pumpAndSettle();
    expect(find.textContaining('enter the journal number (JRN)'), findsOneWidget);
  });

  testWidgets('the answers follow how gyms work today: the front desk registers members', (tester) async {
    await show(tester, sizes['computer']!);
    const question = 'How do I join a gym?';
    await tester.ensureVisible(find.text(question));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(question));
    await tester.pumpAndSettle();
    await tester.tap(find.text(question));
    await tester.pumpAndSettle();
    expect(find.textContaining('the front desk registers you'), findsOneWidget);
    for (final old in ['ask to join', 'Open My gym', 'the day after the current one ends', 'cancel a request']) {
      expect(find.textContaining(old), findsNothing, reason: old);
    }
  });

  for (final MapEntry(key: name, value: size) in {'computer': sizes['computer']!, 'phone': sizes['phone']!}.entries) {
    testWidgets('on a $name the light walks through the steps, one every two seconds', (tester) async {
      final semantics = tester.ensureSemantics();
      await show(tester, size);
      // The dots under the steps say which one is lit.
      Finder dot(int step) => find.bySemanticsLabel(RegExp('^Step $step: '));
      int lit() {
        final on = [
          for (var i = 1; i <= 5; i++)
            if (containsSemantics(isSelected: true).matches(tester.getSemantics(dot(i)), {})) i,
        ];
        expect(on, hasLength(1));
        return on.single;
      }

      await tester.ensureVisible(find.text('Achieve Goals'));
      await tester.pumpAndSettle();
      // Mid-screen, clear of the bar along the top.
      await Scrollable.ensureVisible(tester.element(dot(5)), alignment: 0.5);
      await tester.pumpAndSettle();
      // Tapping a dot moves the light there, and it walks on from it.
      await tester.tap(dot(4));
      await tester.pump();
      expect(lit(), 4);
      for (var i = 1; i <= 5; i++) {
        await tester.pump(const Duration(seconds: 2));
        // After the goal it starts again from signing up.
        expect(lit(), (3 + i) % 5 + 1);
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
  }

  testWidgets('what it does lights up one thing after another, on the beat', (tester) async {
    await show(tester, sizes['computer']!);
    // Frame by frame, so what the beat sets moving plays out.
    Future<void> wait(int ms) async {
      for (var t = 0; t < ms; t += 100) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    const titles = ['Membership Management', 'Attendance Tracking', 'Easy Payments', 'Staff & Roles', 'Business Insights'];
    // The lit one's name is the only one in orange.
    int lit() {
      final colours = [for (final title in titles) tester.widget<Text>(find.text(title)).style!.color];
      final odd = [for (var i = 0; i < titles.length; i++) if (colours.where((c) => c == colours[i]).length == 1) i];
      expect(odd, hasLength(1));
      return odd.single;
    }

    await wait(1500);
    expect(lit(), 0);
    for (var i = 1; i <= 5; i++) {
      await wait(2000);
      expect(lit(), i % 5);
    }
  });

  testWidgets('the mouse takes the light from the beat, and gives it back on leaving', (tester) async {
    await show(tester, sizes['computer']!);
    Future<void> wait(int ms) async {
      for (var t = 0; t < ms; t += 100) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    const titles = ['Membership Management', 'Attendance Tracking', 'Easy Payments', 'Staff & Roles', 'Business Insights'];
    int lit() {
      final colours = [for (final title in titles) tester.widget<Text>(find.text(title)).style!.color];
      return [for (var i = 0; i < titles.length; i++) if (colours.where((c) => c == colours[i]).length == 1) i].single;
    }

    // Into the middle of the screen, clear of the header.
    await Scrollable.ensureVisible(tester.element(find.text('Business Insights')), alignment: 0.5);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await wait(1500);
    expect(lit(), 0);
    await mouse.moveTo(tester.getCenter(find.text('Business Insights')));
    // It stays while the beat goes on.
    await wait(4500);
    expect(lit(), 4);
    expect(tester.takeException(), isNull);
    await mouse.moveTo(Offset.zero);
    await wait(1000);
    expect(lit(), isNot(4));
  });

  testWidgets('it claims no member counts, ratings or prices', (tester) async {
    await show(tester, sizes['computer']!);
    for (final madeUp in ['10K+', '10,000', '4.8', 'Nu ', 'Rated']) {
      expect(find.textContaining(madeUp), findsNothing, reason: madeUp);
    }
  });
}
