import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_membership/src/data/classes.dart';
import 'package:gym_membership/src/data/coaching.dart';
import 'package:gym_membership/src/screens/classes_screen.dart';
import 'package:gym_membership/src/screens/trainer_members_screen.dart';
import 'package:gym_membership/src/widgets/class_widgets.dart';
import 'package:gym_membership/src/widgets/coaching_widgets.dart';
import 'package:health_pro_core/health_pro_core.dart';

import 'gym_screens_test.dart' show day, inDialog, overrides, show;

// Body progress, workout and diet plans, and group classes (the database
// side: tests/database/coaching_test.sql).

BodyMeasurement measured(String id, int daysAgo, {double? weight, double? height, double? waist, String? by}) => BodyMeasurement(
      id: id,
      gymMemberId: 'm1',
      measuredOn: day(-daysAgo),
      weightKg: weight,
      heightCm: height,
      waistCm: waist,
      recordedBy: by,
      recordedByName: by == null ? null : 'Tashi Trainer',
      createdAt: DateTime.utc(2026, 1, 1),
    );

GymClass yoga({int? weekday, int hour = 7, int capacity = 2, bool active = true}) => GymClass(
      id: 'yoga',
      venueId: 'g1',
      name: 'Yoga',
      trainerName: 'Tashi',
      weekday: weekday ?? day(1).weekday,
      hour: hour,
      minute: 0,
      durationMinutes: 60,
      capacity: capacity,
      isActive: active,
    );

Future<void> pump(WidgetTester tester, Widget child, List<Override> with_) async {
  tester.view.physicalSize = const Size(1200, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: with_,
    child: MaterialApp(theme: AppTheme.light, home: Scaffold(body: SingleChildScrollView(child: child))),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('progress', () {
    test('weight now, the change since the first, and BMI from the latest height', () {
      final s = ProgressSummary.of([
        measured('c', 0, weight: 68.5),
        measured('b', 10, height: 172),
        measured('a', 30, weight: 71),
      ]);
      expect(s.weightNow, 68.5);
      expect(s.change, -2.5);
      expect(s.firstOn, day(-30));
      expect(s.bmi!.toStringAsFixed(1), '23.2');
      expect(bmiBand(s.bmi!), 'Healthy weight');
      expect(bmiBand(17), 'Underweight');
      expect(bmiBand(27), 'Overweight');
      expect(bmiBand(31), 'Obese');
      expect(ProgressSummary.of([measured('a', 0, weight: 70)]).change, isNull, reason: 'one weighing: no change yet');
    });

    test('a measurement in words, and as the database takes it', () {
      final m = measured('a', 0, weight: 70, height: 172.5, waist: 80);
      expect(m.others, 'Height 172.5 cm · Waist 80 cm');
      expect(m.toJson()['weight_kg'], 70);
      expect(m.toJson()['chest_cm'], isNull);
      expect(kgText(70.25), '70.3 kg');
    });

    testWidgets('the member sees their progress and logs their weight; changes only their own', (tester) async {
      await pump(tester, const MemberProgress(gymMemberId: 'm1', self: true), [
        myProfileProvider.overrideWith((ref) async => Profile.fromJson({'id': 'me', 'full_name': 'Mindu Dema'})),
        memberMeasurementsProvider.overrideWith((ref, id) async => [
              measured('c', 0, weight: 68.5, by: 'me'),
              measured('b', 10, height: 172, by: 'trainer'),
              measured('a', 30, weight: 71, by: 'trainer'),
            ]),
      ]);
      expect(find.text('68.5 kg'), findsWidgets);
      expect(find.text('−2.5 kg'), findsOneWidget);
      expect(find.text('Healthy weight'), findsOneWidget);
      expect(find.text('Log my weight'), findsOneWidget);
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget, reason: 'only their own can be changed');
      expect(tester.takeException(), isNull);
    });
  });

  group('plans', () {
    final plans = [
      MemberPlan(
          id: 'p1',
          gymMemberId: 'm1',
          kind: PlanKind.workout,
          title: 'Strength, 3 days',
          content: 'Day 1: squats 4 x 8',
          authorName: 'Tashi',
          updatedAt: DateTime.utc(2026, 11, 10)),
      MemberPlan(
          id: 'p2',
          gymMemberId: 'm1',
          kind: PlanKind.diet,
          title: 'Old diet',
          content: 'Rice',
          isActive: false,
          updatedAt: DateTime.utc(2026, 10, 1)),
    ];

    testWidgets('the member reads theirs; earlier ones folded away', (tester) async {
      await pump(tester, const MemberPlans(gymMemberId: 'm1'), [memberPlansProvider.overrideWith((ref, id) async => plans)]);
      expect(find.text('Strength, 3 days'), findsOneWidget);
      expect(find.text('Earlier plans (1)'), findsOneWidget);
      expect(find.text('Give a plan'), findsNothing);
      await tester.tap(find.text('Strength, 3 days'));
      await tester.pumpAndSettle();
      expect(find.text('Day 1: squats 4 x 8'), findsOneWidget);
      expect(find.text('Change'), findsNothing, reason: 'members don\'t change plans');
    });

    testWidgets('their trainer gives and changes them', (tester) async {
      await pump(tester, const MemberPlans(gymMemberId: 'm1', coach: true), [memberPlansProvider.overrideWith((ref, id) async => plans)]);
      expect(find.text('Give a plan'), findsOneWidget);
      await tester.tap(find.text('Strength, 3 days'));
      await tester.pumpAndSettle();
      expect(find.text('Change'), findsOneWidget);
      expect(find.text('Put away'), findsOneWidget);
    });

    testWidgets('a trainer\'s members, gym by gym', (tester) async {
      await show(tester, const TrainerMembersScreen(), with_: [
        trainerMembersProvider.overrideWith((ref) async => [
              TrainerMember(
                gymMemberId: 'm1',
                venueId: 'g1',
                venueName: 'Peak Fitness',
                fullName: 'Mindu Dema',
                code: 'ABC234',
                phone: '+97517700001',
                since: DateTime.utc(2026, 11, 1),
                paidUntil: day(20),
                latestWeight: 69.5,
                activePlans: 1,
              ),
            ]),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Peak Fitness'), findsOneWidget);
      expect(find.text('Mindu Dema'), findsOneWidget);
      expect(find.textContaining('69.5 kg · 1 plan'), findsOneWidget);
    });
  });

  group('classes', () {
    test('times, and when a class runs', () {
      expect(clockTime(0, 5), '12:05 AM');
      expect(clockTime(12, 0), '12:00 PM');
      expect(clockTime(18, 30), '6:30 PM');
      expect(yoga().span, '7:00 AM to 8:00 AM');
    });

    test('the week\'s sessions, in time order, with places and the member\'s booking', () {
      final today = DateTime(2026, 11, 16); // a Monday
      final classes = [
        yoga(weekday: 2, hour: 18),
        const GymClass(id: 'hiit', venueId: 'g1', name: 'HIIT', weekday: 2, hour: 6, minute: 30, capacity: 1),
        const GymClass(id: 'off', venueId: 'g1', name: 'Old', weekday: 2, hour: 9, minute: 0, capacity: 5, isActive: false),
      ];
      final sessions = sessionsFrom(classes, [
        ClassPlaces(classId: 'hiit', date: DateTime(2026, 11, 17), booked: 1),
        ClassPlaces(classId: 'yoga', date: DateTime(2026, 11, 17), booked: 1, myBookingId: 'b1'),
      ], today);
      expect([for (final s in sessions) '${s.gymClass.id} ${s.date.day}'], ['hiit 17', 'yoga 17']);
      expect(sessions.first.isFull, isTrue);
      expect(sessions.last.left, 1);
      expect(sessions.last.myBookingId, 'b1');
      expect(sessions.last.startedBy(DateTime(2026, 11, 17, 18, 0)), isTrue);
      expect(sessions.last.startedBy(DateTime(2026, 11, 17, 17, 59)), isFalse);
    });

    testWidgets('on My gym: book, cancel, full', (tester) async {
      await pump(tester, const MyClassesCard(venueId: 'g1'), [
        gymClassesProvider.overrideWith((ref, id) async => [
              yoga(),
              GymClass(id: 'hiit', venueId: 'g1', name: 'HIIT', weekday: day(1).weekday, hour: 9, minute: 0, capacity: 1),
              GymClass(id: 'zumba', venueId: 'g1', name: 'Zumba', weekday: day(2).weekday, hour: 18, minute: 0, capacity: 10),
            ]),
        gymClassPlacesProvider.overrideWith((ref, id) async => [
              ClassPlaces(classId: 'yoga', date: day(1), booked: 1, myBookingId: 'b1'),
              ClassPlaces(classId: 'hiit', date: day(1), booked: 1),
            ]),
      ]);
      expect(find.text('Tomorrow'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget, reason: 'their own booking');
      expect(find.text('Full'), findsOneWidget);
      expect(find.text('Book'), findsOneWidget);
      expect(find.textContaining('1 of 2 places left'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    test('the desk\'s list: a member of the gym, or a non-member on Health Pro', () {
      final member = ClassBooking.fromJson({
        'id': 'b1', 'class_id': 'yoga', 'class_date': '2026-11-21', 'gym_member_id': 'm1', 'user_id': null,
        'full_name': 'Mindu Dema', 'member_code': 'ABC234', 'phone': '+97517700001', 'email': null,
        'is_member': true, 'booked_by_desk': true,
      });
      final nonMember = ClassBooking.fromJson({
        'id': 'b2', 'class_id': 'yoga', 'class_date': '2026-11-21', 'gym_member_id': null, 'user_id': 'u1',
        'full_name': 'Xo Out', 'member_code': null, 'phone': null, 'email': 'xo@x.bt',
        'is_member': false, 'booked_by_desk': false,
      });
      expect((member.memberName, member.memberCode, member.gymMemberId, member.isNonMember, member.bookedByDesk),
          ('Mindu Dema', 'ABC234', 'm1', false, true));
      expect((nonMember.memberName, nonMember.userId, nonMember.isNonMember, nonMember.contact), ('Xo Out', 'u1', true, 'xo@x.bt'));
      expect(member.contact, '+97517700001');
    });

    test('a class is open to everyone unless the gym says not, and the editor sends it', () {
      final base = {'id': 'y', 'venue_id': 'g1', 'name': 'Yoga', 'weekday': 1, 'starts_at': '07:00:00', 'duration_minutes': 60, 'capacity': 5};
      expect(GymClass.fromJson(base).openToAll, isTrue);
      expect(GymClass.fromJson({...base, 'open_to_all': false}).openToAll, isFalse);
      expect(classDetails(name: 'Yoga', weekday: 1, hour: 7, minute: 0, durationMinutes: 60, capacity: 5, openToAll: false)['open_to_all'],
          isFalse);
    });

    testWidgets('on the gym\'s page: anyone books an open class; members-only ones say so', (tester) async {
      await pump(tester, const ClassWeek(venueId: 'g1', signedIn: false, member: false, explain: true), [
        gymClassesProvider.overrideWith((ref, id) async => [
              yoga(),
              GymClass(
                  id: 'hiit', venueId: 'g1', name: 'HIIT', weekday: day(1).weekday, hour: 9, minute: 0, capacity: 5, openToAll: false),
            ]),
        gymClassPlacesProvider.overrideWith((ref, id) async => const []),
      ]);
      expect(find.text('Book'), findsOneWidget, reason: 'the open class');
      expect(find.text('Members only'), findsOneWidget);
      expect(find.textContaining('members only'), findsOneWidget, reason: 'in the members-only class\'s line');
      expect(find.textContaining('Anyone with a Health Pro account can book'), findsOneWidget);
      expect(find.textContaining('Sign in or create a free account'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    test('My dashboard: a booked class, and when it ends', () {
      final b = MyClassBooking.fromJson({
        'id': 'b1', 'class_id': 'yoga', 'venue_id': 'g1', 'venue_name': 'Coach Gym', 'class_date': '2026-11-21',
        'name': 'Yoga', 'trainer_name': null, 'starts_at': '07:00:00', 'duration_minutes': 45,
      });
      expect((b.name, b.venueName, b.time), ('Yoga', 'Coach Gym', '7:00 AM'));
      expect(b.endsAt, DateTime(2026, 11, 21, 7, 45));
      expect(MyClassBookingsList.ahead([b], DateTime(2026, 11, 21, 7, 44)), [b]);
      expect(MyClassBookingsList.ahead([b], DateTime(2026, 11, 21, 7, 45)), isEmpty, reason: 'over: off the list');
    });

    testWidgets('My dashboard: the classes booked at any gym, each with Cancel', (tester) async {
      MyClassBooking booked(String id, String gym, int inDays) => MyClassBooking(
          id: id, classId: id, venueId: gym, venueName: gym == 'g1' ? 'Coach Gym' : 'Paro Fitness', date: day(inDays),
          name: id == 'b1' ? 'Yoga' : 'Zumba', hour: 18, minute: 0);
      await pump(tester, MyClassBookingsList(bookings: [booked('b1', 'g1', 1), booked('b2', 'g2', 2)]), const []);
      expect(find.text('Tomorrow'), findsOneWidget);
      expect(find.text('Yoga'), findsOneWidget);
      expect(find.textContaining('Paro Fitness'), findsOneWidget);
      expect(find.text('Cancel'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a gym without classes shows nothing on My gym', (tester) async {
      await pump(tester, const MyClassesCard(venueId: 'g1'), [gymClassesProvider.overrideWith((ref, id) async => const [])]);
      expect(find.text('Classes'), findsNothing);
    });

    testWidgets('the desk: bookings by class day, who has registered to date, and the timetable', (tester) async {
      await show(tester, const ClassesScreen(venueId: 'g1'), with_: [
        ...overrides(),
        gymClassesProvider.overrideWith((ref, id) async => [yoga(weekday: day(0).weekday, hour: 23)]),
        gymClassPlacesProvider.overrideWith((ref, id) async => [ClassPlaces(classId: 'yoga', date: day(0), booked: 2)]),
        gymClassBookingsProvider.overrideWith((ref, q) async => [
              ClassBooking(id: 'b1', classId: 'yoga', classDate: day(0), gymMemberId: 'm1', memberName: 'Mindu Dema', memberCode: 'ABC234'),
              ClassBooking(
                  id: 'b2', classId: 'yoga', classDate: day(0), userId: 'u1', memberName: 'Xo Out', memberEmail: 'xo@x.bt', isMember: false),
            ]),
        gymClassRegistrationsProvider.overrideWith((ref, id) async => ClassRegistrations(
              bookings: 14,
              people: 2,
              members: 1,
              nonMembers: 1,
              upcoming: 2,
              classes: [
                ClassTally(classId: 'yoga', name: 'Yoga', weekday: 1, hour: 7, minute: 0, bookings: 14, people: 2, members: 1, nonMembers: 1),
              ],
              registrants: [
                ClassRegistrant(
                    key: 'u:u1', name: 'Xo Out', isMember: false, email: 'xo@x.bt', bookings: 3, firstDate: day(-20), lastDate: day(0),
                    lastClass: 'Yoga'),
                ClassRegistrant(
                    key: 'm:m1', name: 'Mindu Dema', memberCode: 'ABC234', phone: '+97517700001', bookings: 11, firstDate: day(-60),
                    lastDate: day(0), lastClass: 'Yoga'),
              ],
            )),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('New class'), findsOneWidget);
      // Bookings: only the days with a class, each with how many are booked.
      expect(find.text('Today · 2 booked'), findsOneWidget);
      expect(find.text('Tomorrow'), findsNothing, reason: 'no class tomorrow');
      expect(find.text('2 / 2'), findsOneWidget, reason: 'places taken, in the day\'s table');
      expect(find.text('1 class'), findsOneWidget, reason: 'the table\'s count, in the singular');
      // Who's booked: in the class's details, from Open.
      await tester.tap(find.text('Open').first);
      await tester.pumpAndSettle();
      expect(inDialog(find.text('Mindu Dema · ABC234')), findsOneWidget);
      expect(inDialog(find.text('Member')), findsOneWidget);
      expect(inDialog(find.text('Xo Out')), findsOneWidget);
      expect(inDialog(find.text('Non-member')), findsOneWidget);
      expect(inDialog(find.text('xo@x.bt')), findsOneWidget);
      expect(inDialog(find.textContaining('1 member · 1 non-member')), findsOneWidget);
      Navigator.of(tester.element(find.text('Mindu Dema · ABC234'))).pop();
      await tester.pumpAndSettle();

      // Registered to date: the totals, each class's, and everyone who has booked.
      await tester.tap(find.text('Registered'));
      await tester.pumpAndSettle();
      expect(find.text('Places booked'), findsOneWidget);
      expect(find.text('By class'), findsOneWidget);
      expect(find.text('People (2)'), findsOneWidget);
      expect(find.text('Register'), findsOneWidget, reason: 'the non-member, for whoever registers members');
      await tester.tap(find.text('Non-members (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Mindu Dema'), findsNothing, reason: 'non-members only');
      await tester.tap(find.text('Everyone (2)'));
      await tester.enterText(find.byType(TextField), '17700001');
      await tester.pumpAndSettle();
      expect(find.text('Xo Out'), findsNothing, reason: 'found by phone');
      expect(find.text('Mindu Dema'), findsOneWidget);

      // The timetable: who can book each class.
      await tester.tap(find.text('Timetable'));
      await tester.pumpAndSettle();
      expect(find.text('Everyone'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
