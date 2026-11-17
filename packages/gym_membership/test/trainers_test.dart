import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_membership/gym_membership.dart';
import 'package:gym_membership/src/data/joining.dart';
import 'package:gym_membership/src/data/trainers.dart';
import 'package:gym_membership/src/screens/add_trainer_screen.dart';
import 'package:gym_membership/src/screens/check_in_screen.dart';
import 'package:gym_membership/src/screens/gym_trainer_screens.dart';
import 'package:gym_membership/src/screens/my_gyms_screen.dart';
import 'package:gym_membership/src/screens/trainer_screens.dart';
import 'package:gym_membership/src/widgets/trainer_widgets.dart';
import 'package:health_pro_core/health_pro_core.dart';

import 'gym_navigation_test.dart' as nav show gymId, inMenu, openGym, owner, person, showApp;
import 'gym_screens_test.dart' show day, overrides, show;

// Trainers: verified by each gym, their week, attendance taken at the desk,
// members choosing them, reviews (the database side:
// tests/database/trainers_test.sql).

const tandin = TrainerProfile(
  userId: 't1',
  name: 'Tandin Wangchuk',
  headline: 'Strength and conditioning coach',
  experienceYears: 6,
  ratingAverage: 4.5,
  ratingCount: 2,
);

GymTrainer gymTrainer({String status = 'verified', String source = 'request'}) => GymTrainer.fromJson({
      'user_id': 't1',
      'status': status,
      'source': source,
      'email': 'tandin@x.bt',
      'phone': '+97517100004',
      'message': 'Mornings and evenings',
      'requested_at': '2026-11-10T00:00:00Z',
      'profile': {'user_id': 't1', 'display_name': 'Tandin Wangchuk', 'headline': 'Strength coach', 'rating_count': 0},
      'certificates': [
        {'id': 'c1', 'title': 'NSCA CSCS', 'issuer': 'NSCA', 'issued_on': '2020-05-01', 'file_url': 'https://x/cscs.pdf'},
      ],
      'slots': [
        {'weekday': 1, 'starts': '11:00', 'ends': '12:00', 'here': true},
        {'weekday': 1, 'starts': '14:00', 'ends': '15:00', 'here': false},
      ],
      'attendance': ['2026-11-14T02:00:00Z', '2026-11-13T02:00:00Z', '2026-11-12T02:00:00Z'],
      'attendance_30_days': 3,
      'members': 4,
    });

class _ArrivalRepo extends Fake implements GymRepository {
  final bool alsoMember;

  _ArrivalRepo({this.alsoMember = false});

  @override
  Future<CheckInOutcome> checkIn(String venueId, MemberRef member, {bool asMember = false}) async => TrainerArrival(
        name: 'Tandin Wangchuk',
        trainerId: 't1',
        slotsToday: const [OpenPeriod(660, 720)],
        alsoMember: alsoMember,
        personToken: member.cardToken,
      );
}

void main() {
  test("a gym's view of a trainer: its times, the others only 'here: false'", () {
    final t = gymTrainer();
    expect(t.slots.where((s) => s.here).single.time, '11 am–12 pm');
    expect(t.slots.where((s) => !s.here).single.venueName, isNull);
    expect(t.attendance30Days, 3);
    expect(slotsText(t.slots), 'Mon 11 am–12 pm, Mon 2–3 pm');
  });

  test("the trainer's own, gym by gym", () {
    final mine = MyTraining.fromJson({
      'profile': {'user_id': 't1', 'display_name': 'Tandin Wangchuk'},
      'certificates': [],
      'gyms': [
        {'venue_id': 'z', 'venue_name': 'Zeta Gym', 'status': 'verified', 'attendance': ['2026-11-14T02:00:00Z'],
         'attendance_30_days': 1, 'members': [{'name': 'Meto Lhamo', 'since': '2026-11-01T00:00:00Z'}]},
        {'venue_id': 'e', 'venue_name': 'Eta Gym', 'status': 'pending'},
      ],
      'reviews': [],
    });
    expect(mine.gyms.first.members.single.name, 'Meto Lhamo');
    expect(mine.gyms.last.status, TrainerStatus.pending);
    expect(MyTraining.fromJson({'profile': null}).profile, isNull);
  });

  testWidgets("Check-in: a trainer's QR code records their arrival, with their times today", (tester) async {
    await show(tester, const CheckInScreen(venueId: 'g1'),
        with_: [...overrides(), gymRepositoryProvider.overrideWithValue(_ArrivalRepo(alsoMember: true))]);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.enterText(find.byType(TextField), 'healthpro:member:0123456789abcdef0123456789abcdef');
    await tester.tap(find.text('Check in'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('TRAINER ARRIVED'), findsOneWidget);
    expect(find.text('Tandin Wangchuk'), findsOneWidget);
    expect(find.text('Here today: 11 am–12 pm'), findsOneWidget);
    expect(find.text("They're here to work out: check in as a member"), findsOneWidget, reason: 'a member here too');
  });

  testWidgets('Trainers: one asking (certificates to check), and ours with their week and attendance here', (tester) async {
    for (final size in [const Size(1440, 1000), const Size(390, 844)]) {
      await show(tester, const GymTrainersScreen(venueId: 'g1'), size: size, with_: [
        ...overrides(),
        gymTrainersProvider.overrideWith((ref, id) async => [gymTrainer(status: 'pending'), gymTrainer()]),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Asking to train here (1)'), findsOneWidget);
      expect(find.textContaining('NSCA CSCS'), findsOneWidget);
      expect(find.text('Verify'), findsOneWidget);
      expect(find.text("Don't verify"), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Our trainers (1)'), 300, scrollable: find.byType(Scrollable).first);
      await tester.scrollUntilVisible(find.text('Days attended'), 300, scrollable: find.byType(Scrollable).first);
      expect(find.text('2 pm–3 pm · Not available').evaluate().isNotEmpty || find.text('2–3 pm · Not available').evaluate().isNotEmpty,
          isTrue, reason: 'their time at another gym, unnamed');
      expect(find.text('Days attended'), findsOneWidget);
      expect(find.text('Add trainer'), findsOneWidget, reason: 'the gym can add one itself');
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('...one the gym added: so marked, with how to reach them, their times to change and arrival to mark',
      (tester) async {
    await show(tester, const GymTrainersScreen(venueId: 'g1'), size: const Size(1440, 1000), with_: [
      ...overrides(),
      gymTrainersProvider.overrideWith((ref, id) async => [gymTrainer(source: 'gym')]),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Added by the gym'), findsOneWidget);
    expect(find.text('+97517100004'), findsOneWidget);
    expect(find.text('tandin@x.bt'), findsOneWidget);
    expect(find.text('Change times'), findsOneWidget);
    expect(find.text('Mark arrived'), findsOneWidget);
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    expect(find.text('Make inactive'), findsOneWidget, reason: 'in the card\'s menu');
    expect(tester.takeException(), isNull);
  });

  test('a trainer the gym adds: what the database gets', () {
    final json = NewTrainer(
      name: ' Xi Trainer ',
      email: 'xi@x.bt',
      specialties: const ['Yoga'],
      experienceYears: 3,
      certificates: [NewCertificate(title: 'RYT 200', issuer: 'Yoga Alliance', issuedOn: DateTime(2022, 3, 1))],
      slots: const [TrainerSlot(weekday: 2, starts: 420, ends: 540)],
    ).toJson(photoUrl: 'https://x/p.jpg', certificateUrls: const ['https://x/c.jpg']);
    expect(json['display_name'], 'Xi Trainer');
    expect(json['photo_url'], 'https://x/p.jpg');
    expect((json['certificates'] as List).single,
        {'title': 'RYT 200', 'issuer': 'Yoga Alliance', 'issued_on': '2022-03-01', 'file_url': 'https://x/c.jpg'});
    expect((json['slots'] as List).single, {'weekday': 2, 'starts': '07:00', 'ends': '09:00'});
  });

  testWidgets('Add a trainer: all their details, as a registration; name and email are needed', (tester) async {
    for (final size in [const Size(1440, 1000), const Size(390, 844)]) {
      await show(tester, const AddTrainerScreen(venueId: 'g1'), size: size, with_: overrides());
      await tester.pumpAndSettle();
      expect(find.text('Who they are'), findsOneWidget);
      expect(find.text('Full name *'), findsOneWidget);
      expect(find.text('Email *'), findsOneWidget);
      await tester.tap(find.text('Add trainer'));
      await tester.pumpAndSettle();
      expect(find.text('Enter their name'), findsOneWidget, reason: 'nothing saved without them');
      expect(find.text('Email is required'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Certificates'), 300, scrollable: find.byType(Scrollable).first);
      await tester.scrollUntilVisible(find.text('No times set yet.'), 300, scrollable: find.byType(Scrollable).first);
      expect(find.textContaining('Their week at'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  group("On a gym's page, for trainers", () {
    final gym = Venue(
        id: 'g1', type: 'gym', name: 'Peak Fitness', dzongkhag: 'Thimphu', verificationStatus: 'verified', createdAt: DateTime(2026));
    Future<void> showCard(WidgetTester tester, {String? user = 'u1', MyTraining mine = const MyTraining()}) async {
      await show(tester, Scaffold(body: TrainHereCard(gym: gym)), size: const Size(390, 844), with_: [
        ...overrides(),
        currentUserIdProvider.overrideWithValue(user),
        myTrainingProvider.overrideWith((ref) async => mine),
      ]);
      await tester.pumpAndSettle();
    }

    testWidgets('a visitor signs in first', (tester) async {
      await showCard(tester, user: null);
      expect(find.text('Are you a trainer?'), findsOneWidget);
      expect(find.text('Sign in to apply as a trainer'), findsOneWidget);
    });

    testWidgets('someone with no trainer profile makes one on the way', (tester) async {
      await showCard(tester);
      expect(find.text('Apply as a trainer'), findsOneWidget);
    });

    testWidgets('a trainer applies; one who asked waits; one who trains here goes to their page', (tester) async {
      await showCard(tester, mine: const MyTraining(profile: tandin));
      expect(find.text('Apply to train here'), findsOneWidget);
      await showCard(tester, mine: const MyTraining(profile: tandin, gyms: [
        MyTrainerGym(venueId: 'g1', venueName: 'Peak Fitness', place: 'Thimphu', status: TrainerStatus.pending),
      ]));
      expect(find.textContaining('Your application is with Peak Fitness'), findsOneWidget);
      await showCard(tester, mine: const MyTraining(profile: tandin, gyms: [
        MyTrainerGym(venueId: 'g1', venueName: 'Peak Fitness', place: 'Thimphu', status: TrainerStatus.verified),
      ]));
      expect(find.text("You're a trainer here"), findsOneWidget);
      expect(find.text('My times and members'), findsOneWidget);
    });
  });

  testWidgets("a trainer's own page: each gym, its standing, times and attendance", (tester) async {
    final mine = MyTraining(
      profile: tandin,
      gyms: [
        MyTrainerGym(
          venueId: 'z',
          venueName: 'Zeta Gym',
          place: 'Thimphu',
          status: TrainerStatus.verified,
          slots: const [TrainerSlot(weekday: 1, starts: 660, ends: 720)],
          attendance: [DateTime.utc(2026, 11, 14, 2)],
          attendance30Days: 1,
          members: [(name: 'Meto Lhamo', since: DateTime.utc(2026, 11, 1))],
        ),
        const MyTrainerGym(venueId: 'e', venueName: 'Eta Gym', place: 'Paro', status: TrainerStatus.pending),
      ],
    );
    for (final size in [const Size(1440, 1000), const Size(390, 844)]) {
      await show(tester, const TrainerHomeScreen(), size: size,
          with_: [...overrides(), myTrainingProvider.overrideWith((ref) async => mine)]);
      await tester.pumpAndSettle();
      expect(find.text('Tandin Wangchuk'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Eta Gym'), 300, scrollable: find.byType(Scrollable).first);
      expect(find.text('Zeta Gym'), findsOneWidget);
      expect(find.text('Waiting to be checked'), findsOneWidget);
      expect(find.text('Meto Lhamo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets("not a trainer yet: they apply from a gym's page", (tester) async {
    await show(tester, const TrainerHomeScreen(),
        with_: [...overrides(), myTrainingProvider.overrideWith((ref) async => const MyTraining())]);
    await tester.pumpAndSettle();
    expect(find.text('No trainer profile yet'), findsOneWidget);
    expect(find.textContaining('apply as a trainer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a trainer\'s public profile, seen from a gym: other gyms only Not available', (tester) async {
    await show(tester, const TrainerPublicScreen(trainerId: 't1', venueId: 'g1'), size: const Size(390, 844), with_: [
      ...overrides(),
      currentUserIdProvider.overrideWithValue('u1'),
      trainerProfileProvider.overrideWith((ref, id) async => tandin),
      trainerCertificatesProvider.overrideWith((ref, id) async => [TrainerCertificate(id: 'c1', title: 'NSCA CSCS', issuedOn: day(-900))]),
      trainerGymsProvider.overrideWith((ref, id) async => [(id: 'g1', name: 'Peak Fitness', place: 'Thimphu')]),
      trainerTimingsProvider.overrideWith((ref, q) async => const [
            TrainerSlot(weekday: 1, starts: 660, ends: 720, venueId: 'g1', venueName: 'Peak Fitness'),
            TrainerSlot(weekday: 1, starts: 840, ends: 900, here: false),
          ]),
      trainerReviewsProvider.overrideWith((ref, id) async => const <TrainerReview>[]),
      canReviewTrainerProvider.overrideWith((ref, id) async => true),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Strength and conditioning coach'), findsOneWidget);
    expect(find.text('NSCA CSCS'), findsOneWidget);
    expect(find.text('Write a review'), findsOneWidget, reason: 'she trained with him');
    await tester.scrollUntilVisible(find.text('2–3 pm · Not available'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('2–3 pm · Not available'), findsOneWidget);
    expect(find.text('11 am–12 pm'), findsOneWidget, reason: 'here, without the gym named again');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a member chooses their trainer', (tester) async {
    final mine = MyMemberships(gyms: [
      MyGym(venueId: 'g1', venueName: 'Peak Fitness', place: 'Thimphu', gymMemberId: 'm1', startDate: day(-5), endDate: day(25)),
    ]);
    await show(tester, const ChooseTrainerScreen(venueId: 'g1'), size: const Size(390, 844), with_: [
      ...overrides(),
      myMembershipsProvider.overrideWith((ref) async => mine),
      gymVerifiedTrainersProvider.overrideWith((ref, id) async => [tandin]),
      trainerTimingsProvider.overrideWith((ref, q) async => const [TrainerSlot(weekday: 3, starts: 360, ends: 480)]),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Tandin Wangchuk'), findsOneWidget);
    expect(find.text('Here: Wed 6–8 am'), findsOneWidget);
    expect(find.text('Choose Tandin'), findsOneWidget);
  });

  testWidgets('the desk: a member with no trainer yet, and one to assign', (tester) async {
    await show(
      tester,
      const Scaffold(body: MemberTrainerPicker(venueId: 'g1', gymMemberId: 'm1', canChange: true)),
      with_: [
        ...overrides(),
        gymVerifiedTrainersProvider.overrideWith((ref, id) async => [tandin]),
        memberTrainerProvider.overrideWith((ref, id) async => null),
      ],
    );
    await tester.pumpAndSettle();
    expect(find.text('No trainer yet'), findsOneWidget);
    await tester.tap(find.text('Assign a trainer'));
    await tester.pumpAndSettle();
    expect(find.text('Tandin Wangchuk'), findsOneWidget);
  });

  testWidgets('the menu: Trainers for the owner, with those waiting; Trainer profile under Me for a trainer', (tester) async {
    await nav.showApp(tester, const Size(1440, 1000), [
      ...nav.person(gyms: nav.owner),
      gymTrainersProvider.overrideWith((ref, id) async => [gymTrainer(status: 'pending')]),
      myTrainingProvider.overrideWith((ref) async => const MyTraining(profile: tandin, joinedPublicly: true)),
    ], at: '/gyms/${nav.gymId}/manage');
    await nav.openGym(tester);
    expect(nav.inMenu('Trainers'), findsOneWidget);
    expect(nav.inMenu('Trainer profile'), findsOneWidget);
  });

  testWidgets('the menu: no trainer page for someone without a trainer profile', (tester) async {
    await nav.showApp(tester, const Size(1440, 1000), [
      ...nav.person(gyms: nav.owner),
      gymTrainersProvider.overrideWith((ref, id) async => const <GymTrainer>[]),
      myTrainingProvider.overrideWith((ref) async => const MyTraining()),
    ], at: '/gyms/${nav.gymId}/manage');
    expect(nav.inMenu('Trainer profile'), findsNothing);
    expect(nav.inMenu('My training'), findsNothing);
  });
}
