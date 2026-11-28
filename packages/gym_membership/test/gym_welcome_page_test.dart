import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_membership/gym_membership.dart';
import 'package:gym_membership/src/screens/public_screens.dart';
import 'package:gym_membership/src/welcome/gym_welcome_page.dart';
import 'package:health_pro_core/health_pro_core.dart';

Venue placeAt(String id, String name, double lat, double lng,
        {String type = gymVenueType, String dzongkhag = 'Thimphu', String? town}) =>
    Venue.fromJson({
      'id': id,
      'type': type,
      'name': name,
      'dzongkhag': dzongkhag,
      'town': town,
      'latitude': lat,
      'longitude': lng,
      'verification_status': 'verified',
      'created_at': '2026-11-01T00:00:00Z',
    });

// Three places in Thimphu (two areas), one in Paro; a kind with none yet.
final places = [
  placeAt('a', 'Alpha Gym', 27.4655, 89.6420, town: 'Changzamtog'),
  placeAt('b', 'Olakha Fitness', 27.4410, 89.6555, town: 'Olakha'),
  placeAt('p', 'Blue Lane Pool', 27.4640, 89.6400, type: 'swimming', town: 'Changzamtog'),
  placeAt('c', 'Chhu Gym', 27.4305, 89.4133, dzongkhag: 'Paro', town: 'Bondey'),
];
const kinds = [
  VenueType(key: gymVenueType, moduleKey: gymModuleKey, name: 'Gym', sortOrder: 10),
  VenueType(key: 'swimming', moduleKey: gymModuleKey, name: 'Swimming Pool', icon: 'pool', sortOrder: 20),
  VenueType(key: 'massage', moduleKey: gymModuleKey, name: 'Massage', icon: 'wellness', sortOrder: 30),
];

/// The places and kinds above; and the visitor standing at [here], when given.
List<Override> withPlaces({LatLng? here}) => [
      moduleVenuesProvider.overrideWith((ref, module) async => places),
      venueTypesProvider.overrideWith((ref) async => kinds),
      if (here != null) myLocationProvider.overrideWith((ref) => here),
    ];

void main() {
  Future<void> show(WidgetTester tester, Size size, {bool dark = false, List<Override> overrides = const []}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(theme: dark ? AppTheme.dark : AppTheme.light, home: const GymWelcomePage()),
      ),
    );
  }

  group("the user's layout", () {
    // Once the places have loaded, and asking for the location has failed
    // (tests have no location service).
    Future<void> open(WidgetTester tester, Size size, List<Override> overrides) async {
      await show(tester, size, overrides: overrides);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('until it knows where you are: "in Bhutan?", and the dzongkhags with places', (tester) async {
      await open(tester, const Size(1440, 900), withPlaces());
      expect(find.text('Bhutan?'), findsOneWidget);
      expect(find.text('Thimphu'), findsOneWidget);
      expect(find.text('Paro'), findsOneWidget);
      expect(find.text('Use my location'), findsOneWidget);
      // Every kind of service under it, all told.
      expect(find.text('What are you'), findsOneWidget);
      expect(find.text('3 places'), findsOneWidget);
      expect(find.text('1 place'), findsOneWidget);
      expect(find.text('Coming soon'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('in Olakha: "in Thimphu?", Olakha chosen, each kind counted there', (tester) async {
      await open(tester, const Size(1440, 900), withPlaces(here: const LatLng(27.4400, 89.6560)));
      expect(find.text('Thimphu?'), findsOneWidget);
      for (final area in ['All of Thimphu', 'Changzamtog', 'Olakha', 'More places']) {
        expect(find.text(area), findsOneWidget, reason: area);
      }
      expect(find.text('Bondey'), findsNothing, reason: "Paro's areas wait under More places");
      expect(find.text('Use my location'), findsNothing);
      expect(find.text('1 place in Olakha'), findsOneWidget);
      expect(find.text('None in Olakha · 1 elsewhere'), findsOneWidget);
    });

    testWidgets('in Bumthang, with no places yet: "in Bumthang?", and none there', (tester) async {
      await open(tester, const Size(1440, 900), withPlaces(here: const LatLng(27.549, 90.752)));
      expect(find.text('Bumthang?'), findsOneWidget);
      expect(find.text('All of Bumthang'), findsOneWidget);
      expect(find.text('None in Bumthang · 3 elsewhere'), findsOneWidget);
    });

    testWidgets('choosing an area counts each kind there, and Find services starts in it', (tester) async {
      await open(tester, const Size(1440, 900), withPlaces());
      await tester.tap(find.text('Thimphu'));
      await tester.pump();
      expect(find.text('Thimphu?'), findsOneWidget);
      expect(find.text('2 places in Thimphu'), findsOneWidget);
      await tester.tap(find.text('Olakha'));
      await tester.pump();
      expect(find.text('1 place in Olakha'), findsOneWidget);
      expect(find.text('None in Olakha · 1 elsewhere'), findsOneWidget);
      final container = ProviderScope.containerOf(tester.element(find.byType(GymWelcomePage)));
      expect(container.read(servicesAreaProvider), (dzongkhag: 'Thimphu', town: 'Olakha'));
    });

    testWidgets("bhutanesports.org's motion: the kinds run along a band, and what it has counts up", (tester) async {
      await open(tester, const Size(1440, 900), withPlaces());
      expect(find.text('GYM'), findsWidgets);
      expect(find.text('SWIMMING POOL'), findsWidgets);
      // The number over each label, once its section has come into view.
      String counted(String label) => tester
          .widget<Text>(find
              .descendant(
                  of: find.ancestor(of: find.text(label), matching: find.byType(Column)).first,
                  matching: find.byType(Text))
              .first)
          .data!;
      await tester.ensureVisible(find.text('What are you'));
      await tester.pump(); // it comes into view, and starts counting
      await tester.pump(const Duration(seconds: 2));
      expect(counted('PLACES'), '4');
      expect(counted('KINDS OF SERVICE'), '2');
      expect(counted('DZONGKHAGS'), '2');
    });

    for (final MapEntry(key: name, value: size)
        in const {'phone': Size(390, 844), 'tablet': Size(820, 1180), 'computer': Size(1440, 900)}.entries) {
      testWidgets('with places it still fits a $name', (tester) async {
        await open(tester, size, withPlaces(here: const LatLng(27.4400, 89.6560)));
        expect(tester.takeException(), isNull);
        expect(find.text('Where are you'), findsOneWidget);
      });
    }
  });

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

  testWidgets('no animated what-it-does panel: the user took it out', (tester) async {
    await show(tester, sizes['computer']!);
    expect(find.text('Membership Management'), findsNothing);
  });

  testWidgets('it claims no member counts, ratings or prices', (tester) async {
    await show(tester, sizes['computer']!);
    for (final madeUp in ['10K+', '10,000', '4.8', 'Nu ', 'Rated']) {
      expect(find.textContaining(madeUp), findsNothing, reason: madeUp);
    }
  });
}
