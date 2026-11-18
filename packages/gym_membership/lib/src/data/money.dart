import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health_pro_core/health_pro_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'gym_models.dart';

// ─── Offers and discounts (20261118000010_gym_discounts.sql) ───────────────

enum OfferKind {
  percent('percent'),
  amount('amount');

  const OfferKind(this.value);
  final String value;

  static OfferKind from(String? value) => value == 'amount' ? amount : percent;
}

/// One of a gym's offers: so much off a package, as a percentage or an
/// amount ('Student', 10% off).
class GymOffer {
  final String id;
  final String venueId;
  final String name;
  final OfferKind kind;
  final int value;
  final bool isActive;

  const GymOffer({
    required this.id,
    required this.venueId,
    required this.name,
    required this.kind,
    required this.value,
    this.isActive = true,
  });

  /// '10% off', 'Nu. 500 off'.
  String get label => kind == OfferKind.percent ? '$value% off' : '${formatNu(value)} off';

  /// What a package of [fullPrice] costs with it; never below nothing.
  int priceFrom(int fullPrice) {
    final price = kind == OfferKind.percent ? (fullPrice * (100 - value) / 100).round() : fullPrice - value;
    return price < 0 ? 0 : price;
  }

  factory GymOffer.fromJson(Map<String, dynamic> json) => GymOffer(
        id: json['id'] as String,
        venueId: json['venue_id'] as String,
        name: json['name'] as String,
        kind: OfferKind.from(json['kind'] as String?),
        value: (json['value'] as num).toInt(),
        isActive: json['is_active'] as bool? ?? true,
      );
}

/// The discount sent with a sale (gym_add_membership's), or null for none:
/// the [offer] picked and the [reason] typed.
Map<String, dynamic>? discountJson({GymOffer? offer, String? reason}) {
  final why = reason?.trim();
  if (offer == null && (why == null || why.isEmpty)) return null;
  return {if (offer != null) 'offer_id': offer.id, if (why != null && why.isNotEmpty) 'reason': why};
}

/// Bhutan's month of a moment.
DateTime _monthOf(DateTime moment) {
  final d = BhutanTime.toBhutan(moment);
  return DateTime(d.year, d.month);
}

/// Packages of [subs] sold for less than their full price in [month],
/// latest first.
List<GymSubscription> discountedIn(Iterable<GymSubscription> subs, DateTime month) {
  final found = subs
      .where((s) => s.discount > 0 && s.activatedAt != null && _monthOf(s.activatedAt!) == DateTime(month.year, month.month))
      .toList();
  return found..sort((a, b) => b.activatedAt!.compareTo(a.activatedAt!));
}

/// How many discounts, how much in all, and how many with neither an offer
/// nor a reason.
({int count, int total, int unexplained}) discountTotals(Iterable<GymSubscription> discounted) => (
      count: discounted.length,
      total: discounted.fold(0, (sum, s) => sum + s.discount),
      unexplained: discounted.where((s) => s.offerName == null && (s.discountReason ?? '').trim().isEmpty).length,
    );

/// A discount's why: 'Student: College ID seen', 'Referred by Sonam', or
/// 'No reason given'.
String discountWhy(GymSubscription s) {
  final parts = [s.offerName, s.discountReason].where((p) => p != null && p.trim().isNotEmpty).join(': ');
  return parts.isEmpty ? 'No reason given' : parts;
}

// ─── Expenses (20261118000011_gym_expenses.sql) ─────────────────────────────

enum ExpenseCategory {
  rent('rent', 'Rent'),
  salaries('salaries', 'Salaries'),
  equipment('equipment', 'Equipment'),
  maintenance('maintenance', 'Repairs & maintenance'),
  utilities('utilities', 'Electricity, water & internet'),
  supplies('supplies', 'Supplies'),
  marketing('marketing', 'Marketing'),
  other('other', 'Other');

  const ExpenseCategory(this.value, this.label);
  final String value;
  final String label;

  static ExpenseCategory from(String? value) => values.firstWhere((c) => c.value == value, orElse: () => other);
}

/// What the gym spent: on what, when, how much, how and to whom.
class GymExpense {
  final String id;
  final String venueId;
  final DateTime spentOn;
  final ExpenseCategory category;
  final int amount;
  final PaymentMethod method;
  final String? paidTo;
  final String? note;

  const GymExpense({
    required this.id,
    required this.venueId,
    required this.spentOn,
    required this.category,
    required this.amount,
    this.method = PaymentMethod.cash,
    this.paidTo,
    this.note,
  });

  ExpenseDetails get details =>
      ExpenseDetails(spentOn: spentOn, category: category, amount: amount, method: method, paidTo: paidTo, note: note);

  factory GymExpense.fromJson(Map<String, dynamic> json) => GymExpense(
        id: json['id'] as String,
        venueId: json['venue_id'] as String,
        spentOn: BhutanTime.parseDate(json['spent_on'] as String),
        category: ExpenseCategory.from(json['category'] as String?),
        amount: (json['amount'] as num).toInt(),
        method: PaymentMethod.from(json['method'] as String? ?? 'cash'),
        paidTo: json['paid_to'] as String?,
        note: json['note'] as String?,
      );
}

/// What the owner types about an expense (gym_save_expense's details).
class ExpenseDetails {
  final DateTime spentOn;
  final ExpenseCategory category;
  final int amount;
  final PaymentMethod method;
  final String? paidTo;
  final String? note;

  const ExpenseDetails({
    required this.spentOn,
    required this.category,
    required this.amount,
    this.method = PaymentMethod.cash,
    this.paidTo,
    this.note,
  });

  static String? _clean(String? v) => v == null || v.trim().isEmpty ? null : v.trim();

  Map<String, dynamic> toJson() => {
        'spent_on': '${spentOn.year.toString().padLeft(4, '0')}-${spentOn.month.toString().padLeft(2, '0')}-'
            '${spentOn.day.toString().padLeft(2, '0')}',
        'category': category.value,
        'amount': amount,
        'method': method.value,
        'paid_to': _clean(paidTo),
        'note': _clean(note),
      };
}

// ─── Profit ─────────────────────────────────────────────────────────────────

/// One month's money: payments in, expenses out, and what's left.
class MonthMoney {
  final DateTime month;
  final int income;
  final int expenses;

  const MonthMoney({required this.month, required this.income, required this.expenses});

  int get profit => income - expenses;
}

/// The [months] months to [today]'s, oldest first: payments in (refunds
/// left out) and expenses out.
List<MonthMoney> moneyByMonth(Iterable<Payment> payments, Iterable<GymExpense> expenses, DateTime today, {int months = 12}) {
  final first = DateTime(today.year, today.month - months + 1);
  final income = <DateTime, int>{};
  final spent = <DateTime, int>{};
  for (final p in payments) {
    if (p.status == 'refunded') continue;
    final m = _monthOf(p.createdAt);
    income[m] = (income[m] ?? 0) + p.amount;
  }
  for (final e in expenses) {
    final m = DateTime(e.spentOn.year, e.spentOn.month);
    spent[m] = (spent[m] ?? 0) + e.amount;
  }
  return [
    for (var i = 0; i < months; i++)
      () {
        final m = DateTime(first.year, first.month + i);
        return MonthMoney(month: m, income: income[m] ?? 0, expenses: spent[m] ?? 0);
      }(),
  ];
}

/// [expenses] in [month], by category, the largest first.
List<(ExpenseCategory, int)> spentByCategory(Iterable<GymExpense> expenses, DateTime month) {
  final totals = <ExpenseCategory, int>{};
  for (final e in expenses) {
    if (e.spentOn.year == month.year && e.spentOn.month == month.month) totals[e.category] = (totals[e.category] ?? 0) + e.amount;
  }
  return [for (final t in totals.entries) (t.key, t.value)]..sort((a, b) => b.$2.compareTo(a.$2));
}

/// Expenses for Excel: every one in [expenses], with its month's totals as
/// they are.
Spreadsheet expensesSheet(Iterable<GymExpense> expenses) => Spreadsheet(
      sheetName: 'Expenses',
      headings: const ['Date', 'For', 'Amount (Nu.)', 'Paid with', 'Paid to', 'Note'],
      rows: [
        for (final e in expenses) [e.spentOn, e.category.label, e.amount, e.method.label, e.paidTo, e.note],
      ],
    );

// ─── Reading and saving ─────────────────────────────────────────────────────

final gymMoneyRepositoryProvider = Provider<GymMoneyRepository>((ref) => GymMoneyRepository(ref.watch(supabaseProvider)));

/// A gym's offers, those still offered first.
final gymOffersProvider = FutureProvider.family<List<GymOffer>, String>(
  (ref, venueId) => ref.watch(gymMoneyRepositoryProvider).offers(venueId),
);

/// A gym's expenses over the last 12 months, latest first.
final gymExpensesProvider = FutureProvider.family<List<GymExpense>, String>(
  (ref, venueId) {
    final today = BhutanTime.today();
    return ref.watch(gymMoneyRepositoryProvider).expenses(venueId, since: DateTime(today.year, today.month - 11, 1));
  },
);

class GymMoneyRepository {
  GymMoneyRepository(this._client);
  final SupabaseClient _client;

  Future<List<GymOffer>> offers(String venueId) async {
    final rows = await _client.from('gym_offers').select().eq('venue_id', venueId).order('is_active', ascending: false).order('name');
    return rows.map(GymOffer.fromJson).toList();
  }

  /// A new offer ([offerId] null) or changes to one; its id.
  Future<String> saveOffer(String venueId,
      {String? offerId, required String name, required OfferKind kind, required int value, bool isActive = true}) async {
    final id = await _client.rpc('gym_save_offer', params: {
      'venue_id': venueId,
      'offer_id': offerId,
      'name': name.trim(),
      'kind': kind.value,
      'value': value,
      'is_active': isActive,
    });
    return id as String;
  }

  Future<List<GymExpense>> expenses(String venueId, {required DateTime since}) async {
    final from = '${since.year.toString().padLeft(4, '0')}-${since.month.toString().padLeft(2, '0')}-${since.day.toString().padLeft(2, '0')}';
    final rows = await _client
        .from('gym_expenses')
        .select()
        .eq('venue_id', venueId)
        .gte('spent_on', from)
        .order('spent_on', ascending: false)
        .order('created_at', ascending: false);
    return rows.map(GymExpense.fromJson).toList();
  }

  /// A new expense ([expenseId] null) or changes to one; its id.
  Future<String> saveExpense(String venueId, ExpenseDetails details, {String? expenseId}) async {
    final id = await _client.rpc('gym_save_expense', params: {'venue_id': venueId, 'expense_id': expenseId, 'details': details.toJson()});
    return id as String;
  }

  Future<void> deleteExpense(String expenseId) => _client.rpc('gym_delete_expense', params: {'expense_id': expenseId});
}
