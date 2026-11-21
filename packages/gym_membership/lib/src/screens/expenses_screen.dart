import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health_pro_core/health_pro_core.dart';

import '../data/gym_repository.dart';
import '../data/money.dart';
import '../widgets/export_button.dart';
import '../widgets/gym_widgets.dart';
import '../widgets/package_fields.dart';

IconData _iconOf(ExpenseCategory c) => switch (c) {
      ExpenseCategory.rent => Icons.home_work_outlined,
      ExpenseCategory.salaries => Icons.badge_outlined,
      ExpenseCategory.equipment => Icons.fitness_center_rounded,
      ExpenseCategory.maintenance => Icons.build_outlined,
      ExpenseCategory.utilities => Icons.bolt_outlined,
      ExpenseCategory.supplies => Icons.inventory_2_outlined,
      ExpenseCategory.marketing => Icons.campaign_outlined,
      ExpenseCategory.other => Icons.receipt_long_outlined,
    };

/// Expenses and profit, for those who see income: a month's payments in,
/// expenses out and what's left; the last 12 months side by side; what the
/// money went on; and the month's expenses, to add, change or remove.
class ExpensesScreen extends ConsumerStatefulWidget {
  final String venueId;

  /// The expense to open (a link's `?open=`).
  final String? openId;

  const ExpensesScreen({super.key, required this.venueId, this.openId});

  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  late DateTime _month = () {
    final t = BhutanTime.today();
    return DateTime(t.year, t.month);
  }();

  ({String venueId, String moduleKey, DateTime from, DateTime to}) _paymentsQuery(DateTime today) => (
        venueId: widget.venueId,
        moduleKey: gymModuleKey,
        from: bhutanMidnightUtc(DateTime(today.year, today.month - 11, 1)),
        to: bhutanMidnightUtc(DateTime(today.year, today.month, today.day + 1)),
      );

  Future<void> _edit([GymExpense? expense]) async {
    final saved = await showAppDialog<bool>(
      context: context,
      builder: (_) => _ExpenseDialog(venueId: widget.venueId, expense: expense),
    );
    if (saved == true) ref.invalidate(gymExpensesProvider(widget.venueId));
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.venueId;
    final wide = MediaQuery.sizeOf(context).width >= 700;
    return GymStaffPage(
      venueId: id,
      title: 'Expenses & profit',
      permission: VenuePermission.income,
      builder: (context, access) {
        final today = BhutanTime.today();
        final query = _paymentsQuery(today);
        return OpenFromLink<GymExpense>(
          id: widget.openId,
          items: ref.watch(gymExpensesProvider(id)).valueOrNull,
          idOf: (e) => e.id,
          // On its month, so its line is behind it.
          open: (e) {
            setState(() => _month = DateTime(e.spentOn.year, e.spentOn.month));
            _edit(e);
          },
          child: AppPage(
            title: 'Expenses & profit',
            body: AsyncValueView<List<GymExpense>>(
              value: ref.watch(gymExpensesProvider(id)),
              onRetry: () => ref.invalidate(gymExpensesProvider(id)),
              data: (expenses) => AsyncValueView<List<Payment>>(
                value: ref.watch(venuePaymentsProvider(query)),
                onRetry: () => ref.invalidate(venuePaymentsProvider(query)),
                data: (payments) => _content(context, access, expenses, payments, today, wide),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _content(
      BuildContext context, VenueAccess access, List<GymExpense> expenses, List<Payment> payments, DateTime today, bool wide) {
    final brand = context.brand;
    final months = moneyByMonth(payments, expenses, today);
    final month = months.firstWhere((m) => m.month == _month, orElse: () => months.last);
    final first = months.first.month;
    final thisMonth = DateTime(today.year, today.month);
    final spent = spentByCategory(expenses, _month);
    final list = expenses.where((e) => e.spentOn.year == _month.year && e.spentOn.month == _month.month).toList();
    final profitColor = month.profit < 0 ? brand.danger : brand.success;

    final picker = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Month before',
          onPressed: _month.isAfter(first) ? () => setState(() => _month = DateTime(_month.year, _month.month - 1)) : null,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Text(formatMonth(_month), style: const TextStyle(fontWeight: FontWeight.w700)),
        IconButton(
          tooltip: 'Month after',
          onPressed: _month.isBefore(thisMonth) ? () => setState(() => _month = DateTime(_month.year, _month.month + 1)) : null,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(gymExpensesProvider(widget.venueId));
        ref.invalidate(venuePaymentsProvider(_paymentsQuery(today)));
      },
      child: ListView(
        padding: pagePadding(context, bottom: 40),
        children: [
          PageActions(
            text: 'What the gym spends, and what\'s left of the payments each month.',
            children: [
              ExportButton(
                compact: !wide,
                label: 'Export expenses',
                fileName: '${access.venue.name} expenses ${isoDateOf(today)}',
                load: () async => expensesSheet(expenses),
              ),
              FilledButton.icon(
                onPressed: _edit,
                style: FilledButton.styleFrom(minimumSize: PageActions.buttonSize),
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('Add expense'),
              ),
            ],
          ),
          Align(alignment: Alignment.centerLeft, child: picker),
          const SizedBox(height: 8),
          ConsoleCells(
            columns: wide ? 3 : 1,
            spacing: 16,
            children: [
              ConsoleKpi(
                icon: Icons.payments_outlined,
                color: brand.success,
                value: formatNu(month.income),
                count: month.income,
                format: (v) => formatNu(v.round()),
                label: 'Payments in',
                note: formatMonth(_month),
              ),
              ConsoleKpi(
                icon: Icons.receipt_long_outlined,
                color: brand.danger,
                value: formatNu(month.expenses),
                count: month.expenses,
                format: (v) => formatNu(v.round()),
                label: 'Expenses',
                note: '${list.length} ${list.length == 1 ? 'expense' : 'expenses'}',
              ),
              ConsoleKpi(
                icon: month.profit < 0 ? Icons.trending_down_rounded : Icons.trending_up_rounded,
                color: profitColor,
                value: month.profit < 0 ? '- ${formatNu(-month.profit)}' : formatNu(month.profit),
                label: month.profit < 0 ? 'Loss' : 'Profit',
                note: month.income == 0 ? 'No payments yet' : '${(month.profit * 100 / month.income).round()}% of payments',
              ),
            ],
          ),
          const SizedBox(height: 20),
          ResponsiveColumns(
            breakpoint: 1000,
            flex: (3, 2),
            first: [
              SectionTitle('Expenses in ${formatMonth(_month)}'),
              if (list.isEmpty)
                EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'No expenses this month',
                  message: 'Add rent, salaries, equipment and the rest as you pay them, to see the gym\'s profit.',
                  actionLabel: 'Add an expense',
                  onAction: _edit,
                )
              else
                SectionCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var i = 0; i < list.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        _ExpenseRow(expense: list[i], onTap: () => _edit(list[i])),
                      ],
                    ],
                  ),
                ),
            ],
            second: [
              const SectionTitle('What it went on'),
              SectionCard(
                padding: const EdgeInsets.all(16),
                child: spent.isEmpty
                    ? Text('Nothing spent in ${formatMonth(_month)}.', style: TextStyle(color: brand.muted))
                    : Column(
                        children: [
                          for (final (category, amount) in spent)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(_iconOf(category), size: 18, color: brand.muted),
                                      const SizedBox(width: 8),
                                      Expanded(child: Text(category.label)),
                                      Text(formatNu(amount), style: const TextStyle(fontWeight: FontWeight.w700)),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: amount / month.expenses,
                                      minHeight: 6,
                                      color: brand.danger,
                                      backgroundColor: brand.danger.withValues(alpha: 0.12),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
              ),
              const SectionTitle('Last 12 months'),
              SectionCard(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  children: [
                    _MonthLine.heading(context),
                    for (final m in months.reversed)
                      _MonthLine(month: m, selected: m.month == _month, onTap: () => setState(() => _month = m.month)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// '2026-11-18'.
String isoDateOf(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// One month in the 12-month table: in, out, and what's left.
class _MonthLine extends StatelessWidget {
  final MonthMoney? month;
  final bool selected;
  final VoidCallback? onTap;

  const _MonthLine({required this.month, this.selected = false, this.onTap});

  static Widget heading(BuildContext context) => const _MonthLine(month: null);

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final m = month;
    final style = m == null ? TextStyle(color: brand.muted, fontSize: 12, fontWeight: FontWeight.w700) : const TextStyle(fontSize: 13.5);
    Widget cell(String text, {Color? color, bool bold = false}) => Expanded(
          flex: 3,
          child: Text(text,
              textAlign: TextAlign.end,
              style: style.copyWith(color: color, fontWeight: bold ? FontWeight.w700 : null)),
        );
    final profit = m?.profit ?? 0;
    return InkWell(
      onTap: onTap,
      child: Container(
        color: selected ? brand.highlight.withValues(alpha: 0.08) : null,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(flex: 3, child: Text(m == null ? 'Month' : formatMonth(m.month), style: style)),
            cell(m == null ? 'In' : formatNu(m.income)),
            cell(m == null ? 'Out' : formatNu(m.expenses)),
            cell(m == null ? 'Profit' : (profit < 0 ? '- ${formatNu(-profit)}' : formatNu(profit)),
                color: m == null ? null : (profit < 0 ? brand.danger : brand.success), bold: m != null),
          ],
        ),
      ),
    );
  }
}

class _ExpenseRow extends StatelessWidget {
  final GymExpense expense;
  final VoidCallback onTap;

  const _ExpenseRow({required this.expense, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final e = expense;
    final sub = [formatDate(e.spentOn), if (e.paidTo != null) e.paidTo!, e.method.label, if (e.note != null) e.note!].join(' · ');
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: brand.danger.withValues(alpha: 0.1),
              child: Icon(_iconOf(e.category), size: 18, color: brand.readable(brand.danger)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.category.label, style: TextStyle(fontWeight: FontWeight.w600, color: brand.ink)),
                  Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: brand.muted, fontSize: 12.5)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(formatNu(e.amount), style: TextStyle(fontWeight: FontWeight.w700, color: brand.ink)),
          ],
        ),
      ),
    );
  }
}

/// A new expense ([expense] null) or changes to one: the day, what for, how
/// much, how it was paid, to whom, and a note. Deleting is here too. True
/// once saved or deleted.
class _ExpenseDialog extends ConsumerStatefulWidget {
  final String venueId;
  final GymExpense? expense;

  const _ExpenseDialog({required this.venueId, this.expense});

  @override
  ConsumerState<_ExpenseDialog> createState() => _ExpenseDialogState();
}

class _ExpenseDialogState extends ConsumerState<_ExpenseDialog> {
  final _form = GlobalKey<FormState>();
  late final ExpenseDetails? _old = widget.expense?.details;
  late DateTime _on = _old?.spentOn ?? BhutanTime.today();
  late ExpenseCategory? _category = _old?.category;
  late PaymentMethod _method = _old?.method ?? PaymentMethod.cash;
  late final _amount = TextEditingController(text: _old == null ? '' : '${_old.amount}');
  late final _paidTo = TextEditingController(text: _old?.paidTo ?? '');
  late final _note = TextEditingController(text: _old?.note ?? '');
  bool _saving = false;
  bool _pickCategory = false;

  bool get _editing => widget.expense != null;

  @override
  void dispose() {
    for (final c in [_amount, _paidTo, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final valid = _form.currentState!.validate();
    if (_category == null) setState(() => _pickCategory = true);
    if (!valid || _category == null) return;
    final details = ExpenseDetails(
      spentOn: _on,
      category: _category!,
      amount: int.parse(_amount.text.trim()),
      method: _method,
      paidTo: _paidTo.text,
      note: _note.text,
    );
    setState(() => _saving = true);
    final ok = await runAction(context, () async {
      await ref.read(gymMoneyRepositoryProvider).saveExpense(widget.venueId, details, expenseId: widget.expense?.id);
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) return;
    showFeedback(context, _editing ? 'Saved' : 'Expense added');
    Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    final sure = await confirmAction(
      context,
      title: 'Delete this expense?',
      message: '${widget.expense!.category.label}, ${formatNu(widget.expense!.amount)} on ${formatDate(widget.expense!.spentOn)}. '
          'It stays in the activity log.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!sure || !mounted) return;
    final ok = await runAction(context, () => ref.read(gymMoneyRepositoryProvider).deleteExpense(widget.expense!.id));
    if (ok && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final today = BhutanTime.today();
    final brand = context.brand;
    Widget label(String text) => Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6),
          child: Text(text, style: TextStyle(fontWeight: FontWeight.w600, color: brand.ink)),
        );
    return AlertDialog(
      title: Text(_editing ? 'Expense' : 'New expense'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DateField(
                  label: 'Day it was spent',
                  value: _on,
                  required: true,
                  firstDate: DateTime(today.year - 2),
                  lastDate: today,
                  onChanged: (d) => setState(() => _on = d ?? _on),
                ),
                label('What it was for *'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in ExpenseCategory.values)
                      ChoiceChip(
                        avatar: Icon(_iconOf(c), size: 16),
                        label: Text(c.label),
                        selected: _category == c,
                        onSelected: (_) => setState(() {
                          _category = c;
                          _pickCategory = false;
                        }),
                      ),
                  ],
                ),
                if (_pickCategory)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('Choose what it was for', style: TextStyle(color: brand.danger, fontSize: 12)),
                  ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _amount,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Amount *', prefixText: 'Nu. '),
                  validator: (v) => Validators.wholeNumber(v, min: 1, max: 10000000),
                ),
                label('Paid with'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final m in PaymentMethod.values)
                      ChoiceChip(label: Text(m.label), selected: _method == m, onSelected: (_) => setState(() => _method = m)),
                  ],
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _paidTo,
                  maxLength: 100,
                  decoration: const InputDecoration(labelText: 'Paid to', hintText: 'The landlord, a trainer, a shop...'),
                ),
                TextFormField(
                  controller: _note,
                  maxLength: 500,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Note', hintText: 'November rent, new dumbbells...'),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        if (_editing)
          TextButton(
            onPressed: _saving ? null : _delete,
            style: TextButton.styleFrom(foregroundColor: brand.danger),
            child: const Text('Delete'),
          ),
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _save, child: Text(_editing ? 'Save' : 'Add')),
      ],
    );
  }
}
