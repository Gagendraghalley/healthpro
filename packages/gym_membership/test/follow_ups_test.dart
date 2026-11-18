import 'package:flutter_test/flutter_test.dart';
import 'package:gym_membership/gym_membership.dart';
import 'package:gym_membership/src/data/follow_ups.dart';
import 'package:gym_membership/src/screens/activity_screen.dart';
import 'package:gym_membership/src/screens/enquiries_screen.dart';
import 'package:health_pro_core/health_pro_core.dart';

import 'gym_screens_test.dart' show day, overrides, show;

// The activity log, enquiries and free trials, WhatsApp reminders and
// birthdays (the database side: tests/database/follow_ups_test.sql).

GymMember member(String id, {DateTime? born}) => GymMember(
      id: id,
      venueId: 'g1',
      code: 'ABC23$id',
      qrToken: 'token-$id',
      fullName: 'Member $id',
      phone: '+9751711122$id',
      dateOfBirth: born,
      joinedOn: day(-100),
      createdAt: DateTime.utc(2026, 1, 1),
    );

GymEnquiry enquiry(String id, {EnquiryStatus status = EnquiryStatus.open, DateTime? followUp, DateTime? trialFrom, DateTime? trialTo}) =>
    GymEnquiry(
      id: id,
      venueId: 'g1',
      fullName: 'Karma $id',
      phone: '+9751750002$id',
      status: status,
      followUpOn: followUp,
      trialStartsOn: trialFrom,
      trialEndsOn: trialTo,
      interest: 'Weight loss',
      createdAt: DateTime.now().toUtc(),
    );

void main() {
  group('birthdays', () {
    test('29 February is the 28th in a year without one', () {
      final born = DateTime(1996, 2, 29);
      expect(birthdayIn(born, 2027), DateTime(2027, 2, 28));
      expect(birthdayIn(born, 2028), DateTime(2028, 2, 29));
      expect(nextBirthday(DateTime(1990, 11, 18), DateTime(2026, 11, 18)), DateTime(2026, 11, 18));
      expect(nextBirthday(DateTime(1990, 1, 5), DateTime(2026, 11, 18)), DateTime(2027, 1, 5));
    });

    test('the week ahead, today first, with their age; only members asked for', () {
      final today = day(0);
      final members = [
        member('1', born: DateTime(today.year - 30, today.month, today.day + 3)),
        member('2', born: DateTime(today.year - 25, today.month, today.day)),
        member('3', born: DateTime(today.year - 40, today.month, today.day + 9)),
        member('4'),
        member('5', born: DateTime(today.year - 20, today.month, today.day)),
      ];
      final found = birthdaysWithin(members, today, 7, include: (m) => m.id != '5');
      expect([for (final b in found) b.member.id], ['2', '1']);
      expect(found.first.age, 25);
      expect(found.first.day, today);
    });

    test('recent members: a package now, or one that ended in the last 90 days', () {
      GymSubscription sub(int from, int to, String status) => GymSubscription(
            id: 's$from',
            venueId: 'g1',
            memberId: 'm',
            gymMemberId: 'm',
            planName: 'Gym',
            durationDays: 30,
            price: 1500,
            status: status,
            startDate: day(from),
            endDate: day(to),
            requestedAt: DateTime.utc(2026, 1, 1),
          );
      expect(isRecentMember([sub(-10, 20, SubscriptionStatus.active)], day(0)), isTrue);
      expect(isRecentMember([sub(-120, -60, SubscriptionStatus.expired)], day(0)), isTrue);
      expect(isRecentMember([sub(-200, -100, SubscriptionStatus.expired)], day(0)), isFalse);
      expect(isRecentMember([sub(-10, 20, SubscriptionStatus.cancelled)], day(0)), isFalse);
    });
  });

  group('WhatsApp messages', () {
    test('a renewal reminder before, on and after the last day', () {
      final today = DateTime(2026, 11, 18);
      String msg(DateTime end) => renewalMessage(name: 'Sonam Dorji', gym: 'Peak Fitness', plan: 'Monthly', end: end, today: today);
      expect(msg(DateTime(2026, 11, 21)), startsWith('Hello Sonam, your Monthly at Peak Fitness ends on 21 Nov 2026.'));
      expect(msg(today), contains('ends today'));
      expect(msg(DateTime(2026, 11, 10)), contains('ended on 10 Nov 2026. We miss you!'));
      expect(birthdayMessage(name: 'Sonam Dorji', gym: 'Peak Fitness'), startsWith('Happy birthday, Sonam! Everyone at Peak Fitness'));
    });

    test('when a member was last sent each kind', () {
      final messages = [
        MemberMessage(gymMemberId: 'a', kind: MessageKind.renewal, sentAt: DateTime.utc(2026, 11, 10)),
        MemberMessage(gymMemberId: 'a', kind: MessageKind.renewal, sentAt: DateTime.utc(2026, 11, 16)),
        MemberMessage(gymMemberId: 'a', kind: MessageKind.birthday, sentAt: DateTime.utc(2026, 11, 17)),
      ];
      expect(lastSent(messages, 'a', MessageKind.renewal), DateTime.utc(2026, 11, 16));
      expect(lastSent(messages, 'b', MessageKind.renewal), isNull);
    });
  });

  group('enquiries', () {
    test('what needs the desk today', () {
      final today = day(0);
      expect(enquiry('1', followUp: day(0)).needsActionOn(today), isTrue);
      expect(enquiry('2', followUp: day(-2)).needsActionOn(today), isTrue, reason: 'a missed follow-up');
      expect(enquiry('3', followUp: day(2)).needsActionOn(today), isFalse);
      expect(enquiry('4', status: EnquiryStatus.trial, trialFrom: day(-4), trialTo: day(-1)).needsActionOn(today), isTrue,
          reason: 'a trial that has ended');
      expect(enquiry('5', status: EnquiryStatus.joined, followUp: day(-2)).needsActionOn(today), isFalse);
      expect(enquiry('6', status: EnquiryStatus.trial, trialFrom: day(0), trialTo: day(2)).trialDays, 3);
    });

    test('what the desk saves: the phone tidied, empty words left out', () {
      final json = EnquiryDetails(
        fullName: ' Karma ',
        phone: '17 50 00 21',
        status: EnquiryStatus.trial,
        trialStartsOn: DateTime(2026, 11, 18),
        trialEndsOn: DateTime(2026, 11, 20),
        interest: '  ',
      ).toJson();
      expect(json['full_name'], 'Karma');
      expect(json['phone'], '+97517500021');
      expect(json['interest'], isNull);
      expect(json['trial_ends_on'], '2026-11-20');
      expect(json['source'], 'walk_in');
    });

    testWidgets('the list: who to follow up first, a trial, and Register', (tester) async {
      await show(tester, const EnquiriesScreen(venueId: 'g1'), with_: [
        ...overrides(),
        gymEnquiriesProvider.overrideWith((ref, id) async => [
              enquiry('1', followUp: day(3)),
              enquiry('2', followUp: day(-1)),
              enquiry('3', status: EnquiryStatus.trial, trialFrom: day(0), trialTo: day(2)),
              enquiry('4', status: EnquiryStatus.joined),
            ]),
      ]);
      await tester.pumpAndSettle();
      expect(find.textContaining('1 to follow up today'), findsOneWidget);
      expect(find.text('To follow up  3'), findsOneWidget);
      expect(find.text('Follow-up missed, ${formatShortDate(day(-1))}'), findsOneWidget);
      expect(find.text('Trial until ${formatShortDate(day(2))}'), findsOneWidget);
      expect(find.text('Register'), findsNWidgets(3));
      expect(find.text('Karma 4'), findsNothing, reason: 'joined: under Joined');
      // The missed one comes first.
      expect(tester.getTopLeft(find.text('Karma 2')).dy, lessThanOrEqualTo(tester.getTopLeft(find.text('Karma 1')).dy));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a trainer, who doesn\'t register members, can\'t open it', (tester) async {
      await show(tester, const EnquiriesScreen(venueId: 'g1'), with_: [
        ...overrides(role: VenueRole.trainer),
        gymEnquiriesProvider.overrideWith((ref, id) async => const []),
      ]);
      await tester.pumpAndSettle();
      expect(find.text("Your role here doesn't include this"), findsOneWidget);
    });
  });

  group('the activity log', () {
    final entries = [
      AuditEntry(
        id: 3,
        action: 'payment.received',
        summary: 'Received Nu. 1,500 from Sonam Log',
        details: 'Nu. 1,500 cash · receipt 4',
        actorName: 'Dawa Desk',
        gymMemberId: 'a',
        amount: 1500,
        createdAt: DateTime.now().toUtc(),
      ),
      AuditEntry(
        id: 2,
        action: 'plan.changed',
        summary: 'Changed the package Monthly',
        details: 'price Nu. 1,500 to Nu. 1,600',
        actorName: 'Oki Owner',
        createdAt: DateTime.now().toUtc(),
      ),
      AuditEntry(id: 1, action: 'member.registered', summary: 'Registered Sonam Log (ABC234)', createdAt: DateTime.utc(2026, 1, 5)),
    ];

    test('each entry\'s area', () {
      expect([for (final e in entries) e.area], [AuditArea.money, AuditArea.setup, AuditArea.members]);
      expect(entries.last.by, 'Someone');
    });

    testWidgets('by day, narrowed by kind and by who', (tester) async {
      await show(tester, const ActivityLogScreen(venueId: 'g1'), with_: [
        ...overrides(),
        gymAuditLogProvider.overrideWith((ref, q) async => entries),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Received Nu. 1,500 from Sonam Log'), findsOneWidget);
      expect(find.text('Changed the package Monthly'), findsOneWidget);
      await tester.tap(find.text('Money'));
      await tester.pumpAndSettle();
      expect(find.text('Changed the package Monthly'), findsNothing);
      expect(find.text('Received Nu. 1,500 from Sonam Log'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the front desk can\'t open it', (tester) async {
      await show(tester, const ActivityLogScreen(venueId: 'g1'), with_: [
        ...overrides(role: VenueRole.staff),
        gymAuditLogProvider.overrideWith((ref, q) async => entries),
      ]);
      await tester.pumpAndSettle();
      expect(find.text("Your role here doesn't include this"), findsOneWidget);
    });
  });
}
