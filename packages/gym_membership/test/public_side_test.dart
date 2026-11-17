import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_membership/gym_membership.dart';
import 'package:gym_membership/src/screens/public_screens.dart';
import 'package:health_pro_core/health_pro_core.dart';

import 'gym_screens_test.dart' show overrides, plans, show;

// The public side: the list of gyms (near me, prices, a budget) and a gym's
// page with its profile (the database side: tests/database/profile_test.sql).

Venue gymAt(String id, String name, {double? lat, double? lng, Map<String, dynamic> extra = const {}}) => Venue.fromJson({
      'id': id,
      'type': gymVenueType,
      'name': name,
      'dzongkhag': 'Thimphu',
      'verification_status': 'verified',
      'created_at': '2026-11-01T00:00:00Z',
      'latitude': lat,
      'longitude': lng,
      ...extra,
    });

// Near the clock tower, in Babesa, and in Paro.
final town = gymAt('a', 'Alpha Gym', lat: 27.4728, lng: 89.6393);
final babesa = gymAt('b', 'Babesa Fitness', lat: 27.4310, lng: 89.6520);
final paro = gymAt('c', 'Chhu Gym', lat: 27.4305, lng: 89.4133, extra: {'dzongkhag': 'Paro'});
final nowhere = gymAt('d', 'Druk Gym');
const prices = {'a': (low: 3000, high: 12000), 'b': (low: 1500, high: 6000), 'c': (low: 2000, high: 9000)};

void main() {
  group('arranging the list', () {
    final all = [town, babesa, paro, nowhere];
    List<String> names(Iterable<({Venue gym, ({int low, int high})? price, double? km})> rows) =>
        [for (final r in rows) r.gym.name];

    test('as it comes, unsorted by distance without a location', () {
      expect(names(arrangeGyms(all, prices: prices)), ['Alpha Gym', 'Babesa Fitness', 'Chhu Gym', 'Druk Gym']);
    });

    test('nearest first from where they stand, gyms with no place last', () {
      const nearBabesa = LatLng(27.4290, 89.6500);
      final rows = arrangeGyms(all, prices: prices, sort: GymSort.nearest, here: nearBabesa);
      expect(names(rows), ['Babesa Fitness', 'Alpha Gym', 'Chhu Gym', 'Druk Gym']);
      expect(rows.first.km, lessThan(1));
      expect(rows.last.km, isNull);
    });

    test('by price, either way; gyms without prices last', () {
      expect(names(arrangeGyms(all, prices: prices, sort: GymSort.cheapest)), ['Babesa Fitness', 'Chhu Gym', 'Alpha Gym', 'Druk Gym']);
      expect(names(arrangeGyms(all, prices: prices, sort: GymSort.dearest)), ['Alpha Gym', 'Chhu Gym', 'Babesa Fitness', 'Druk Gym']);
    });

    test('within a budget: a package at or under it', () {
      expect(names(arrangeGyms(all, prices: prices, budget: 2000)), ['Babesa Fitness', 'Chhu Gym']);
      expect(names(arrangeGyms(all, prices: prices, budget: 1000)), isEmpty);
    });

    test('in one dzongkhag', () {
      expect(names(arrangeGyms(all, prices: prices, dzongkhag: 'Paro')), ['Chhu Gym']);
    });

    test('price ranges in words', () {
      expect(priceRangeText(2000, 10000), 'Nu. 2,000 – 10,000');
      expect(priceRangeText(1500, 1500), 'Nu. 1,500');
    });
  });

  testWidgets('the list: each gym with its prices; Near me, sort and budget', (tester) async {
    for (final size in [const Size(1440, 1000), const Size(390, 844)]) {
      await show(tester, const GymListScreen(), size: size, with_: [
        ...overrides(),
        publicVenuesProvider.overrideWith((ref, q) async => [town, babesa, paro, nowhere]),
        gymPriceRangesProvider.overrideWith((ref) async => prices),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Near me'), findsOneWidget);
      expect(find.text('Sort: Suggested'), findsOneWidget);
      expect(find.text('Any budget'), findsOneWidget);
      expect(find.text('4 gyms'), findsOneWidget);
      expect(find.text('Nu. 1,500 – 6,000'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Prices at the desk'), 300, scrollable: find.byType(Scrollable).first);
      expect(find.text('Prices at the desk'), findsOneWidget, reason: 'a gym with no packages yet');
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('...a budget keeps to the gyms within it', (tester) async {
    await show(tester, const GymListScreen(), with_: [
      ...overrides(),
      publicVenuesProvider.overrideWith((ref, q) async => [town, babesa, paro, nowhere]),
      gymPriceRangesProvider.overrideWith((ref) async => prices),
    ]);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Any budget'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Up to Nu. 2,000').last);
    await tester.pumpAndSettle();
    expect(find.text('2 gyms · with a package up to Nu. 2,000'), findsOneWidget);
    expect(find.text('Alpha Gym'), findsNothing);
  });

  testWidgets("a gym's page: prices, contact, facilities, videos, hours and the map", (tester) async {
    MapTiles.showTiles = false;
    addTearDown(() => MapTiles.showTiles = true);
    final gym = gymAt('g1', 'Peak Fitness', lat: 27.4728, lng: 89.6393, extra: {
      'email': 'hello@peak.bt',
      'contact_person': 'Sonam Tobgay',
      'facilities': ['Shower', 'Massage'],
      'videos': ['https://www.youtube.com/watch?v=abc123'],
      'opening_hours': {'mon': [['06:00', '21:00']], 'sun': []},
    });
    for (final size in [const Size(1440, 1000), const Size(390, 844)]) {
      await show(tester, const GymDetailsScreen(venueId: 'g1'), size: size, with_: [
        ...overrides(),
        venueProvider.overrideWith((ref, id) async => gym),
        currentUserIdProvider.overrideWithValue(null),
        venueReviewsProvider.overrideWith((ref, id) async => const <VenueReview>[]),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Nu. 1,500 – 2,200'), findsOneWidget, reason: 'from its packages on sale');
      expect(find.byTooltip('All gyms'), findsOneWidget, reason: 'opened straight, back leads to the list of gyms');
      expect(find.text('Ask for Sonam Tobgay'), findsOneWidget);
      expect(find.text('hello@peak.bt'), findsOneWidget);
      for (final heading in ['Facilities', 'Videos', 'Opening hours', 'Where it is']) {
        await tester.scrollUntilVisible(find.text(heading), 300, scrollable: find.byType(Scrollable).first);
        expect(find.text(heading), findsOneWidget, reason: heading);
      }
      expect(tester.takeException(), isNull);
    }
  });

  test('the gym form offers the usual facilities', () {
    final kind = const GymModule().venueKinds.single;
    expect(kind.facilities, containsAll(['Shower', 'Massage']));
    expect(plans, isNotEmpty);
  });
}
