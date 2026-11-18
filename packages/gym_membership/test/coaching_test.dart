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

import 'gym_screens_test.dart' show day, overrides, show;

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

    testWidgets('a gym without classes shows nothing on My gym', (tester) async {
      await pump(tester, const MyClassesCard(venueId: 'g1'), [gymClassesProvider.overrideWith((ref, id) async => const [])]);
      expect(find.text('Classes'), findsNothing);
    });

    testWidgets('the desk: the day\'s classes with who\'s booked, and the weekly timetable', (tester) async {
      await show(tester, const ClassesScreen(venueId: 'g1'), with_: [
        ...overrides(),
        gymClassesProvider.overrideWith((ref, id) async => [yoga(weekday: day(0).weekday, hour: 23)]),
        gymClassBookingsProvider.overrideWith((ref, q) async => [
              ClassBooking(id: 'b1', classId: 'yoga', classDate: day(0), gymMemberId: 'm1', memberName: 'Mindu Dema', memberCode: 'ABC234'),
            ]),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('New class'), findsOneWidget);
      expect(find.text('Mindu Dema · ABC234'), findsOneWidget);
      expect(find.text('1 / 2'), findsOneWidget);
      expect(find.text('Weekly timetable'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
