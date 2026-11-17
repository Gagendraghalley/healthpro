import 'package:flutter_test/flutter_test.dart';
import 'package:gym_membership/gym_membership.dart';
import 'package:gym_membership/src/data/dashboard_data.dart';
import 'package:health_pro_core/health_pro_core.dart';

final today = DateTime(2026, 11, 7); // a Saturday
DateTime day(int offset) => DateTime(today.year, today.month, today.day + offset);

GymSubscription sub(
  String member, {
  String status = SubscriptionStatus.active,
  int? from,
  int? to,
  String plan = 'Monthly',
  DateTime? activatedAt,
  DateTime? requestedAt,
  String? id,
}) =>
    GymSubscription(
      id: id ?? '$member-$status-$from-$to',
      venueId: 'g1',
      memberId: member,
      memberName: member,
      planName: plan,
      durationDays: 30,
      price: 1500,
      status: status,
      startDate: from == null ? null : day(from),
      endDate: to == null ? null : day(to),
      requestedAt: requestedAt ?? DateTime.utc(2026, 10, 1),
      activatedAt: activatedAt,
    );

Payment pay(int amount, DateTime bhutanDay, {String status = 'completed', String? forSub, String method = 'mbob'}) =>
    Payment.fromJson({
      'id': '$amount-$bhutanDay',
      'venue_id': 'g1',
      'module_key': gymModuleKey,
      'reference_id': forSub,
      'amount': amount,
      'method': method,
      'status': status,
      // An hour into that Bhutan day.
      'created_at': bhutanMidnightUtc(bhutanDay).add(const Duration(hours: 1)).toIso8601String(),
    });

void main() {
  test('members stand active, expired or waiting, once each', () {
    final standing = memberStanding([
      sub('ana', from: -5, to: 20), // covering today
      sub('bo', status: SubscriptionStatus.expired, from: -60, to: -31),
      sub('cy', status: SubscriptionStatus.pending), // only asked
      sub('di', from: -30, to: -1), // ended yesterday, not yet marked expired
      sub('ed', status: SubscriptionStatus.expired, from: -60, to: -31),
      sub('ed', from: -30, to: 0), // renewed: active
      sub('fa', from: 3, to: 33), // paid, starts later: active
    ], today);
    expect(standing.active, 3);
    expect(standing.expired, 2);
    expect(standing.waiting, 1);
    expect(standing.members, 5);
  });

  test('ending soon: within the window, not renewed, soonest first', () {
    final ending = endingWithin([
      sub('late', from: -20, to: 9),
      sub('soon', from: -25, to: 2),
      sub('renewed', from: -25, to: 2),
      sub('renewed', from: 3, to: 32), // paid after: not ending
      sub('far', from: -1, to: 40),
      sub('gone', status: SubscriptionStatus.expired, from: -40, to: -11),
    ], today, 30);
    expect(ending.map((s) => s.memberId), ['soon', 'late']);
    expect(ending.first.daysLeftOn(today), 3);
  });

  test('revenue by day for 7 days, Bhutan dates, completed payments only', () {
    final points = revenueSeries([
      pay(1500, today),
      pay(800, today),
      pay(2000, day(-6)),
      pay(9999, day(-7)), // before the week
      pay(500, today, status: 'refunded'),
    ], today, RevenueRange.week);
    expect(points, hasLength(7));
    expect(points.first.amount, 2000);
    expect(points.last.amount, 2300);
    expect(points.last.label, 'Sat');
    expect(points.fold<int>(0, (s, p) => s + p.amount), 4300);
  });

  test('revenue by week for 90 days and by month for a year', () {
    final quarter = revenueSeries([pay(100, day(-89)), pay(200, today)], today, RevenueRange.quarter);
    expect(quarter, hasLength(13));
    expect(quarter.first.start, day(-89));
    expect(quarter.last.end, today);
    expect(quarter.first.amount, 100);
    expect(quarter.last.amount, 200);

    final year = revenueSeries([pay(300, DateTime(2025, 12, 1)), pay(400, today)], today, RevenueRange.year);
    expect(year, hasLength(12));
    expect(year.first.label, 'Dec');
    expect(year.first.amount, 300);
    expect(year.last.label, 'Nov');
    expect(year.last.amount, 400);
    expect(revenueFrom(today), DateTime(2025, 12, 1));
  });

  test('recent activity: newest first, renewals told apart, payments when shown', () {
    final first = sub('ana', id: 's1', from: -40, to: -11, activatedAt: DateTime.utc(2026, 9, 27, 4));
    final renewal = sub('ana', id: 's2', from: -10, to: 19, activatedAt: DateTime.utc(2026, 10, 28, 4));
    final activity = recentActivity(
      subs: [first, renewal],
      checkIns: [
        GymCheckIn(id: 'c1', venueId: 'g1', memberId: 'ana', memberName: 'ana', checkedInAt: DateTime.utc(2026, 11, 7, 1)),
      ],
      payments: [pay(1500, DateTime(2026, 10, 28), forSub: 's2')],
    );
    expect(activity.first.kind, GymActivityKind.checkIn);
    expect(activity.first.text, 'ana checked in');
    final renewed = activity.firstWhere((a) => a.kind == GymActivityKind.renewed);
    expect(renewed.text, 'ana renewed Monthly · Nu. 1,500 by mBoB');
    expect(activity.where((a) => a.kind == GymActivityKind.joined).single.text, 'ana started Monthly');
    expect(recentActivity(subs: [first, renewal], checkIns: const [], limit: 2), hasLength(2));
  });

  // A member's check-in, an hour into that Bhutan day.
  GymCheckIn visit(int offset) => GymCheckIn(
        id: 'v$offset',
        venueId: 'g1',
        memberId: 'me',
        gymName: 'Druk Fitness Club',
        checkedInAt: bhutanMidnightUtc(day(offset)).add(const Duration(hours: 1)),
      );

  test("a member's visits by day and by week", () {
    final visits = [visit(0), visit(0), visit(-1), visit(-6), visit(-7), visit(-20), visit(-89), visit(-90)];
    final week = visitSeries(visits, today, RevenueRange.week);
    expect([for (final p in week) p.amount], [1, 0, 0, 0, 0, 1, 2]);
    final quarter = visitSeries(visits, today, RevenueRange.quarter);
    expect(quarter.fold<int>(0, (s, p) => s + p.amount), 7); // 90 days back is outside
  });

  test('income this month against the same days of last month', () {
    final change = incomeChangeMonthToDate([
      pay(1000, DateTime(2026, 11, 1)),
      pay(500, today),
      pay(9999, DateTime(2026, 11, 3), status: 'pending'), // not paid yet
      pay(1000, DateTime(2026, 10, 2)),
      pay(4000, DateTime(2026, 10, 8)), // after the 7th: not the same days
      pay(700, DateTime(2026, 9, 30)), // the month before
    ], today);
    expect(change, closeTo(0.5, 1e-9));

    // Nothing last month in those days: nothing to compare with.
    expect(incomeChangeMonthToDate([pay(1000, DateTime(2026, 11, 1))], today), isNull);

    // On the 31st, a short month counts to its own last day.
    expect(
      incomeChangeMonthToDate([pay(800, DateTime(2027, 3, 2)), pay(1000, DateTime(2027, 2, 28))], DateTime(2027, 3, 31)),
      closeTo(-0.2, 1e-9),
    );
  });

  test('the greeting follows the hour in Bhutan', () {
    expect(greetingAt(DateTime(2026, 11, 7, 6)), 'Good morning');
    expect(greetingAt(DateTime(2026, 11, 7, 13)), 'Good afternoon');
    expect(greetingAt(DateTime(2026, 11, 7, 19)), 'Good evening');
  });
}
