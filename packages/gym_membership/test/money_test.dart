import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_membership/gym_membership.dart';
import 'package:gym_membership/src/data/money.dart';
import 'package:gym_membership/src/data/receipts.dart';
import 'package:gym_membership/src/screens/expenses_screen.dart';
import 'package:gym_membership/src/screens/offers_screen.dart';
import 'package:gym_membership/src/widgets/package_fields.dart';
import 'package:health_pro_core/health_pro_core.dart';

import 'gym_screens_test.dart' show day, overrides, plans, show;

// Discounts and offers, and expenses and profit (the database side:
// tests/database/money_test.sql).

const student = GymOffer(id: 'o1', venueId: 'g1', name: 'Student', kind: OfferKind.percent, value: 10);
const couple = GymOffer(id: 'o2', venueId: 'g1', name: 'Couple', kind: OfferKind.amount, value: 500);
const monthly = GymPlan(id: 'p1', venueId: 'g1', name: 'Gym', durationDays: 30, price: 1500, isActive: true);

Payment payment(int amount, DateTime day, {String status = 'completed'}) => Payment.fromJson({
      'id': 'pay-$amount-${day.day}',
      'venue_id': 'g1',
      'module_key': gymModuleKey,
      'amount': amount,
      'method': 'cash',
      'status': status,
      'created_at': bhutanMidnightUtc(day).add(const Duration(hours: 10)).toIso8601String(),
    });

GymExpense expense(String id, ExpenseCategory c, int amount, DateTime on) =>
    GymExpense(id: id, venueId: 'g1', spentOn: on, category: c, amount: amount, paidTo: 'Landlord');

GymSubscription sold(String id, int price, int? list, {String? offer, String? reason, DateTime? at}) => GymSubscription(
      id: id,
      venueId: 'g1',
      memberId: id,
      gymMemberId: id,
      memberName: 'Member $id',
      planName: 'Gym',
      durationDays: 30,
      price: price,
      status: SubscriptionStatus.active,
      startDate: day(0),
      endDate: day(30),
      requestedAt: DateTime.now().toUtc(),
      activatedAt: at ?? DateTime.now().toUtc(),
      listPrice: list,
      offerName: offer,
      discountReason: reason,
    );

void main() {
  group('offers and discounts', () {
    test('an offer\'s price, never below nothing', () {
      expect(student.priceFrom(4500), 4050);
      expect(couple.priceFrom(1500), 1000);
      expect(couple.priceFrom(300), 0);
      expect(student.label, '10% off');
      expect(couple.label, 'Nu. 500 off');
    });

    test('a sale tells the database about a discount only when there is one', () {
      expect(const PackageSale(plan: monthly, months: 3, amount: 4500, offer: student).discountDetails, isNull);
      const withOffer = PackageSale(plan: monthly, months: 3, amount: 4050, offer: student, discountReason: ' ID seen ');
      expect(withOffer.listPrice, 4500);
      expect(withOffer.discount, 450);
      expect(withOffer.discountDetails, {'offer_id': 'o1', 'reason': 'ID seen'});
      expect(const PackageSale(plan: monthly, months: 1, amount: 1000, discountReason: 'Referred by Sonam').discountDetails,
          {'reason': 'Referred by Sonam'});
    });

    test('the month\'s discounts, how much, and those with no reason', () {
      final now = DateTime.now().toUtc();
      final subs = [
        sold('a', 4050, 4500, offer: 'Student'),
        sold('b', 1200, 1500),
        sold('c', 1500, 1500),
        sold('d', 1500, null),
        sold('e', 1000, 1500, reason: 'Referred', at: now.subtract(const Duration(days: 70))),
      ];
      final month = DateTime(BhutanTime.today().year, BhutanTime.today().month);
      final given = discountedIn(subs, month);
      expect(given.map((s) => s.id), unorderedEquals(['a', 'b']));
      final totals = discountTotals(given);
      expect((totals.count, totals.total, totals.unexplained), (2, 750, 1));
      expect(discountWhy(subs[0]), 'Student');
      expect(discountWhy(subs[1]), 'No reason given');
    });

    test('the receipt shows the full price and the discount', () {
      final r = Receipt.fromJson({
        'payment_id': 'p',
        'receipt_no': 7,
        'paid_at': '2026-11-18T04:00:00Z',
        'amount': 4050,
        'method': 'cash',
        'gym_name': 'Peak Fitness',
        'member_name': 'Pema',
        'plan_name': 'Gym',
        'list_price': 4500,
        'offer_name': 'Student',
        'discount_reason': 'ID seen',
      });
      expect(r.lines, containsAll([('Full price', 'Nu. 4,500'), ('Discount', '- Nu. 450 (Student: ID seen)')]));
      expect(r.message, contains('Discount: - Nu. 450'));
    });

    testWidgets('picking an offer sets the amount; less without one needs a reason', (tester) async {
      final form = GlobalKey<FormState>();
      PackageSale? sale;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          gymPlansProvider.overrideWith((ref, q) async => plans),
          gymOffersProvider.overrideWith((ref, id) async => const [student, couple]),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: Form(
                key: form,
                child: PackageFields(venueId: 'g1', start: day(0), initialPlanId: 'p1', onChanged: (s) => sale = s),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(sale?.amount, 1500);
      expect(find.text('Offer'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextFormField, 'Amount received'), '1000');
      await tester.pumpAndSettle();
      expect(find.text('Reason for the discount *'), findsOneWidget);
      expect(form.currentState!.validate(), isFalse);
      await tester.pumpAndSettle();
      expect(find.text('Say why they pay less (or pick an offer)'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextFormField, 'Reason for the discount *'), 'Referred by Sonam');
      await tester.pumpAndSettle();
      expect(sale?.discountDetails, {'reason': 'Referred by Sonam'});
      expect(tester.takeException(), isNull);
    });

    testWidgets('the offers page: the offers, and the month\'s discounts', (tester) async {
      await show(tester, const OffersScreen(venueId: 'g1'), with_: [
        ...overrides(),
        gymOffersProvider.overrideWith((ref, id) async => const [student, couple]),
        gymSubscriptionsProvider.overrideWith((ref, id) async => [sold('a', 4050, 4500, offer: 'Student'), sold('b', 1200, 1500)]),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Student'), findsWidgets);
      expect(find.text('Nu. 500 off'), findsOneWidget);
      expect(find.text('2 discounts, Nu. 750 off'), findsOneWidget);
      expect(find.text('1 without a reason'), findsOneWidget);
      expect(find.text('- Nu. 450'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a link to one offer (the search) opens it', (tester) async {
      await show(tester, const OffersScreen(venueId: 'g1', openId: 'o2'), with_: [
        ...overrides(),
        gymOffersProvider.overrideWith((ref, id) async => const [student, couple]),
        gymSubscriptionsProvider.overrideWith((ref, id) async => const []),
      ]);
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byType(Dialog), matching: find.text('Couple')), findsWidgets, reason: 'its title and name');
      expect(find.descendant(of: find.byType(Dialog), matching: find.text('Student')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('expenses and profit', () {
    test('each month: payments in (no refunds), expenses out, what\'s left', () {
      final today = DateTime(2026, 11, 18);
      final months = moneyByMonth(
        [payment(5000, DateTime(2026, 11, 2)), payment(3000, DateTime(2026, 11, 9)), payment(900, DateTime(2026, 11, 3), status: 'refunded'),
         payment(2000, DateTime(2026, 10, 5))],
        [expense('r', ExpenseCategory.rent, 6000, DateTime(2026, 11, 1)), expense('s', ExpenseCategory.salaries, 4000, DateTime(2026, 10, 30))],
        today,
      );
      expect(months, hasLength(12));
      expect(months.first.month, DateTime(2025, 12));
      expect((months.last.income, months.last.expenses, months.last.profit), (8000, 6000, 2000));
      expect(months[10].profit, -2000, reason: 'October lost money');
    });

    test('what the money went on, the largest first', () {
      final month = DateTime(2026, 11);
      final spent = spentByCategory([
        expense('a', ExpenseCategory.supplies, 300, DateTime(2026, 11, 2)),
        expense('b', ExpenseCategory.rent, 6000, DateTime(2026, 11, 1)),
        expense('c', ExpenseCategory.supplies, 200, DateTime(2026, 11, 9)),
        expense('d', ExpenseCategory.rent, 6000, DateTime(2026, 10, 1)),
      ], month);
      expect(spent, [(ExpenseCategory.rent, 6000), (ExpenseCategory.supplies, 500)]);
    });

    test('an expense sent to the database, tidied', () {
      final json = ExpenseDetails(spentOn: DateTime(2026, 11, 8), category: ExpenseCategory.utilities, amount: 1200, paidTo: '  ').toJson();
      expect(json, {'spent_on': '2026-11-08', 'category': 'utilities', 'amount': 1200, 'method': 'cash', 'paid_to': null, 'note': null});
    });

    testWidgets('the month in, out and left, the 12 months, and the expenses', (tester) async {
      await show(tester, const ExpensesScreen(venueId: 'g1'), with_: [
        ...overrides(),
        gymExpensesProvider.overrideWith((ref, id) async => [expense('r', ExpenseCategory.rent, 6000, day(0))]),
        venuePaymentsProvider.overrideWith((ref, q) async => [payment(8000, day(0))]),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Payments in'), findsOneWidget);
      expect(find.text('Profit'), findsWidgets);
      expect(find.text('Rent'), findsWidgets);
      expect(find.text('Last 12 months'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the front desk, who doesn\'t see income, can\'t open it', (tester) async {
      await show(tester, const ExpensesScreen(venueId: 'g1'), with_: [
        ...overrides(role: VenueRole.staff),
        gymExpensesProvider.overrideWith((ref, id) async => const []),
      ]);
      await tester.pumpAndSettle();
      expect(find.text("Your role here doesn't include this"), findsOneWidget);
    });
  });
}
