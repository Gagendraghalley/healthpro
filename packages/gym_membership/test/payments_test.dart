import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_membership/gym_membership.dart';
import 'package:gym_membership/src/data/joining.dart';
import 'package:gym_membership/src/data/online_payments.dart';
import 'package:gym_membership/src/screens/payment_screens.dart';
import 'package:health_pro_core/health_pro_core.dart';

import 'gym_navigation_test.dart' as nav show frontDesk, gymId, inMenu, owner, person, showApp;
import 'gym_screens_test.dart' show day, overrides, show;

// Paying online with a journal number, and the gym's settings (the database
// side: tests/database/payments_test.sql).

PaymentClaim claim({String status = 'pending', int amount = 3000, int months = 2}) => PaymentClaim.fromJson({
      'id': 'c1',
      'venue_id': 'g1',
      'gym_member_id': 'm1',
      'member': {'full_name': 'Pema Yangzom', 'code': '4K7P9Q'},
      'plan_id': 'p1',
      'plan_name': 'Gym',
      'months': months,
      'amount': amount,
      'jrn': 'JRN445566',
      'status': status,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });

MyGym myGym({MyClaim? claim, String? info = 'Bank of Bhutan 200123456, Peak Fitness'}) => MyGym(
      venueId: 'g1',
      venueName: 'Peak Fitness',
      place: 'Thimphu',
      planName: 'Gym',
      startDate: day(-40),
      endDate: day(-10),
      gymMemberId: 'm1',
      paymentInfo: info,
      claim: claim,
    );

void main() {
  test('settings: the defaults before a gym saves any, and what it saved', () {
    final d = GymSettings.defaults('g1');
    expect(d.reminderDays, [3]);
    expect(d.managersAnswerJoins, isFalse);
    final s = GymSettings.fromJson(
        {'venue_id': 'g1', 'payment_qr_path': 'g1/qr.png', 'reminder_days': [7, 3], 'join_approval': 'managers'});
    expect(s.reminderDays, [7, 3]);
    expect(s.managersAnswerJoins, isTrue);
  });

  test('a member pays online where they are registered, the gym says how, and nothing waits', () {
    expect(myGym().canPayOnline, isTrue);
    expect(myGym(info: null).canPayOnline, isFalse, reason: 'no payment QR or details: at the desk');
    final waiting =
        MyClaim(id: 'c1', status: ClaimStatus.pending, planName: 'Gym', months: 1, amount: 1500, jrn: 'JRN1', createdAt: DateTime.now());
    expect(myGym(claim: waiting).canPayOnline, isFalse, reason: 'one waits already');
  });

  testWidgets('Payments to confirm: who, what for, the journal number, and the price to compare', (tester) async {
    for (final size in [const Size(1440, 1000), const Size(390, 844)]) {
      await show(tester, const PaymentsToConfirmScreen(venueId: 'g1'), size: size, with_: [
        ...overrides(),
        gymPaymentClaimsProvider.overrideWith((ref, id) async => [claim(amount: 2500)]),
        gymSettingsProvider.overrideWith((ref, id) async => GymSettings.defaults(id)),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Waiting (1)'), findsOneWidget);
      expect(find.text('Pema Yangzom'), findsOneWidget);
      expect(find.text('JRN445566'), findsOneWidget);
      expect(find.text('Gym · 2 months'), findsOneWidget);
      expect(find.text('The price for that is Nu. 3,000.'), findsOneWidget, reason: 'they paid Nu. 2,500');
      expect(find.text('Confirm'), findsOneWidget);
      expect(find.text('Not found'), findsOneWidget);
      expect(find.text('Add your payment QR code'), findsOneWidget, reason: 'the owner, with none yet');
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('...confirming asks them to check the bank first', (tester) async {
    await show(tester, const PaymentsToConfirmScreen(venueId: 'g1'), with_: [
      ...overrides(),
      gymPaymentClaimsProvider.overrideWith((ref, id) async => [claim()]),
      gymSettingsProvider.overrideWith((ref, id) async => GymSettings.defaults(id)),
    ]);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(find.text("Confirm Pema Yangzom's payment?"), findsOneWidget);
    expect(find.textContaining('find journal number JRN445566 for Nu. 3,000'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('Membership settings: payment QR, reminder days, who answers requests to join', (tester) async {
    for (final size in [const Size(1440, 1000), const Size(390, 844)]) {
      await show(tester, const MembershipSettingsScreen(venueId: 'g1'), size: size, with_: [
        ...overrides(),
        gymSettingsProvider.overrideWith(
            (ref, id) async => const GymSettings(venueId: 'g1', reminderDays: [7, 3], joinApproval: JoinApproval.managers)),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Upload payment QR'), findsOneWidget);
      FilterChip chip(String label) => tester.widget<FilterChip>(find.widgetWithText(FilterChip, label));
      expect(chip('7 days').selected, isTrue);
      expect(chip('3 days').selected, isTrue);
      expect(chip('1 day').selected, isFalse);
      await tester.scrollUntilVisible(find.text('The owner and managers only'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('The owner and managers only'), findsOneWidget);
      expect(find.text('Save settings'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  group('Pay online', () {
    Future<void> showPay(WidgetTester tester, MyMemberships mine) => show(
          tester,
          const PayOnlineScreen(venueId: 'g1'),
          size: const Size(390, 844),
          with_: [...overrides(), currentUserIdProvider.overrideWithValue('u1'), myMembershipsProvider.overrideWith((ref) async => mine)],
        );

    testWidgets('the package, the amount, how to pay, and the journal number', (tester) async {
      await showPay(tester, MyMemberships(gyms: [myGym()]));
      await tester.pumpAndSettle();
      expect(find.text('Peak Fitness'), findsOneWidget);
      expect(find.text('Choose your package'), findsOneWidget);
      expect(find.text('Scan this in your bank app and pay Nu. 1,500'), findsOneWidget, reason: 'their usual package');
      expect(find.text('Bank of Bhutan 200123456, Peak Fitness'), findsOneWidget);
      await tester.scrollUntilVisible(find.text("I've paid: send it to the gym"), 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text("I've paid: send it to the gym"));
      await tester.pumpAndSettle();
      expect(find.text('Enter the journal number from the receipt'), findsOneWidget, reason: 'nothing sent without it');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a payment waiting: nothing to pay again', (tester) async {
      final waiting = MyClaim(
          id: 'c1', status: ClaimStatus.pending, planName: 'Gym', months: 1, amount: 1500, jrn: 'JRN1', createdAt: DateTime.now());
      await showPay(tester, MyMemberships(gyms: [myGym(claim: waiting)]));
      await tester.pumpAndSettle();
      expect(find.text('Your payment is waiting'), findsOneWidget);
    });

    testWidgets('not a member there: ask to join first', (tester) async {
      await showPay(tester, MyMemberships.none);
      await tester.pumpAndSettle();
      expect(find.text("You're not a member of this gym yet"), findsOneWidget);
    });
  });

  group('the menu', () {
    const computer = Size(1440, 1000);

    testWidgets("the owner: payments to confirm, with a count, and the gym's membership settings", (tester) async {
      await nav.showApp(tester, computer, [
        ...nav.person(gyms: nav.owner),
        gymWaitingPaymentsProvider.overrideWith((ref, id) async => 2),
        gymWaitingRequestsProvider.overrideWith((ref, id) async => 0),
        gymSettingsProvider.overrideWith((ref, id) async => GymSettings.defaults(id)),
      ]);
      expect(nav.inMenu('Payments to confirm'), findsOneWidget);
      expect(nav.inMenu('Membership settings'), findsOneWidget);
      expect(nav.inMenu('Join requests'), findsOneWidget);
    });

    testWidgets('the front desk, where managers answer requests to join: none for them', (tester) async {
      await nav.showApp(tester, computer, [
        ...nav.person(gyms: nav.frontDesk),
        gymWaitingPaymentsProvider.overrideWith((ref, id) async => 0),
        gymWaitingRequestsProvider.overrideWith((ref, id) async => 1),
        gymSettingsProvider.overrideWith((ref, id) async => GymSettings(venueId: id, joinApproval: JoinApproval.managers)),
      ], at: '/gyms/${nav.gymId}/manage');
      expect(nav.inMenu('Payments to confirm'), findsOneWidget, reason: 'they take payments');
      expect(nav.inMenu('Join requests'), findsNothing);
      expect(nav.inMenu('Membership settings'), findsNothing, reason: "they don't edit the gym");
    });
  });
}
