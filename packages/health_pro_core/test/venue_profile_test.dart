import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro_core/health_pro_core.dart';
import 'package:health_pro_core/src/venues/venue_profile_fields.dart';

// A venue's public profile: opening hours, facilities, videos, its place on
// the map (the database side: tests/database/profile_test.sql).

final week = OpeningHours.fromJson({
  'mon': [['06:00', '10:00'], ['16:00', '21:00']],
  'tue': [['06:00', '10:00'], ['16:00', '21:00']],
  'wed': [['06:00', '10:00'], ['16:00', '21:00']],
  'thu': [['06:00', '10:00'], ['16:00', '21:00']],
  'fri': [['06:00', '10:00'], ['16:00', '21:00']],
  'sat': [['07:00', '12:00']],
  'sun': [],
})!;

/// A Monday (17 Nov 2025) at [hour]:[minute], Bhutan time.
DateTime monday(int hour, [int minute = 0]) => DateTime(2025, 11, 17, hour, minute);

Future<void> pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(390, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: Scaffold(body: SingleChildScrollView(child: child))));
}

void main() {
  group('opening hours', () {
    test('read and written as the database keeps them', () {
      expect(week.on(1), const [OpenPeriod(360, 600), OpenPeriod(960, 1260)]);
      expect(week.on(7), isEmpty, reason: 'closed on Sunday');
      expect(OpeningHours.fromJson(week.toJson())!.days, week.days);
      expect(OpeningHours.fromJson(null), isNull);
    });

    test('the week in words, days with the same hours together', () {
      expect(week.summary(), [
        (days: 'Mon–Fri', hours: '6–10 am, 4–9 pm'),
        (days: 'Sat', hours: '7 am–12 pm'),
        (days: 'Sun', hours: 'Closed'),
      ]);
      expect(OpenPeriod.label(1440), 'midnight');
      expect(OpenPeriod.label(390), '6:30 am');
    });

    test('open now, until when; or when it opens next', () {
      expect(week.at(monday(7))!.label, 'Open now · until 10 am');
      expect(week.at(monday(12))!.label, 'Closed · opens 4 pm');
      expect(week.at(monday(22))!.label, 'Closed now');
      expect(week.at(monday(10))!.open, isFalse, reason: 'it closes at 10');
      expect(week.at(DateTime(2025, 11, 23, 9))!.label, 'Closed now', reason: 'Sunday');
      expect(const OpeningHours({1: [OpenPeriod(360, 600)]}).at(DateTime(2025, 11, 18, 9)), isNull, reason: 'Tuesday: not said');
    });
  });

  test('distances, as the crow flies', () {
    // Thimphu's clock tower to Paro airport: about 23 km.
    final km = distanceKm(27.4728, 89.6393, 27.4032, 89.4246);
    expect(km, closeTo(22.5, 2));
    expect(distanceText(0.84), '850 m');
    expect(distanceText(4.24), '4.2 km');
    expect(distanceText(38.4), '38 km');
  });

  test('video links: YouTube and Facebook only, with a YouTube picture', () {
    expect(isVideoLink('https://www.youtube.com/watch?v=abc123'), isTrue);
    expect(isVideoLink('https://fb.watch/xyz/'), isTrue);
    expect(isVideoLink('http://youtube.com/watch?v=abc'), isFalse, reason: 'https only');
    expect(isVideoLink('https://evil.example/v'), isFalse);
    expect(youTubeId('https://www.youtube.com/watch?v=abc123&t=4'), 'abc123');
    expect(youTubeId('https://youtu.be/xyz789'), 'xyz789');
    expect(youTubeId('https://www.youtube.com/shorts/sh0rt'), 'sh0rt');
    expect(youTubeId('https://fb.watch/xyz/'), isNull);
  });

  testWidgets('opening hours, on the form: added, a day closed, a break', (tester) async {
    OpeningHours? hours;
    await pump(
      tester,
      StatefulBuilder(builder: (context, setState) => OpeningHoursEditor(value: hours, onChanged: (v) => setState(() => hours = v))),
    );
    await tester.tap(find.text('Add opening hours'));
    await tester.pumpAndSettle();
    expect(hours!.on(1), const [OpenPeriod(360, 1260)], reason: 'Monday to Saturday 6 am to 9 pm to start with');
    expect(find.text('Closed'), findsOneWidget, reason: 'Sunday');

    await tester.tap(find.text('Add a break').first);
    await tester.pumpAndSettle();
    expect(hours!.on(1), const [OpenPeriod(360, 600), OpenPeriod(960, 1260)]);

    await tester.tap(find.byType(Switch).at(1));
    await tester.pumpAndSettle();
    expect(hours!.on(2), isEmpty, reason: 'Tuesday closed');
    expect(OpeningHoursEditor.valid(hours), isTrue);
    expect(OpeningHoursEditor.problem(const [OpenPeriod(600, 360)]), 'Closes before it opens');
    expect(tester.takeException(), isNull);
  });

  testWidgets('facilities: the usual ones as ticks, and their own', (tester) async {
    var list = <String>['Shower'];
    await pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) => FacilitiesEditor(
          value: list,
          suggestions: const ['Shower', 'Massage'],
          onChanged: (v) => setState(() => list = v),
        ),
      ),
    );
    await tester.tap(find.text('Massage'));
    await tester.pumpAndSettle();
    expect(list, ['Shower', 'Massage']);
    await tester.enterText(find.byType(TextField), '  Ice   bath ');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(list, ['Shower', 'Massage', 'Ice bath']);
    expect(find.text('Ice bath'), findsOneWidget);
  });

  testWidgets('videos: a link that isn\'t YouTube or Facebook is refused', (tester) async {
    var list = <String>[];
    await pump(
      tester,
      StatefulBuilder(builder: (context, setState) => VideoLinksEditor(value: list, onChanged: (v) => setState(() => list = v))),
    );
    await tester.enterText(find.byType(TextField), 'https://evil.example/v');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.textContaining('YouTube or Facebook video link'), findsOneWidget);
    expect(list, isEmpty);
    await tester.enterText(find.byType(TextField), 'https://youtu.be/xyz789');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(list, ['https://youtu.be/xyz789']);
  });

  testWidgets('the public page: open now, the week, and the map with Directions', (tester) async {
    MapTiles.showTiles = false;
    addTearDown(() => MapTiles.showTiles = true);
    await pump(
      tester,
      Column(children: [
        OpeningHoursView(hours: week, at: monday(7)),
        const FacilitiesView(facilities: ['Shower', 'Massage']),
        const VenueMap(latitude: 27.4728, longitude: 89.6390),
      ]),
    );
    await tester.pump();
    expect(find.text('Open now · until 10 am'), findsOneWidget);
    expect(find.text('Monday'), findsOneWidget);
    expect(find.text('6–10 am, 4–9 pm'), findsWidgets);
    expect(find.text('Massage'), findsOneWidget);
    expect(find.text('Directions'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
