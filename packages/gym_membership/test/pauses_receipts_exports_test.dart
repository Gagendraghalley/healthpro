import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_membership/gym_membership.dart';
import 'package:gym_membership/src/data/exports.dart';
import 'package:gym_membership/src/data/receipts.dart';
import 'package:gym_membership/src/screens/members_screens.dart';
import 'package:gym_membership/src/widgets/receipt_view.dart';
import 'package:health_pro_core/health_pro_core.dart';

DateTime day(int offset) {
  final t = BhutanTime.today();
  return DateTime(t.year, t.month, t.day + offset);
}

GymSubscription sub(String id, int from, int to, {String status = SubscriptionStatus.active, String? paymentId}) =>
    GymSubscription(
      id: id,
      venueId: 'g1',
      memberId: 'm1',
      gymMemberId: 'm1',
      planName: 'Monthly',
      durationDays: 30,
      price: 1500,
      status: status,
      startDate: day(from),
      endDate: day(to),
      requestedAt: DateTime.now().toUtc(),
      paymentId: paymentId,
    );

GymPause pause(int from, int to, {String member = 'm1', String? reason}) => GymPause(
      id: 'pz$from',
      venueId: 'g1',
      gymMemberId: member,
      startDate: day(from),
      endDate: day(to),
      reason: reason,
    );

final member = GymMember.fromJson({
  'id': 'm1',
  'venue_id': 'g1',
  'code': 'K7P9QA',
  'qr_token': '0123456789abcdef0123456789abcdef',
  'full_name': 'Karma Wangmo',
  'phone': '+97517123456',
  'email': 'karma@example.bt',
  'blood_group': 'B+',
  'date_of_birth': '1995-04-12',
  'medical_notes': 'Asthma',
  'joined_on': '2026-11-01',
  'created_at': '2026-11-01T03:00:00Z',
});

final receiptJson = {
  'payment_id': 'pay1',
  'receipt_no': 12,
  'paid_at': '2026-11-18T04:30:00Z',
  'amount': 4500,
  'method': 'mbob',
  'reference': '123456789',
  'status': 'completed',
  'gym_name': 'Peak <Fitness> & Co',
  'gym_phone': '+97517000301',
  'gym_address': 'Changzamtok, Thimphu',
  'member_name': 'Karma Wangmo',
  'member_code': 'K7P9QA',
  'member_phone': '+97517123456',
  'plan_name': 'Monthly',
  'start_date': '2026-11-18',
  'end_date': '2027-02-18',
  'received_by': 'Dawa Desk',
};

void main() {
  group('pausing', () {
    test('a running pause makes them paused; one planned or over does not', () {
      final subs = [sub('s1', -10, 20)];
      expect(standingOf(subs, day(0), pause: pause(-2, 5)), MemberStanding.paused);
      expect(standingOf(subs, day(0), pause: pause(3, 9)), MemberStanding.active);
      expect(standingOf(subs, day(0)), MemberStanding.active);
    });

    test('the open pause is the one running or planned, for that member', () {
      final all = [pause(-20, -11), pause(3, 9), pause(-1, 4, member: 'm2')];
      expect(openPauseOf(all, 'm1', day(0))!.startDate, day(3));
      expect(openPauseOf(all, 'm2', day(0))!.gymMemberId, 'm2');
      expect(openPauseOf([pause(-20, -11)], 'm1', day(0)), isNull);
      expect(pause(3, 9).days, 7);
      expect(pause(3, 9).isUpcomingOn(day(0)), isTrue);
    });

    test('until when they run after a pause: everything from its first day moves, as the database does', () {
      final subs = [sub('old', -90, -60, status: SubscriptionStatus.expired), sub('now', -10, 20), sub('next', 20, 50)];
      expect(runsUntilAfterPause(subs, day(5), 14), day(64));
      expect(runningOn(subs, day(5))!.id, 'now');
      expect(runningOn(subs, day(30))!.id, 'next');
      expect(runningOn(subs, day(80)), isNull);
      expect(runsUntilAfterPause(subs, day(80), 14), isNull);
    });
  });

  group('receipts', () {
    final r = Receipt.fromJson(receiptJson);

    test('read from the database, numbered, with the JRN', () {
      expect(r.number, 'No. 000012');
      expect(receiptNumber(7), '000007');
      expect(r.referenceLine, 'JRN 123456789');
      expect(r.period, '${formatDate(DateTime(2026, 11, 18))} to ${formatDate(DateTime(2027, 2, 18))}');
      expect(r.lines.map((l) => l.$1), ['Received from', 'Member code', 'Package', 'Valid', 'Paid by', 'Reference', 'Received by']);
      expect(r.fileName, isNot(contains('<')));
    });

    test('as a WhatsApp message', () {
      expect(r.message, startsWith('*Peak <Fitness> & Co*\nReceipt No. 000012'));
      expect(r.message, contains('Amount: *${formatNu(4500)}*'));
      expect(r.message, contains('Reference: JRN 123456789'));
    });

    test('as a page to print, its words escaped', () {
      expect(r.html, contains('Peak &lt;Fitness&gt; &amp; Co'));
      expect(r.html, isNot(contains('<Fitness>')));
      expect(r.html, contains('RECEIPT No. 000012'));
      expect(Receipt.fromJson({...receiptJson, 'status': 'refunded'}).html, contains('Refunded'));
    });

    testWidgets('the receipt opens with its paper and ways to send it', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [gymReceiptProvider.overrideWith((ref, id) async => r)],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(child: TextButton(onPressed: () => showReceipt(context, 'pay1'), child: const Text('Open'))),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('RECEIPT No. 000012'), findsOneWidget);
      expect(find.text('Dawa Desk'), findsOneWidget);
      expect(find.text(formatNu(4500)), findsOneWidget);
      expect(find.text('WhatsApp'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget, reason: 'a phone shares the picture');
      expect(find.text('Print'), findsNothing, reason: 'printing is on the website');
    });
  });

  group('exports', () {
    test('members: details, package, until when, and where they stand', () {
      final data = MembersExport(
        members: [member],
        subscriptions: [sub('s1', -10, 20)],
        pauses: [pause(-1, 5)],
      );
      final sheet = membersSheet(data, day(0));
      expect(sheet.headings.first, 'Member code');
      final row = sheet.rows.single;
      expect(row[0], 'K7P9QA');
      expect(row[2], '+97517123456', reason: 'a phone number stays text');
      expect(row[4], DateTime(1995, 4, 12));
      expect(row[12], 'Monthly');
      expect(row[13], day(20));
      expect(row[14], 'Paused until ${formatDate(day(5))}');
      expect(sheet.sheetXml(), contains('<t xml:space="preserve">+97517123456</t>'));
    });

    test('payments: receipt, Bhutan time, package, amount as a number', () {
      final p = ExportedPayment.fromJson({
        'id': 'pay1',
        'venue_id': 'g1',
        'module_key': gymModuleKey,
        'amount': 4500,
        'method': 'mbob',
        'reference': '123456789',
        'status': 'completed',
        'receipt_no': 12,
        'payer_name': 'Karma Wangmo',
        'created_at': '2026-11-18T04:30:00Z',
        'package': [
          {'plan_name': 'Monthly', 'start_date': '2026-11-18', 'end_date': '2027-02-18', 'registered': {'code': 'K7P9QA'}},
        ],
      });
      final row = paymentsSheet([p]).rows.single;
      expect(row[0], '000012');
      expect(row[1], DateTime(2026, 11, 18, 10, 30), reason: '04:30 UTC is 10:30 in Bhutan');
      expect(row.sublist(2, 5), ['Karma Wangmo', 'K7P9QA', 'Monthly']);
      expect(row[7], 4500);
      expect(row.sublist(8), ['mBoB', '123456789', 'Received']);
    });

    test('visits: when and who, a registered member or an account', () {
      final rows = visitsSheet([
        ExportedVisit.fromJson({
          'checked_in_at': '2026-11-18T00:15:00Z',
          'registered': {'full_name': 'Karma Wangmo', 'code': 'K7P9QA', 'phone': '+97517123456'},
        }),
        ExportedVisit.fromJson({
          'checked_in_at': '2026-11-18T01:00:00Z',
          'member': {'full_name': 'Pema', 'member_code': 'ABCDEF', 'phone': null},
        }),
      ]).rows;
      expect(rows[0], [DateTime(2026, 11, 18, 6, 15), 'Karma Wangmo', 'K7P9QA', '+97517123456']);
      expect(rows[1], [DateTime(2026, 11, 18, 7), 'Pema', 'ABCDEF', null]);
    });
  });

  testWidgets("a paused member's page says so, with Resume, and receipts by their packages", (tester) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final gym = Venue.fromJson({
      'id': 'g1',
      'type': gymVenueType,
      'name': 'Peak Fitness',
      'dzongkhag': 'Thimphu',
      'verification_status': 'verified',
      'created_at': '2026-11-01T00:00:00Z',
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [
        venueAccessProvider.overrideWith((ref, id) async => VenueAccess(gym, VenueRole.owner)),
        gymMemberProvider.overrideWith((ref, id) async => member),
        gymSubscriptionsProvider.overrideWith((ref, id) async => [sub('s1', -10, 34, paymentId: 'pay1')]),
        gymMemberCheckInsProvider.overrideWith((ref, id) async => const <GymCheckIn>[]),
        gymMemberPausesProvider.overrideWith((ref, id) async => [pause(-2, 11, reason: 'Travelling')]),
        gymMemberClaimsProvider.overrideWith((ref, id) async => const []),
        gymVerifiedTrainersProvider.overrideWith((ref, id) async => const []),
        memberTrainerProvider.overrideWith((ref, id) async => null),
        unreadCountProvider.overrideWithValue(0),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const GymMemberScreen(venueId: 'g1', memberId: 'm1')),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Paused to ${formatShortDate(day(11))}'), findsOneWidget);
    expect(find.text('Paused: no check-in until it ends'), findsOneWidget);
    expect(find.textContaining('Travelling'), findsOneWidget);
    expect(find.text('Resume'), findsOneWidget);
    expect(find.text('Pause'), findsNothing, reason: 'one pause at a time');
    expect(find.byTooltip('Receipt'), findsOneWidget);
    expect(find.text('Delete member'), findsOneWidget, reason: 'the owner can take them off the register');
  });
}
