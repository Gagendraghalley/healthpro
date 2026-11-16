import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_membership/gym_membership.dart';
import 'package:gym_membership/src/data/joining.dart';
import 'package:gym_membership/src/data/trainers.dart';
import 'package:gym_membership/src/screens/check_in_screen.dart';
import 'package:gym_membership/src/screens/join_screens.dart';
import 'package:gym_membership/src/screens/members_screens.dart';
import 'package:gym_membership/src/screens/my_gyms_screen.dart';
import 'package:health_pro_core/health_pro_core.dart';

import 'gym_screens_test.dart' show day, gym, overrides, plans, show;

// One QR code per person at every gym, and joining a gym by its QR code
// (the database side: tests/database/people_test.sql).

const sonamQr = '0123456789abcdef0123456789abcdef';

class _FakeRepo extends Fake implements GymRepository {
  @override
  Future<CheckInResult> checkIn(String venueId, MemberRef member, {bool asMember = false}) async =>
      throw NotMemberHere(name: 'Sonam Choden', personToken: member.cardToken);
}

final _sonam = PersonDetails.fromJson({
  'person_id': 'p1',
  'full_name': 'Sonam Choden',
  'details': {'full_name': 'Sonam Choden', 'phone': '+97517700777', 'email': 'sonam@x.bt', 'blood_group': 'O+'},
  'plan_id': 'p2',
  'message': 'Mornings, please',
});

MyMemberships _mine({bool member = false, bool waiting = false}) => MyMemberships(
      gyms: [
        if (member)
          MyGym(venueId: 'g1', venueName: 'Peak Fitness', place: 'Thimphu', planName: 'Gym', startDate: day(-5), endDate: day(25)),
      ],
      requests: [
        if (waiting)
          MyJoinRequest(
            id: 'r1',
            venueId: 'g1',
            venueName: 'Peak Fitness',
            status: JoinRequestStatus.pending,
            createdAt: DateTime.now().toUtc(),
          ),
      ],
    );

void main() {
  test('a member\'s gyms, requests and visits, from my_gyms()', () {
    final m = MyMemberships.fromJson({
      'gyms': [
        {
          'venue_id': 'g1', 'venue_name': 'Alpha Gym', 'dzongkhag': 'Thimphu', 'town': 'Changzamtog',
          'member_code': '4K7P9Q', 'plan_name': 'Monthly', 'start_date': '2026-11-01', 'end_date': '2026-12-01',
          'last_visit': '2026-11-14T02:00:00Z',
        },
        {'venue_id': 'g2', 'venue_name': 'Beta Gym', 'dzongkhag': 'Paro'},
      ],
      'requests': [
        {'id': 'r1', 'venue_id': 'g3', 'venue_name': 'Gamma Gym', 'status': 'pending', 'created_at': '2026-11-15T00:00:00Z'},
      ],
      'visits': [
        {'venue_name': 'Alpha Gym', 'checked_in_at': '2026-11-14T02:00:00Z'},
      ],
    });
    expect(m.gyms.first.place, 'Changzamtog, Thimphu');
    expect(m.gyms.first.isActiveOn(DateTime(2026, 12, 1)), isTrue, reason: 'valid on its end date');
    expect(m.gyms.first.hasEndedBy(DateTime(2026, 12, 2)), isTrue);
    expect(m.at('g2')!.endDate, isNull, reason: 'registered, no package yet');
    expect(m.waitingAt('g3')!.id, 'r1');
    expect(m.waitingAt('g1'), isNull);
    expect(m.visits.single.gym, 'Alpha Gym');
  });

  testWidgets("Check-in: someone on Health Pro who isn't a member here: the desk adds them", (tester) async {
    await show(tester, const CheckInScreen(venueId: 'g1'),
        with_: [...overrides(), gymRepositoryProvider.overrideWithValue(_FakeRepo())]);
    await tester.pump(const Duration(milliseconds: 500));
    // A USB scanner types the QR code into the box.
    await tester.enterText(find.byType(TextField), 'healthpro:member:$sonamQr');
    await tester.tap(find.text('Check in'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Not a member here yet'), findsOneWidget);
    expect(find.text('Sonam Choden'), findsOneWidget);
    expect(find.text('Add to this gym'), findsOneWidget);
  });

  testWidgets('...the front desk without registering can only say who to ask', (tester) async {
    await show(tester, const CheckInScreen(venueId: 'g1'), with_: [
      ...overrides(),
      // Checks members in, doesn't register them.
      venueAccessProvider.overrideWith((ref, id) async => VenueAccess(gym, 'door', permissions: {GymPermission.checkIn})),
      gymRepositoryProvider.overrideWithValue(_FakeRepo()),
    ]);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.enterText(find.byType(TextField), 'healthpro:member:$sonamQr');
    await tester.tap(find.text('Check in'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Not a member here yet'), findsOneWidget);
    expect(find.text('Add to this gym'), findsNothing);
  });

  testWidgets('Register member for someone on Health Pro: filled in, with the package they asked for', (tester) async {
    await show(
      tester,
      const RegisterMemberScreen(venueId: 'g1', requestId: 'r1'),
      with_: [
        ...overrides(),
        dzongkhagsProvider.overrideWith((ref) async => const <LocationItem>[]),
        gymPersonDetailsProvider.overrideWith((ref, q) async => _sonam),
      ],
    );
    await tester.pumpAndSettle();
    expect(find.text('Add Sonam Choden'), findsOneWidget);
    expect(find.text('Sonam Choden asked to join'), findsOneWidget);
    expect(find.text('"Mornings, please"'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Sonam Choden'), findsOneWidget, reason: 'their name, filled in');
    expect(find.widgetWithText(TextFormField, '+97517700777'), findsOneWidget, reason: 'their phone');
    expect(find.textContaining('Gym + Aerobics'), findsWidgets, reason: 'the package they asked for, chosen');
    expect(tester.takeException(), isNull);
  });

  testWidgets('...and someone registered here already: their page instead', (tester) async {
    final here = PersonDetails.fromJson({'person_id': 'p1', 'full_name': 'Sonam Choden', 'details': {}, 'gym_member_id': 'm1'});
    await show(tester, const RegisterMemberScreen(venueId: 'g1', personQr: sonamQr),
        with_: [...overrides(), gymPersonDetailsProvider.overrideWith((ref, q) async => here)]);
    await tester.pumpAndSettle();
    expect(find.text('Sonam Choden is a member here already'), findsOneWidget);
    expect(find.text('Open their page'), findsOneWidget);
  });

  testWidgets('Join requests: who is waiting, what they want; and what was answered', (tester) async {
    final requests = [
      JoinRequest.fromJson({
        'id': 'r1', 'venue_id': 'g1', 'status': 'pending', 'created_at': DateTime.now().toUtc().toIso8601String(),
        'message': 'Mornings, please', 'person': {'full_name': 'Sonam Choden', 'phone': '+97517700777'},
        'plan_id': 'p1', 'plan': {'name': 'Gym', 'price': 1500},
      }),
      JoinRequest.fromJson({
        'id': 'r2', 'venue_id': 'g1', 'status': 'declined', 'created_at': '2026-11-01T00:00:00Z',
        'decided_at': '2026-11-02T00:00:00Z', 'decision_note': 'Full until March', 'person': {'full_name': 'Tashi Lhamo'},
      }),
    ];
    for (final size in [const Size(1440, 1000), const Size(390, 844)]) {
      await show(tester, const JoinRequestsScreen(venueId: 'g1'),
          size: size, with_: [...overrides(), gymJoinRequestsProvider.overrideWith((ref, id) async => requests)]);
      await tester.pumpAndSettle();
      expect(find.text('Waiting (1)'), findsOneWidget);
      expect(find.text('Sonam Choden'), findsOneWidget);
      expect(find.text('Would like Gym (Nu. 1,500)'), findsOneWidget);
      expect(find.text('Add to gym'), findsOneWidget);
      expect(find.text('Decline'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Tashi Lhamo'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('Declined'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('The gym QR code: its page, to print', (tester) async {
    await show(tester, const GymQrScreen(venueId: 'g1'), size: const Size(390, 844), with_: overrides());
    await tester.pumpAndSettle();
    expect(find.text('Peak Fitness'), findsWidgets);
    expect(find.text('Scan to join this gym'), findsOneWidget);
    expect(find.text('Download to print'), findsOneWidget);
    expect(gymJoinLink('g1'), endsWith('#/gyms/g1?join=1'));
    expect(tester.takeException(), isNull);
  });

  group('Joining from the gym page', () {
    Future<void> showCard(WidgetTester tester, {String? user, MyMemberships? mine}) => show(
          tester,
          Scaffold(body: ListView(children: [JoinGymCard(gym: gym, plans: plans, highlight: true)])),
          size: const Size(390, 844),
          with_: [
            ...overrides(),
            currentUserIdProvider.overrideWithValue(user),
            myMembershipsProvider.overrideWith((ref) async => mine ?? MyMemberships.none),
          ],
        );

    testWidgets('a visitor signs in first', (tester) async {
      await showCard(tester);
      await tester.pumpAndSettle();
      expect(find.text('Join Peak Fitness'), findsOneWidget);
      expect(find.text('Sign in to ask to join'), findsOneWidget);
    });

    testWidgets('signed in: ask to join, with the package they would like', (tester) async {
      await showCard(tester, user: 'u1');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ask to join'));
      await tester.pumpAndSettle();
      expect(find.text('Ask to join Peak Fitness'), findsOneWidget);
      expect(find.text("Package you'd like (optional)"), findsOneWidget);
      expect(find.text('Send request'), findsOneWidget);
    });

    testWidgets('asked already: waiting, and can take it back', (tester) async {
      await showCard(tester, user: 'u1', mine: _mine(waiting: true));
      await tester.pumpAndSettle();
      expect(find.text('Request sent'), findsOneWidget);
      expect(find.text('Take my request back'), findsOneWidget);
    });

    testWidgets('a member: their membership, and their QR code', (tester) async {
      await showCard(tester, user: 'u1', mine: _mine(member: true));
      await tester.pumpAndSettle();
      expect(find.text('Your membership'), findsOneWidget);
      expect(find.textContaining("You're a member here, until"), findsOneWidget);
      expect(find.text('Show my QR code'), findsOneWidget);
    });
  });

  testWidgets('My gyms on the dashboard: how things stand, each gym with its package, requests', (tester) async {
    for (final size in [const Size(1440, 1000), const Size(390, 844)]) {
      await show(tester, const Scaffold(body: SingleChildScrollView(child: MyGymsDashboard())), size: size, with_: [
        ...overrides(),
        myMembershipsProvider.overrideWith((ref) async => _mine(member: true, waiting: true)),
      ]);
      await tester.pumpAndSettle();
      for (final label in ['My gyms', 'Active packages', 'Days left', 'Visits in 7 days']) {
        expect(find.text(label), findsWidgets, reason: label);
      }
      expect(find.text('1 request waiting'), findsOneWidget);
      expect(find.text('Peak Fitness'), findsWidgets);
      expect(find.text('Active until ${formatDate(day(25))}'), findsOneWidget);
      expect(find.text('26 days left'), findsOneWidget, reason: 'the last day counts');
      expect(find.text('Take back'), findsOneWidget, reason: 'their request elsewhere, waiting');
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('My gyms on the dashboard, with no gym yet: the way to find one', (tester) async {
    await show(tester, const Scaffold(body: SingleChildScrollView(child: MyGymsDashboard())), with_: [
      ...overrides(),
      myMembershipsProvider.overrideWith((ref) async => MyMemberships.none),
    ]);
    await tester.pumpAndSettle();
    expect(find.text("You're not a member of a gym yet"), findsOneWidget);
    expect(find.text('No active package'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('My gym: the gym in full (facilities, trainers) beside their membership there', (tester) async {
    for (final size in [const Size(1440, 1000), const Size(390, 844)]) {
      await show(tester, const MyGymScreen(), size: size, with_: [
        ...overrides(),
        venueProvider.overrideWith((ref, id) async => gym),
        gymVerifiedTrainersProvider.overrideWith((ref, id) async => const <TrainerProfile>[]),
        myMembershipsProvider.overrideWith((ref) async => _mine(member: true)),
      ]);
      await tester.pumpAndSettle();
      expect(find.text(gym.name), findsWidgets);
      for (final label in ['My membership', 'Facilities', 'Trainers']) {
        await tester.scrollUntilVisible(find.text(label), 200, scrollable: find.byType(Scrollable).first);
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('My gym, with no gym yet: how to join one', (tester) async {
    await show(tester, const MyGymScreen(), with_: [
      ...overrides(),
      myMembershipsProvider.overrideWith((ref) async => MyMemberships.none),
    ]);
    await tester.pumpAndSettle();
    expect(find.text("You're not a member of a gym yet"), findsOneWidget);
    expect(find.text('Find a gym'), findsWidgets, reason: 'the first step, and the button');
  });
}
