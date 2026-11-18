import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_membership/gym_membership.dart';
import 'package:gym_membership/src/data/joining.dart';
import 'package:gym_membership/src/data/online_payments.dart';
import 'package:gym_membership/src/screens/payment_screens.dart';
import 'package:health_pro_core/health_pro_core.dart';

import 'gym_navigation_test.dart' as nav show frontDesk, gymId, inMenu, openGym, owner, person, showApp;
import 'gym_screens_test.dart' show day, inDialog, overrides, show;

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

const peakAccount = PaymentAccount(bankName: 'Bank of Bhutan', accountNumber: '200123456789', accountName: 'Peak Fitness');

/// Where the gym's bank-issued QR image is kept.
const peakQr = 'https://example.test/gym-payment-qr/g1/qr.png';

MyGym myGym({MyClaim? claim, PaymentAccount? account = peakAccount, String? qr = peakQr}) => MyGym(
      venueId: 'g1',
      venueName: 'Peak Fitness',
      place: 'Thimphu',
      planName: 'Gym',
      startDate: day(-40),
      endDate: day(-10),
      gymMemberId: 'm1',
      paymentAccount: account,
      paymentQrUrl: qr,
      claim: claim,
    );

/// The bank-issued QR image of [accountName]'s account, as payers see it.
Finder bankQr(String accountName) => find.byWidgetPredicate(
    (w) => w is Image && w.semanticLabel == 'Bank-issued payment QR code for $accountName');

/// Gives the bank-issued QR image's address, for screens that show it.
class QrRepo extends Fake implements GymRepository {
  @override
  String? paymentQrUrl(String? path) => path == null || path.isEmpty ? null : 'https://example.test/gym-payment-qr/$path';
}

void main() {
  test('settings: the defaults before a gym saves any, and what it saved', () {
    final d = GymSettings.defaults('g1');
    expect(d.reminderDays, [3]);
    expect(d.managersAnswerJoins, isFalse);
    expect(d.account, isNull, reason: 'no bank account yet: payments at the desk only');
    final s = GymSettings.fromJson({
      'venue_id': 'g1', 'bank_name': 'Bank of Bhutan', 'account_number': '200123456789', 'account_name': 'Peak Fitness',
      'online_provider': 'bank_account', 'reminder_days': [7, 3], 'join_approval': 'managers',
    });
    expect(s.account!.spacedNumber, '2001 2345 6789');
    expect(s.onlineProvider, OnlineProvider.bankAccount);
    expect(s.reminderDays, [7, 3]);
    expect(s.managersAnswerJoins, isTrue);
  });

  test('the payment QR code holds the account, the amount and what it is for', () {
    expect(peakAccount.qrData(amount: 1500, note: 'Peak Fitness, Gym'),
        'Pay to: Peak Fitness\nBank: Bank of Bhutan\nAccount: 200123456789\nAmount: Nu. 1500\nFor: Peak Fitness, Gym');
    expect(peakAccount.qrData(), isNot(contains('Amount')));
    expect(PaymentAccount.fromJson({'bank_name': null, 'account_number': null}), isNull);
  });

  test('a member pays online where they are registered, the gym has set up its account and QR, and nothing waits', () {
    expect(myGym().canPayOnline, isTrue);
    expect(myGym(account: null).canPayOnline, isFalse, reason: 'no bank account set up: at the desk');
    expect(myGym(qr: null).canPayOnline, isFalse, reason: "the bank's QR not uploaded yet: at the desk");
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
      expect(find.text('Set up your bank account'), findsOneWidget, reason: 'the owner, with none yet');
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(inDialog(find.text('JRN445566')), findsOneWidget);
      expect(inDialog(find.text('Gym · 2 months')), findsOneWidget);
      expect(inDialog(find.text('The price for that is Nu. 3,000.')), findsOneWidget, reason: 'they paid Nu. 2,500');
      expect(inDialog(find.text('Confirm')), findsOneWidget);
      expect(inDialog(find.text('Not found')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('...confirming asks them to check the bank first', (tester) async {
    await show(tester, const PaymentsToConfirmScreen(venueId: 'g1'), with_: [
      ...overrides(),
      gymPaymentClaimsProvider.overrideWith((ref, id) async => [claim()]),
      gymSettingsProvider.overrideWith((ref, id) async => GymSettings.defaults(id)),
    ]);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(find.text("Confirm Pema Yangzom's payment?"), findsOneWidget);
    expect(find.textContaining('find journal number JRN445566 for Nu. 3,000'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('Membership settings: the bank account and its QR, reminder days, who answers requests to join', (tester) async {
    for (final size in [const Size(1440, 1000), const Size(390, 844)]) {
      await show(tester, const MembershipSettingsScreen(venueId: 'g1'), size: size, with_: [
        ...overrides(),
        gymRepositoryProvider.overrideWithValue(QrRepo()),
        gymSettingsProvider.overrideWith((ref, id) async => const GymSettings(
            venueId: 'g1',
            account: peakAccount,
            paymentQrPath: 'g1/qr.png',
            reminderDays: [7, 3],
            joinApproval: JoinApproval.managers)),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Account number'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '200123456789'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Change QR code'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('Bank-issued payment QR'), findsOneWidget);
      expect(find.text('Remove QR'), findsOneWidget, reason: 'the QR they uploaded');
      await tester.scrollUntilVisible(find.text('What payers see'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('2001 2345 6789'), findsOneWidget, reason: 'the account written out under the QR');
      expect(bankQr('Peak Fitness'), findsOneWidget, reason: "the bank's QR they uploaded");
      await tester.scrollUntilVisible(find.text('Online payment gateway (RMA)'), 200, scrollable: find.byType(Scrollable).first);
      await tester.scrollUntilVisible(find.text('7 days'), 200, scrollable: find.byType(Scrollable).first);
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
      expect(find.text('2001 2345 6789'), findsNothing, reason: 'the QR code comes when they go on to pay');
      expect(find.text("I've paid: send it to the gym"), findsNothing);
      await tester.tap(find.text('Proceed to pay Nu. 1,500'));
      await tester.pumpAndSettle();
      expect(find.text('Pay Nu. 1,500 in your bank app'), findsOneWidget, reason: 'their usual package');
      await tester.scrollUntilVisible(find.text('2001 2345 6789'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('Bank of Bhutan'), findsOneWidget);
      await tester.scrollUntilVisible(find.text("I've paid: send it to the gym"), 200, scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(find.text("I've paid: send it to the gym"));
      await tester.pumpAndSettle();
      await tester.tap(find.text("I've paid: send it to the gym"));
      await tester.pumpAndSettle();
      expect(find.text('Enter the journal number from the receipt'), findsOneWidget, reason: 'nothing sent without it');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a gym with no bank account set up: at the desk', (tester) async {
      await showPay(tester, MyMemberships(gyms: [myGym(account: null)]));
      await tester.pumpAndSettle();
      expect(find.text('Peak Fitness takes payments at the front desk'), findsOneWidget);
    });

    testWidgets("a gym with its account but not the bank's QR yet: at the desk", (tester) async {
      await showPay(tester, MyMemberships(gyms: [myGym(qr: null)]));
      await tester.pumpAndSettle();
      expect(find.text('Peak Fitness takes payments at the front desk'), findsOneWidget);
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
      await nav.openGym(tester);
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
      await nav.openGym(tester);
      expect(nav.inMenu('Payments to confirm'), findsOneWidget, reason: 'they take payments');
      expect(nav.inMenu('Join requests'), findsNothing);
      expect(nav.inMenu('Membership settings'), findsNothing, reason: "they don't edit the gym");
    });
  });
}
